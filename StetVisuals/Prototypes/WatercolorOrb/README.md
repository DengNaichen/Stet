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
