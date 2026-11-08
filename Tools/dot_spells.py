"""dot_spells.py - Write DotSpells.lua: the player's single-target damage-over-time
spells the DoT kill estimate tracks (#175, docs/DOT-KILL-PLAN.md section 5), from
the client's own tables. No tooltip parsing: every number comes from SpellEffect,
SpellMisc, SpellDuration and SpellLevels.

- The universe: class spells (SkillLineAbility rows with a class mask), plus the
  spells their targeted Effect 64 (trigger spell) effects trigger.
- SUPPORTED names the families tracked, by aura name. Nothing joins on its own:
  the other candidates (a periodic damage or leech aura on the enemy target,
  not channelled) are only reported, and joining is a reviewed edit with a
  fixture in tests/test_dotspells.lua.
- A supported row is refused (the script fails) when its description uses a
  formula variable ($<...>) other than its family's reviewed exceptions, when
  it's channelled, or when it doesn't have exactly one periodic effect.

Reads the local wago.tools exports (References/Forever/db, fetched once per
build with References/Tools/Wago/wago.py get SpellEffect SpellMisc
SpellDuration SpellLevels SpellName Spell SkillLineAbility). Every table must
be from the same build. Never fetches anything itself.

Usage (from the repo root):
    python Tools/dot_spells.py                  # the newest saved build
    python Tools/dot_spells.py 1.60.1.70862
    python Tools/dot_spells.py --report         # also list the candidates left out
"""
import csv
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "..", "..", "References", "Forever", "db")
OUT = os.path.join(HERE, "..", "DotSpells.lua")
TABLES = ["spelleffect", "spellmisc", "spellduration", "spelllevels", "spellname", "spell",
          "skilllineability"]

# The supported families, by aura name, each with the formula variables its
# description may use (reviewed: they belong to a part we don't track).
SUPPORTED = {
    "Corruption": (),
    "Shadow Word: Pain": (),
    "Bane of Agony": (),
    "Immolate": ("mult",),        # ${$m2*$<mult>}: the direct part only; the DoT is $o1
    "Siphon Life": (),
    "Moonfire": (),
    "Insect Swarm": (),
    "Rend": (),
    "Rip": (),
    "Rupture": ("bloodS",),       # extra duration only ((8+$<bloodS>) secs): more ticks, errs low
    "Garrote": (),
    "Rake": (),
    "Pounce Bleed": (),
    "Serpent Sting": (),
    "Flame Shock": (),
    "Devouring Plague": (),
    "Holy Fire": (),
}

AURA_PERIODIC_DAMAGE, AURA_PERIODIC_LEECH = 3, 53
EFFECT_APPLY_AURA, EFFECT_TRIGGER_SPELL = 6, 64
TARGET_UNIT_TARGET_ENEMY = 6
CHANNEL_BITS = 0x4 | 0x40          # SpellMisc.Attributes_1: channelled, self-channelled
# SchoolMask bit -> GetSpellBonusDamage's index.
SCHOOL_INDEX = {1: 1, 2: 2, 4: 3, 8: 4, 16: 5, 32: 6, 64: 7}


def build_of(path):
    return re.search(r"-(\d+\.\d+\.\d+\.\d+)\.csv$", path).group(1)


def version(build):
    return tuple(int(x) for x in build.split("."))


def newest_build():
    files = glob.glob(os.path.join(DB, "forever-spelleffect-*.csv"))
    if not files:
        sys.exit("no SpellEffect export in %s: python References/Tools/Wago/wago.py get %s"
                 % (DB, " ".join(TABLES)))
    return max((build_of(p) for p in files), key=version)


def rows(table, build):
    path = os.path.join(DB, "forever-%s-%s.csv" % (table, build))
    if not os.path.exists(path):
        sys.exit("missing %s: python References/Tools/Wago/wago.py get %s --build %s"
                 % (path, table, build))
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def num(v):
    if v is None or v == "":
        return 0.0
    return float(v)


def lua_num(v):
    if v == int(v):
        return "%d" % v
    return "%.10g" % v


