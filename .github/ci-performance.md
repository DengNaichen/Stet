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

Enable Xcode's input-addressed Swift/Clang compilation cache, isolated by toolchain and build/test mode, with a per-commit key and compatible fallback. Cache compiler results even on test failure. The first experiment cached only compiler results. The incremental follow-up also caches unsigned Build products and ModuleCache, validating tracked input SHA-256 hashes before restoring nanosecond mtimes. Test result logs, signing material and app data are not cached. Local Makefile behavior is unchanged unless `CI_XCODEBUILD_FLAGS` is supplied.

The package cache stays in DerivedData/SourcePackages because `normalize-binary-frameworks.sh` locates the Sherpa framework there. Do not independently move that directory without updating its consumer.

Validation: run the modified workflow cold, then rerun the same commit warm. Compare job elapsed times including cache transfer overhead, dependency resolution, compilation cache hits, and the number/result of executed tests. Follow with a changed-source run to check invalidation. No estimated speedup is a measured result.

References: [Apple Xcode 26 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26-release-notes), [GitHub cache action](https://github.com/actions/cache), [GitHub cache scope](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching).

## Intermediate measurements

| Experiment | Build job | Test job | Result |
| --- | ---: | ---: | --- |
| Native cache cold, [34458876587 attempt 1](https://github.com/DengNaichen/Stet/actions/runs/34458876587/attempts/1) | 280 s | 524 s | 521 tests passed |
| Native cache warm, same commit, attempt 2 | 176 s | 244 s | Existing clipboard timing test failed |
| Skip redundant resolution, changed test source, [34460313988 attempt 1](https://github.com/DengNaichen/Stet/actions/runs/34460313988/attempts/1) | 154 s | 265 s | 521 tests passed; tests: 996 cache-hit and 15 cache-miss diagnostics |
| Native + manifests fully warm, same commit, attempt 2 | 137 s | 246 s | 521 tests passed |

The clipboard test raced a 100 ms timeout against polling on a loaded runner. It now checks cancellation on the captured task and awaits completion, without changing production behavior. The revised source passed both full-suite runs.

Native caching leaves substantial build preparation and Swift test macro work even with zero compiler misses. The next experiment caches incremental products with content-checked source timestamps. Changed files retain fresh mtimes; removed/untracked paths and symlinks cannot be restored by cached metadata. The helper is covered by fixture tests, including same-length edits and nanosecond precision. Each CI job still invokes its original build/test command; test results are never used to skip execution.

| Incremental experiment | Build job | Test job | Result |
| --- | ---: | ---: | --- |
| Seed products from native caches, [34461659602 attempt 1](https://github.com/DengNaichen/Stet/actions/runs/34461659602/attempts/1) | 163 s | 184 s | 521 tests passed |
| Same revision with incremental cache, attempt 2 | 109 s | 168 s | 521 tests passed; build has no SwiftCompile/SwiftDriver tasks |

Incremental archives are approximately 476 MiB (build) / 501 MiB (tests), taking 12–14 seconds to restore in this sample. Total job times include that cost. Directory fingerprints are being strengthened to cover nested resource contents, with a real Swift test-source edit used for the final invalidation run.
