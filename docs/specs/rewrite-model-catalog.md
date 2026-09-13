# Remote rewrite model catalog

The macOS app loads `StetMac/Resources/rewrite-models.json` as its bundled offline baseline and checks the same file on GitHub `main` at launch and every 24 hours. Settings can also request a refresh. A newer valid catalog is cached atomically in Application Support; invalid, stale, or unavailable responses preserve the last known good catalog.

## Maintaining the catalog

1. Add, disable, or remove models under an existing provider in `rewrite-models.json`.
2. Ensure every provider's `defaultModelID` references an enabled model.
3. Increment `revision`; never reuse or decrease it.
4. Run `python3 scripts/validate-rewrite-models.py` and open a PR.
5. Merge after CI passes. No tag, DMG, or application release is required for clients that include the catalog loader.

To undo a change, make a new edit and increment the revision again. Clients ignore older or equal revisions.

## Security and fallback behavior

The catalog can only refer to providers already compiled into Stet. It cannot change API hosts, authentication, Keychain accounts, request formats, or provider protocols. Those boundaries remain in Swift so a catalog update cannot redirect credentials or transcript text.

A saved model is preferred while it remains enabled. If it is disabled or removed, Stet uses that provider's current default without overwriting the saved choice and shows the temporary fallback in Settings. Restoring the model restores the user's choice automatically. If a provider has no valid configuration, transcript improvement is skipped and the original transcript is retained.

The first app version containing this loader must still be released. Schema changes and new provider protocols also require a release.
