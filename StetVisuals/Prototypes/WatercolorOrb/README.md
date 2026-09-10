# Watercolor orb — throwaway visual prototype

Checkpoint of the standalone blue/white watercolor effect before capsule resizing.

Run from this directory: `python3 -m http.server 8766 --bind 127.0.0.1`, then open http://127.0.0.1:8766/ . No dependencies or build step.

Current audio input is normalized loudness only; FFT features and the fast pigment response discussed in the reference observations have not been implemented. Default pigment grain is 0.08. Attribution and source terms are embedded in index.html.

Design question for the next experiment: does this effect retain readable color layering and motion inside the macOS capsule's 80 × 40 logical-point footprint? Dimensions come from MacDictationPanelConstants.Layout (controlHeight 40, aspect ratio 2). The HTML is an optical study, not a native Metal or glass integration.

Kept on the codex/watercolor-capsule-prototype branch, outside the production app. Reference frame sheets remain in the local analysis artifact directory and are not included here.

## Capsule size experiment

`index.html` now provides three views via `?variant=actual` (default), `compare`, or `detail`. The original checkpoint is preserved byte-for-byte in `orb-baseline.html`.

The capsule renders at 80 × 40 CSS pixels (logical-point comparison at browser zoom 100%). The two placeholder side controls use 40 × 40 and spacing 18.144 from the native capsule layout. Device-pixel ratio is respected up to 2. Both shapes use one shader clock, loudness envelope, palette, and grain setting; only the mask and output aspect ratio change. This directly compresses the normalized flow into the capsule, without retuning the visual model. The detail view enlarges the actual capsule pixels 4×; it does not rerender at a larger resolution. The view switcher supports arrow keys and URL parameters.

Initial observation: broad pale-blue / white / blue bands remain legible at actual size; the pigment granularity and fine internal tonal variation are much less legible. Final acceptance is pending user review. No native app code was changed.

Validation: JavaScript syntax checked; all three browser views inspected, including actual-size and enlarged copies. Microphone remains opt-in; the simulated envelope can drive both shapes for comparison.

## Larger, rounder follow-up

Size presets are shareable as `&size=original` (80 × 40), `compact` (88 × 56), and `round` (96 × 64, default). Each uses a capsule radius of half its height. Side controls stay at 40 × 40. The extra height gives the large color bands more room; acceptance is pending user review. Rendering resolution and the 4× pixel view follow the selected dimensions. Size switching and simulated audio were checked in the browser with no console errors.

## Circular body with secondary actions

`size=circle` (default) renders a 64-diameter orb; `circleLarge` renders 72. Cancel and confirm have 32-diameter visible discs inside 44 × 44 hit areas. Their centers sit 12 below the orb center, with 12 horizontal pixels between visible edges. Hovering the group or focusing within it reveals the controls; touch pointers keep them visible. Buttons only show local layout-demo feedback. Original capsule remains selectable. Browser inspection verified 64 × 64 and 44 × 44 bounds, center offsets of ±60 horizontally and +12 vertically, feedback, and no console errors. Native app integration remains out of scope.

## Inter-layer flow

Added two broad counter-turning coordinate fields, a separately moving white wash, and wider blue transition blending. The layer-flow slider defaults to 0.8; 0 restores the previous color-field equations for comparison at the same time. This is procedural domain warping, not a fluid simulation. Geometry, pigment amount, and audio envelope remain as before. Checked the small orb and large preview, slider input, JavaScript syntax, and browser console. User visual acceptance is pending.
