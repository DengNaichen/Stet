# Worktree preparation and build caches

Run `make setup-worktree` (or `scripts/setup-worktree --if-needed`) from a checkout.
The setup reports the selected Xcode/Swift toolchain, prepares the architecture
checker, and reports whether the ignored local FunASR runtime is present. It does
not build the app or silently install Homebrew tools. Missing runtime assets still
require `Packages/StetEngine/Vendor/FunASRPackage/build-xcframework.sh` before an
app build; setup's successful exit means architecture tooling is ready, not that
all app build prerequisites have been installed.

## Architecture tool

`arch-check.py` asks `scripts/worktree-cache.py deps-graph` for a validated binary
on every invocation. It no longer trusts an existing checkout-local `.build`
binary after tool sources change. The default cache is
`${XDG_CACHE_HOME:-$HOME/.cache}/stet/worktrees/v1`; `STET_WORKTREE_CACHE_DIR` can
select an isolated cache for experiments.

Each key includes the tool's manifest, resolved dependencies, source bytes and
filenames, builder implementation, selected Swift/Xcode/SDK identity, host
architecture, and build-affecting environment. The key excludes the checkout
path. Uncommitted tool edits invalidate it just like committed edits.

One process builds each key under a file lock. Other processes report that they
are waiting and then validate the completed artifact. Compilation uses a private
source snapshot and SwiftPM scratch directory; only the standalone executable
and its hash manifest are published, by atomic rename. Failed builds never
publish a ready artifact; detected corruption rebuilds that key. A source edit
while waiting or compiling triggers a fresh input check. If the cache builder
script itself changes while a process is running, preparation aborts and asks
for a restart, so old loaded code cannot publish under a new implementation key.
Cached output is not a
substitute for running the architecture rules on the current checkout.

Do not delete the shared cache while preparations or architecture checks are
running. Worktree removal does not remove this cache. Old checkout-local
`tools/deps-graph/.build` directories are not automatically deleted.

## Xcode

`make build`, `make ci-build`, and `make test` enable Xcode's native compilation
cache and print a build timing summary. `MACOS_COMPILATION_CACHE=NO` disables the
setting for comparison. `CI_XCODEBUILD_FLAGS` remains available on all three
commands for explicit build settings and paths.

Keep DerivedData and mutable SourcePackages artifacts separate between concurrent
worktrees. In particular, `normalize-binary-frameworks.sh` modifies and signs the
Sherpa framework artifact. Sharing that writable tree can make one build change
another build's input.

With default Xcode locations, per-project build products are separate while the
native compilation cache lives at the DerivedData parent's
`CompilationCache.noindex`. With an explicit `-derivedDataPath`, Xcode defaults
the compilation cache under that directory; an experiment can pass
`COMPILATION_CACHE_CAS_PATH` to share only a dedicated native cache. CI retains its
existing `.build/ci/CompilationCache.noindex` cache configuration.

Sharing download data or enabling the cache does not guarantee compilation hits
across source paths. Use cache diagnostics and real elapsed times to assess a
new setup, and continue to execute tests even when compilation is cached.

## Cache cleanup

`scripts/xcode-storage.sh clean-project <checkout>` only removes that checkout's
allowlisted caches and matching DerivedData. The process guard checks command
lines plus build tools' working directories and open files against those paths.
Zed/SourceKit or a build in another checkout does not block cleanup. A process
using the target checkout or caches still blocks it, and unavailable process
inspection preserves resources. The script never stops editor/build processes.

## Agent adapters

- Cursor's existing worktree setup calls the same script.
- Codex's Darwin local-environment setup prepares new worktrees. CLI sessions do
  not imply that the desktop local-environment hook ran.
- Claude and Codex `SessionStart` (`startup|resume`) run idempotent preparation
  from the current Git checkout, rather than a possibly stale primary-project
  environment variable. Hook trust/support is controlled by each host.
- Stop hooks keep their existing architecture-check behavior. Cold compilation
  should normally happen during setup, before the Stop hook's shorter timeout.

The adapter tests exercise configured commands and target-directory selection;
they do not claim an end-to-end GUI lifecycle test.

## Validation

```sh
python3 -m unittest discover -s scripts/tests -p 'test_worktree_*.py' -v
```

These tests cover cache input changes, corruption, failed publication, concurrent
builders, edits during lock waits/builds, Swift driver symlink dispatch, setup
failures and host command routing. Pre-commit filename selection uses Python and
Git's NUL-delimited output; a missing `rg` no longer silently disables the checks.

[Real multi-worktree measurements](research/worktree-cache-validation-2026-11-07.md) record the tested cache and isolation behavior;
unit test timing is not a replacement for fresh Swift/Xcode builds.