def is_periodic(e):
    return (int(e["Effect"]) == EFFECT_APPLY_AURA
            and int(e["EffectAura"]) in (AURA_PERIODIC_DAMAGE, AURA_PERIODIC_LEECH)
            and int(e["ImplicitTarget_0"]) == TARGET_UNIT_TARGET_ENEMY)


def load(build):
    t = {name: rows(name, build) for name in TABLES}
    names = {int(r["ID"]): r["Name_lang"] for r in t["spellname"]}
    desc = {int(r["ID"]): (r.get("Description_lang") or "") for r in t["spell"]}
    effects = {}
    for e in t["spelleffect"]:
        if int(e["DifficultyID"] or 0) == 0:
            effects.setdefault(int(e["SpellID"]), []).append(e)
    misc = {int(r["SpellID"]): r for r in t["spellmisc"] if int(r["DifficultyID"] or 0) == 0}
    levels = {int(r["SpellID"]): r for r in t["spelllevels"] if int(r["DifficultyID"] or 0) == 0}
    duration = {int(r["ID"]): r for r in t["spellduration"]}
    classSpells = {int(r["Spell"]) for r in t["skilllineability"] if int(r["ClassMask"] or 0) != 0}
    return names, desc, effects, misc, levels, duration, classSpells


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    report = "--report" in sys.argv
    build = args[0] if args else newest_build()
    names, desc, effects, misc, levels, duration, classSpells = load(build)

    # The universe: class spells, and the auras their targeted triggers cast.
    trigger = {}                       # cast spellID -> triggered spellID
    for sid in classSpells:
        for e in effects.get(sid, []):
            if (int(e["Effect"]) == EFFECT_TRIGGER_SPELL
                    and int(e["ImplicitTarget_0"]) == TARGET_UNIT_TARGET_ENEMY
                    and int(e["EffectTriggerSpell"] or 0) != 0):
                trigger[sid] = int(e["EffectTriggerSpell"])
    universe = classSpells | set(trigger.values())

    def channelled(sid):
        m = misc.get(sid)
        return m is not None and int(m["Attributes_1"] or 0) & CHANNEL_BITS != 0

    auras, casts, errors, candidates = {}, {}, [], set()
    for sid in sorted(universe):
        periodic = [e for e in effects.get(sid, []) if is_periodic(e)]
        if not periodic:
            continue
        name = names.get(sid, "")
        if name not in SUPPORTED:
            if not channelled(sid):
                candidates.add(sid)
            continue
        problems = []
        if len(periodic) != 1:
            problems.append("%d periodic effects" % len(periodic))
        if channelled(sid):
            problems.append("channelled")
        variables = set(re.findall(r"\$<(\w+)>", desc.get(sid, "")))
        unreviewed = variables - set(SUPPORTED[name])
        if unreviewed:
            problems.append("formula variables %s" % sorted(unreviewed))
        m, lv = misc.get(sid), levels.get(sid)
        if m is None:
            problems.append("no SpellMisc row")
        if problems:
            errors.append("%s %d: %s" % (name, sid, ", ".join(problems)))
            continue
        e = periodic[0]
        d = duration.get(int(m["DurationIndex"] or 0))
        if d is None or int(d["Duration"]) <= 0 or int(e["EffectAuraPeriod"]) <= 0:
            errors.append("%s %d: no duration or period" % (name, sid))
            continue
        mask = int(m["SchoolMask"] or 0)
        schools = [SCHOOL_INDEX[b] for b in sorted(SCHOOL_INDEX) if mask & b]
        if not schools or mask & ~127:
            errors.append("%s %d: school mask %d" % (name, sid, mask))
            continue
        auras[sid] = {
            "name": name,
            "schoolMask": mask,
            "schools": schools,
            "period": int(e["EffectAuraPeriod"]) / 1000.0,
            "duration": int(d["Duration"]) / 1000.0,
            "maxDuration": int(d["MaxDuration"] or d["Duration"]) / 1000.0,
            "durationPerCombo": int(d["DurationPerResource"] or 0) / 1000.0,
            "base": num(e["EffectBasePointsF"]),
            "perLevel": num(e["EffectRealPointsPerLevel"]),
            "perCombo": num(e["EffectPointsPerResource"]),
            "coef": num(e["EffectBonusCoefficient"]),
            "baseLevel": int(lv["BaseLevel"]) if lv else 0,
            "maxLevel": int(lv["MaxLevel"]) if lv else 0,
            "spellLevel": int(lv["SpellLevel"]) if lv else 0,
        }
    if errors:
        sys.exit("refused:\n  " + "\n  ".join(errors))

    # Ranks: the lowest spellID of the same name is the family.
    family = {}
    for sid in sorted(auras):
        family.setdefault(auras[sid]["name"], sid)
    # Casts: a class spell that is itself a supported aura, or triggers one.
    for sid in sorted(classSpells):
        aura = sid if sid in auras else trigger.get(sid)
        if aura in auras and not channelled(sid):
            m = misc.get(sid)
            travel = m is not None and (num(m["Speed"]) > 0 or num(m["LaunchDelay"]) > 0)
            casts[sid] = (aura, travel)
    used = {a for a, _ in casts.values()}
    missing = sorted(set(SUPPORTED) - {auras[a]["name"] for a in used})
    if missing:
        sys.exit("supported families with no castable rank: %s" % ", ".join(missing))

    lines = [
        "-- DotSpells.lua: GENERATED by Tools/dot_spells.py from the client's SpellEffect,",
        "-- SpellMisc, SpellDuration, SpellLevels, SpellName, Spell and SkillLineAbility",
        "-- tables (build %s, wago.tools). Do not edit: re-run the script after a" % build,
        "-- new build. docs/DOT-KILL-PLAN.md section 5 has the rules.",
        "--",
        "-- aura[spellID]: one periodic effect, per tick. period, duration and the",
        "-- durations in seconds; schools are GetSpellBonusDamage indices.",
        "-- cast[spellID] = { aura spellID, travel }: what a SUCCEEDED applies.",
        "",
        "GlassUF = GlassUF or {}",
        "GlassUF.DotSpells = {",
        "    build = \"%s\"," % build,
        "    aura = {",
    ]
    for sid in sorted(auras):
        a = auras[sid]
        lines.append(
            "        [%d] = { name = %s, family = %d, schoolMask = %d, schools = { %s }, period = %s,"
            " duration = %s, maxDuration = %s, durationPerCombo = %s, base = %s, perLevel = %s,"
            " perCombo = %s, coef = %s, baseLevel = %d, maxLevel = %d, spellLevel = %d },"
            % (sid, '"%s"' % a["name"], family[a["name"]], a["schoolMask"],
               ", ".join(str(s) for s in a["schools"]), lua_num(a["period"]), lua_num(a["duration"]),
               lua_num(a["maxDuration"]), lua_num(a["durationPerCombo"]), lua_num(a["base"]),
               lua_num(a["perLevel"]), lua_num(a["perCombo"]), lua_num(a["coef"]),
               a["baseLevel"], a["maxLevel"], a["spellLevel"]))
    lines += ["    },", "    cast = {"]
    for sid in sorted(casts):
        aura, travel = casts[sid]
        lines.append("        [%d] = { %d, %s }, -- %s" % (sid, aura, "true" if travel else "false",
                                                         names.get(sid, "")))
    lines += ["    },", "}", ""]
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("wrote %s: %d auras, %d casts (build %s)" % (os.path.normpath(OUT), len(auras), len(casts), build))
    if report:
        print("candidates left out (not on the supported list):")
        for sid in sorted(candidates, key=lambda s: (names.get(s, ""), s)):
            variables = sorted(set(re.findall(r"\$<(\w+)>", desc.get(sid, ""))))
            print("  %-24s %7d%s" % (names.get(sid, "?"), sid,
                                      "  own scaling: " + ", ".join(variables) if variables else ""))


if __name__ == "__main__":
    main()
