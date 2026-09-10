# Orb Glass Motion Lab

An independent macOS experiment for the cancel and confirm buttons emerging
from a circular watercolor orb. It lets us judge the trajectory together with
native Liquid Glass separation at the intended product size.

This project is intentionally outside `StetVisuals/`: the production Xcode
project automatically includes sources in that directory. The lab has its own
app target and does not change Stet's production UI.

## Run

Requires macOS 26+, Xcode 26+, and its Metal toolchain.

Open `OrbGlassMotionLab.xcodeproj`, select the `OrbGlassMotionLab` scheme and
`My Mac`, then Run. The generated project and shared scheme are checked in;
XcodeGen is only needed when changing `project.yml`.

From this directory:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project OrbGlassMotionLab.xcodeproj \
  -scheme OrbGlassMotionLab -configuration Debug \
  -derivedDataPath /tmp/orb-glass-motion-build build
open /tmp/orb-glass-motion-build/Build/Products/Debug/OrbGlassMotionLab.app
```

## Inspect

- Compare the actual-size and 2× native previews. The center is 64 pt; each
  button is 28 pt with a 44 pt hit area.
- Replay expansion, retract, or scrub the progress slider to inspect a specific
  moment. Buttons become clickable after expansion.
- Compare a straight path, a shallow upward arc, and a downward swing. Adjust
  the horizontal reach, final downward offset, and curve amplitude separately.
- Show the paths and adjust duration to judge timing. Playback samples the
  actual Bézier path every frame, using an ease-in/ease-out progress curve.
- Adjust glass spacing to inspect fusion and separation. Light, dark, and
  colored backgrounds make the native material easier to inspect.
- Hide the watercolor to inspect the underlying glass, or enable watercolor
  movement to judge the complete composition. The selected preset starts with
  watercolor movement enabled; turn it off to inspect the trajectory alone.

Each preview uses a shared `GlassEffectContainer` and stable glass identities.
The watercolor overlays the center glass, following Stet's existing
composition. See Apple's
[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
for the native material APIs.

## Selected preset — 2026-09-11

Captured from the only open native lab window after the user selected its
parameters. These exact values are now the launch defaults; the UI's integer
labels truncate the underlying slider values.

| Control | Saved value |
| --- | --- |
| Trajectory | Downward swing / 下摆 |
| Horizontal reach per side | 60.15538985143712 pt |
| Final downward offset | 12.6339011004039 pt |
| Curve amplitude | 11.88852372917651 pt |
| Glass fusion spacing | 11.56007428520794 pt |
| Duration | 0.55 s |
| Initial preview progress | 0.8643167688116247 (86.43167688116247%) |
| Background | Colored / 色块 |
| Show path | Off |
| Show watercolor | On |
| Animate watercolor | On |
| Orb / button / hit diameter | 64 / 28 / 44 pt |

The saved preview is an intermediate point on the curve. Its rendered button
positions therefore differ from the endpoint values above. Launch restores
that selected preview position; replay and expand still run to 100%. The
progress control retains its existing behavior, including button interaction
after full expansion.

## Scope and validation

The lab explores button motion and glass geometry. Button actions only update
local feedback. Thinking, recording, and audio analysis are not implemented.
The Metal watercolor port uses a fixed tone and optional time animation; it
does not replace the HTML experiment's audio behavior.

Built with Xcode 26.6 and launched on macOS 26.6.2. Both native previews and the
Metal material rendered successfully; background and watercolor movement
controls were observed working. The selected preset above was verified against
the native controls and a screenshot. The build's only warning
was the skipped App Intents metadata extraction for this app without App
Intents.

Prototype branch: `codex/watercolor-capsule-prototype`.

## Material attribution

`Sources/Watercolor.metal` ports the existing
`StetVisuals/Prototypes/WatercolorOrb/index.html` material, including our pigment
granulation and inter-layer flow changes. Its base flow derives from
[Rare UI's Fluid Orb](https://www.rareui.com/components/fluidorb), by Swami Malode.
