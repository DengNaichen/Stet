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

The first clipboard-test adjustment captured and awaited the cancelled task and passed two runs, but failed again in the final cold run. Increasing the timeout did not establish reliable readiness; those two passes were insufficient evidence of stability.

Native caching leaves substantial build preparation and Swift test macro work even with zero compiler misses. The next experiment caches incremental products with content-checked source timestamps. Changed files retain fresh mtimes; removed/untracked paths and symlinks cannot be restored by cached metadata. The helper is covered by fixture tests, including same-length edits and nanosecond precision. Each CI job still invokes its original build/test command; test results are never used to skip execution.

| Incremental experiment | Build job | Test job | Result |
| --- | ---: | ---: | --- |
| Seed products from native caches, [34461659602 attempt 1](https://github.com/DengNaichen/Stet/actions/runs/34461659602/attempts/1) | 163 s | 184 s | 521 tests passed |
| Same revision with incremental cache, attempt 2 | 109 s | 168 s | 521 tests passed; build has no SwiftCompile/SwiftDriver tasks |

Incremental archives are approximately 476 MiB (build) / 501 MiB (tests), taking 12–14 seconds to restore in this sample. Total job times include that cost. Directory fingerprints cover nested resource contents, with fixture coverage for same-name edits and malformed cache metadata.

The changed-source run [34462415559](https://github.com/DengNaichen/Stet/actions/runs/34462415559) passed all checks: build 126 s, tests 298 s, including cache uploads. The test-source edit was recompiled and all 521 tests ran. This is slower than a no-change rerun; do not advertise warm rerun timing as the cost of every code change.

The v2 namespace intentionally started empty in [34463067580](https://github.com/DengNaichen/Stet/actions/runs/34463067580): build passed in 254 s; tests took 504 s and failed on clipboard restoration and pending-result readiness. Package resolution alone took 78 s in the test job. This failed run is not a successful performance result. It retained package/native caches but deliberately did not save incremental test products.

## Flaky-test investigation

Historical runs failed intermittently on `restoreHandlesEmptyClipboardGracefully`, `hotkeyPreservesNewerClipboardAndCancelsOldTimeout`, and `listeningToProcessingTransitionDefersResumeUntilConfiguredDelayElapses`. Tests assumed that a short real sleep or a brief polling window established asynchronous completion. A busy runner can start or resume the production task later than the test expects.

The fix injects controllable sleep functions into clipboard restore, pending-result dismissal and media resume, keeping their existing real-time defaults in the app. Tests await sleep registration, advance a virtual clock and await the actual task. Cancellation assertions also await completion. All related pending-result timeout tests use the same approach. The hotkey action test starts from an already-copied pending result; separate tests retain coverage of the failed-paste fallback pipeline. Its fixture uses a private pasteboard.

The clock has regression tests for deadline ordering and cancellation before/after registration. A standalone harness passed 1,000 repetitions of each of these three cases. Final repeated app-suite and hosted CI results are pending.
