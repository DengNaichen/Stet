# macOS CI performance

## Baseline — September 10, 2026

Baseline: [PR #56 run 34456673443](https://github.com/DengNaichen/Stet/actions/runs/34456673443), commit `b5b84c05fdfae7e35e358023c5f058a02adfddab`, macos-26 ARM64, Xcode 26.6 (17F113). Job elapsed times include cache/setup/cleanup when present; phase measurements use timestamped logs.

| Measurement | Baseline |
| --- | ---: |
| Swift Quality (attempt 1) | 18 s |
| macOS Build (attempt 1) | 349 s |
| Build: dependency resolution | 88 s |
| macOS Tests (attempt 2) | 355 s |
| Tests: dependency resolution | 66 s |
| Tests: resolved packages to test start | 232 s |
| Actual Swift Testing execution (521 tests) | 33.443 s |
| Metal component installation | 4–5 s |

Attempt 1 tests failed after 398 s on timing-sensitive tests. An unchanged rerun passed. Successful build/quality jobs were retained, not rerun; do not interpret the rerun's workflow duration as a fresh full pipeline measurement.

## Experiment

Keep the same checks, test suite, coverage, runner and Xcode selection. Separate dependency resolution so GitHub records its elapsed time. Cache SwiftPM sources and binary artifacts using manifests, lockfiles and exact toolchain/OS identity. Save packages before compilation so a test failure does not discard the download work.

Enable Xcode's input-addressed Swift/Clang compilation cache, isolated by toolchain and build/test mode, with a per-commit key and compatible fallback. Cache compiler results even on test failure. Build products, test results, signing material and app data are not cached. Local Makefile behavior is unchanged unless `CI_XCODEBUILD_FLAGS` is supplied.

The package cache stays in DerivedData/SourcePackages because `normalize-binary-frameworks.sh` locates the Sherpa framework there. Do not independently move that directory without updating its consumer.

Validation: run the modified workflow cold, then rerun the same commit warm. Compare job elapsed times including cache transfer overhead, dependency resolution, compilation cache hits, and the number/result of executed tests. Follow with a changed-source run to check invalidation. No estimated speedup is a measured result.

References: [Apple Xcode 26 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26-release-notes), [GitHub cache action](https://github.com/actions/cache), [GitHub cache scope](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).
