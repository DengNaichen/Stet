# Watercolor Blue dictation indicator

Status: active. macOS only.

## Approved appearance

Watercolor Blue is the default for a missing or unknown theme preference. All six
existing themes remain available; a saved selection is preserved. All seven themes
use the same native circular renderer, audio response, Thinking animation and
glass button arrangement. Each retains its own appearance card. iOS behavior is unchanged.

The source of truth is the user's live browser controls captured on 2026-09-11 at
`http://127.0.0.1:8765/?variant=detail&size=circle`, not the HTML file's defaults:

| Parameter | Approved value |
| --- | --- |
| Orb diameter | 64 pt |
| Flow speed | 1.25× |
| Pigment granulation | 0.14 |
| Interlayer flow | 0.77 |
| Silence waves | Enabled |
| Preview level | 0.60; replaced by live normalized voice level in the app |
| Simulation / microphone / pause controls | All off in the captured browser |

The palette stays pale blue, white, light blue and dense blue in every state.
Granulation changes pigment concentration and wet edges, rather than adding a
noise overlay. Broad counter-turning fields and an independent white wash let
the color layers pass through each other.

For the other six themes, reuse the existing three swatches in their fixed
`idle` order as ground, interlayer and pigment. Dilute them toward the same paper
white to create lighter washes; mix pigment with the ground for its denser region.
Color roles remain fixed when entering Thinking. Watercolor Blue retains the exact
approved browser colors rather than going through this derived palette mapping.

## Session behavior

- **Starting / listening:** 64 pt. Normalized audio level drives the
  approved response: energy attack 55 ms / release 320 ms; pigment tone attack
  120 ms / release 580 ms; velocity follows `1.25 × (1 + 4 × energy)` over 240 ms.
  The orb and buttons do not scale with microphone volume.
- **A pause while listening:** stays in listening. After at least 650 ms of
  quiet input and low residual energy, gentle waves blend in over 600 ms. Their
  amplitudes and speed vary every 2.8–4.6 seconds; both waves travel in the same
  direction. They fade out over 120 ms when speech resumes.
- **Processing / Thinking:** the same paint shrinks to 44 pt. The input becomes
  `0.10 + 0.06 × sin(2πt / 2.6)`, and the deformation amplitude is 40% of the
  speaking field. Transition time constant is 115 ms. Capture the existing paint
  phase as an anchor and blend deformation around it. No new hue, rotation,
  fake progress bar, or randomized movement. The microphone does not drive this
  state. Cancel stays available; Finish is disabled because capture has ended.
- **Result / hidden:** stop rendering after dismissal. Existing clipboard and
  error surfaces retain their behavior.
- **Reduce Motion:** a static paint sample, immediate state size and final
  button placement. Labels and controls still reflect the session state.

The audio analyzer supplies unwindowed mono RMS alongside its existing level.
Watercolor uses the browser's microphone mapping,
`sqrt(clamp((RMS - 0.004) / 0.12, 0, 1))`, so ordinary low background input can
enter the approved quiet-wave state. Explicit normalized preview inputs remain
unchanged. The legacy perceptual dB measurement remains available to other consumers;
all seven native orb themes share the browser response. No new FFT-to-visual
mapping, capture gain, or recognition behavior is introduced.

## Native button arrangement

Each glass button is 28 pt, its circular target is 44 pt, and its symbol is 12 pt.
While the main orb shrinks 64 → 44 pt, both buttons and their symbols shrink by the
same continuous ratio: buttons reach 19.25 pt and symbols 8.25 pt. The surrounding
padding grows to preserve each 44 pt hit target throughout the transition.
On macOS 26 use a shared Liquid Glass container; older supported systems use a
material background. The approved native lab settings are:

| Parameter | Value |
| --- | --- |
| Trajectory | Downward cubic Bézier swing |
| Horizontal reach | 60.15538985143712 pt |
| Final drop | 12.6339011004039 pt |
| Bend | 11.88852372917651 pt |
| Duration | 0.55 s, smoothstep easing |
| Glass fusion spacing | 11.56007428520794 pt |
| Selected lab preview progress | 0.8643167688116247 |

The selected lab pose is the fully open, interactive product endpoint. Product
progress 0–1 samples the original curve from 0 to that saved pose; this preserves
the chosen geometry without leaving the controls in a noninteractive preview
state. Button targets stay within the existing 370 × 106 pt window.

## Theme artwork

Asset: `StetMac/Assets.xcassets/watercolorBlue.imageset/watercolorBlue.png`.
Generated with the built-in imagegen tool, then copied into the asset catalog.
No existing artwork was replaced. Final prompt:

> Use case: stylized-concept. Generate one finished portrait illustration for the Watercolor Blue appearance theme card in the Stet macOS app, aspect ratio 4:5. The card should express the same material as a fluid blue watercolor orb: a broad, elegant ocean swell, seen from overhead, formed by azure blue watercolor pigment on pale icy blue cotton paper. Deep blue pools merge into lighter cyan washes; a generous winding band of soft white separates the deep blue from the very pale blue ground. Visible fine pigment granulation belongs inside the paint, with soft wet-on-wet edges and restrained paper texture. Large connected shapes, calm open areas, one or two sweeping wave forms with a lively inward curl, rich but not dark. Beautiful, tactile, polished fine-art print with natural daylight, readable when cropped to a small portrait card. Fill the entire image, no frame. No text, no letters, no logos, no app UI, no orb sphere, no random speckles overlaid on top, no tiny fragmented swirls, no purple or green.

## Attribution

Base flow adapted from [Rare UI's Fluid Orb](https://www.rareui.com/components/fluidorb)
by Swami Malode. The [upstream MIT license](https://github.com/swamimalode07/rare-ui/blob/main/LICENSE)
is included as `StetVisuals/RareUI-LICENSE.txt` and bundled with the framework.

## Initial implementation validation (2026-09-11)

| Command | Result |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build` | Exit 2 (xcodebuild 65): this host has no development provisioning profile for `NaichengDeng.Stet.Debug`. |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make ci-build` | Exit 0. Swift, Metal, theme asset, and framework license resource compiled and packaged. |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | Exit 0. 550 tests in 82 suites passed, including RMS calibration, idle/Thinking separation, transition continuity, hit-target geometry, and all seven theme preferences. |
| `make lint` | Exit 0. SwiftLint and swift-format passed. |

Interactive verification used a temporary native host linked to the production
StetVisuals framework. Checked 64 pt listening and 44 pt Thinking on light/dark
backgrounds, Finish → Thinking with Finish disabled, Cancel → hidden while
Thinking, old Egg rendering and switching back to Watercolor, and the artwork at
the production card's portrait crop. Reduced Motion and interrupted transitions
were verified in state/geometry tests. No live microphone session or signed
release was run in this validation; PCM input was exercised with synthetic audio.

The subsequent all-theme update removes the old capsule view and state styling.
`make test` again passed all 550 tests, and `make lint` passed. A native overview
rendered all seven theme previews with the same circular material; the existing
three swatches remain recognizable in each theme. Local packaging is a separate
Release build signed with the existing Developer ID identity and profile, without
publishing or replacing the installed application.
