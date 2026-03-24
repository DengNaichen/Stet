# Quickstart: OpenClaw Transcript Handoff

## Prerequisites

- macOS 26.0 development environment
- Stet project dependencies installed
- Local `openclaw` CLI available on `PATH`
- Local OpenClaw installation initialized and able to resolve its default agent
- Rewrite enabled in Stet if you want to validate the AI-route transcript path

## Build and Run

1. Open the macOS project in Xcode or build from the command line:
   ```bash
   xcodebuild -project apps/mac/Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build
   ```
2. Launch the app.
3. Open Settings and go to the Hotkey section.
4. Keep the existing dictation hotkey unchanged.
5. Assign a second hotkey for the OpenClaw route.
6. Open the AI settings and confirm rewrite is enabled if you want the OpenClaw route to receive rewritten output.

## Manual Verification

1. Trigger the original dictation hotkey and confirm the current focused app still receives injected text.
2. Trigger the OpenClaw hotkey and speak a short sentence.
3. Confirm the focused app is not typed into by Stet for the OpenClaw route.
4. Confirm the feature reports success or failure through the existing workflow surface, but does not mirror OpenClaw output into the capsule.
5. Verify the rewritten transcript is what OpenClaw receives, not the raw speech text.

## Failure Checks

1. Remove `openclaw` from `PATH` or point the app at a machine without the local install, then trigger the OpenClaw hotkey.
2. Confirm the feature surfaces a local handoff failure.
3. Disable or break the rewrite path, then confirm the feature surfaces a separate rewrite failure before handoff starts.

## Notes

- The feature uses the local OpenClaw CLI boundary, not a Swift SDK.
- The route uses OpenClaw's default agent resolution.
- OpenClaw output is owned by OpenClaw-side delivery, not by the Stet capsule UI.
