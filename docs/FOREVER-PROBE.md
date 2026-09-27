# Forever probe results: GlassUnitFrames

Runtime measurements on the live client, recorded with the build number. The API dump says what
exists; this file says what works. Addon-agnostic findings also belong in
`C:\Projects\References\PORTING-TBC-TO-FOREVER.md`.

## Probe 1: glass material rendering (build 1.60.1.70009, 2026-09-27)

Instrument: `Tools/GlassProbe`, one non-secure frame with fake values, textures from
`Tools/make_textures.py`. Screenshots taken by the owner over sandstone cobbles (Orgrimmar-like
bright warm scene). UI effective scale 0.71 on the owner's setup.

| Question | Result |
|---|---|
| All 35 construction steps (textures, masks, slicing, gradients, animation, model) | **All ran without error** |
| 9-slice via `SetTextureSliceMargins` + `SetTextureSliceMode` on a Texture | **Works**: rims and shadow scale cleanly to 360x66 and 66x66 |
| 9-slice on a **MaskTexture** | **Works**: corner radius holds on a non-square frame |
| `MaskTexture` on a `StatusBar:GetStatusBarTexture()` fill | **Works**: rounded at empty, 3%, 50% and 100%; the moving fill edge stays square, as expected |
| `SetGradient("VERTICAL", CreateColor(...), CreateColor(...))` | **Works** (colour objects) |
| `SetBlendMode("ADD")` gloss and sheen | **Works** |
| `AnimationGroup` Translation + Alpha on a masked texture, mask anchored to the frame | **Works**: the sheen stays clipped to the body as it moves |
| Uncompressed 32-bit TGA, bottom-left origin, power-of-two sizes, straight alpha with single-colour RGB | **Loads**; no visible halos on the rim or shadow |
| Pixel snapping (`snap off`) and `SetScale(0.8)` | No visible softening or shimmer on 1px lines at this UI scale |
| 3D `PlayerModel:SetUnit("player")` + `SetPortraitZoom(1)` called once at `PLAYER_LOGIN` | **Blank tile** |
| 2D `SetPortraitTexture(tex, "player")` called once at `PLAYER_LOGIN`, shown later | **Blank** |

Visual verdict on style 1: the bars read close to the mockup, but the frame body and rim read as
**a chrome bezel on smoked plastic**, not glass. The rim is too thick, too opaque and evenly grey.
The sheen at full alpha is too strong. This is an art problem, not a platform limit.

### Second run (same build, same session, after `/reload`)

| Question | Result |
|---|---|
| A texture file that **did not exist at client start** (`late.tga`, `rim2/3.tga`, `sheen2.tga`), deployed and followed by `/reload` | **Loads.** New texture files do not need a full restart on 70009. (A brand-new *addon folder* did need one to appear in the list; that was the first deploy.) |
| 3D portrait with SUF's refresh sequence on `PLAYER_ENTERING_WORLD` / `UNIT_MODEL_CHANGED` / `UNIT_PORTRAIT_UPDATE` + 1 s delayed refresh | **Works**: `GetModelFileID()` = 900914 |
| 2D `SetPortraitTexture(tex, "player")` refreshed the same way | **Works**, but the client returns its own **circular** portrait on black corners (`disableMasking` defaults to false). `GetTextureFileID()` returns nil for it: it is a generated render, not a file. |
| Screen / scale on the owner's setup | 3840x2160, UIParent effective scale 0.64 |

Style comparison: **style 3 (thick clear bevel) reads most like glass**, with the background
visible through the bevel and the top-edge highlight doing the work. Style 2's hairline rim is too
thin to register at 0.64 scale. Style 1 remains a chrome bezel.

### Third run: polish round (same build)

| Question | Result |
|---|---|
| `FontString:SetFont("Fonts\\ARIALN.TTF", …)`, a client-shipped font | **Works**; `GetFont()` reads back `Fonts\ARIALN.TTF` |
| `SetPortraitTexture(tex, "player", true)` (`disableMasking`) | **Works**: square portrait, but on an opaque **black** background |
| 3D `PlayerModel` portrait | Renders on a **transparent** background, so the glass tile shows behind the head |

**Settled look for the POC: style 4** (thick clear bevel with a brighter top lip, corner glints,
an inner-lip catch-light, cool light tint), **3D portrait**, **Arial Narrow** (font to be a
setting). Verdict on the POC's primary question: **the glass reads convincingly** on warm
sandstone and dark grass. The one visible gap against the mockup is true background blur, which
addons cannot do: the scene shows through the body sharp rather than frosted.
