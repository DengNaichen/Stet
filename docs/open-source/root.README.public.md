# Public Export Notes

This repository is intended to be published as a sanitized public export.

It intentionally excludes:

- managed billing internals
- wallet / ledger settlement logic
- Stripe top-up implementation details
- trial-credit issuance
- private abuse controls and thresholds

Recommended workflow:

1. Keep the main development repository private.
2. Run `./scripts/export-open-source.sh /path/to/public-export`.
3. Publish the generated directory to the public GitHub repository.

Do not make the private source repository public directly.
