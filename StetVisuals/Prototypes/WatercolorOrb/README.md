# Watercolor orb — throwaway visual prototype

Checkpoint of the standalone blue/white watercolor effect before capsule resizing.

Run from this directory: `python3 -m http.server 8766 --bind 127.0.0.1`, then open http://127.0.0.1:8766/ . No dependencies or build step.

Current audio input is normalized loudness only; FFT features and the fast pigment response discussed in the reference observations have not been implemented. Default pigment grain is 0.08. Attribution and source terms are embedded in index.html.

Design question for the next experiment: does this effect retain readable color layering and motion inside the macOS capsule's 80 × 40 logical-point footprint? Dimensions come from MacDictationPanelConstants.Layout (controlHeight 40, aspect ratio 2). The HTML is an optical study, not a native Metal or glass integration.

Kept on the codex/watercolor-capsule-prototype branch, outside the production app. Reference frame sheets remain in the local analysis artifact directory and are not included here.
