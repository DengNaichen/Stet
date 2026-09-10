# App compatibility list

The macOS app downloads its paste compatibility list directly from GitHub:

https://raw.githubusercontent.com/DengNaichen/Stet/main/StetMac/Resources/app-compatibility.json

`StetMac/Resources/app-compatibility.json` is the single source for both the remotely distributed list and the bundled offline default. Entries identify apps whose posted paste command can be treated as completed when verification is unavailable or fails. This does not bypass input permissions or treat a failed event post as success. Recovery timings and paste behavior remain in Swift code.

## Maintaining the list

1. Add or remove the app's lowercase Bundle ID in `bundleIDs`.
2. Increment `revision`. Keep `schemaVersion` at 1.
3. Run `python3 scripts/validate-app-compatibility.py` and open a PR.
4. Merge after CI passes. GitHub serves the new file; no tag, DMG, or application release is needed for subsequent list changes.

To undo a bad entry, remove it and increment `revision` again. Do not restore an older revision number: clients ignore older or equal revisions. An empty list with a higher revision revokes all app-specific exceptions.

## Client behavior

The app loads the bundled list and a newer valid cache from Application Support before use. It checks GitHub in the background at launch and every 24 hours while running. Paste queries use only the in-memory set and never wait for networking. A successful refresh replaces the whole set and atomically saves the validated configuration. Invalid responses, unsupported schemas, HTTP errors, cancellation, and network or cache-write failures preserve the current list.

Settings → General → App Compatibility provides a manual check button. The button keeps its label and is disabled while checking. A fixed-height status area displays “Updated” after a successful check (including an already-current list), or an explicit failure message while retaining the current list. Settings and the paste workflow share the same store, so manual updates affect subsequent pastes immediately.

The request downloads the same public file for every user; it does not send transcripts, clipboard content, or installed app lists. The repository's HTTPS endpoint is the configuration trust source. GitHub unavailability or CDN caching can delay updates; existing cached/bundled behavior remains available.

One app release is required to introduce this loader. Older versions, including 0.5.11, still use their compiled list. New compatibility behaviors or schema changes may also require an app release.
