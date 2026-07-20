# Stet Internal Monorepo

This private repository is the canonical development repository for Stet.

## Layout

- `Public/Stet/` is the complete public macOS repository. It is exported to
  `DengNaichen/Stet` with `git subtree split`.
- `Private/StetMobile/` is the private iOS application and its imported history.
- Root-level files are internal monorepo governance and CI only.

The private repository remote is named `origin`. The public projection remote is
named `public`. Normal development branches and pushes go to `origin`; never push
the monorepo branch itself to `public`.

After cloning the private repository, configure the public projection remote once:

```bash
git remote add public https://github.com/DengNaichen/Stet.git
```

## Common commands

```bash
make build          # public macOS app
make test           # public macOS tests
make ios-build      # private iOS simulator build (bootstraps ignored runtime)
make lint           # public and private Swift sources
make verify-public  # public-boundary and GitHub-size checks
make public-export  # print the public projection commit; does not push
```

To publish the public projection after review:

```bash
./scripts/publish-public.sh --push
```

The publish script only pushes the history derived from `Public/Stet/`. Files
under `Private/`, local model payloads, and ignored runtime frameworks are not
part of that commit.

## Runtime policy

Model payloads, downloaded iOS runtime frameworks, Xcode build products, and the
retired root-level `StetMobile/` checkout are local-only. They are not mirrored
or backed up into GitHub by this repository.
