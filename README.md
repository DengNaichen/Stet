# Stet

Stet is a small monorepo that keeps the macOS app, website, and managed relay backend in one place.

## Layout

- `apps/mac`: macOS SwiftUI app and tests
- `apps/web`: SvelteKit marketing site
- `apps/backend`: Supabase relay backend
- `scripts`: shared repo scripts

## Root Commands

From the repo root:

```bash
npm run mac:build
npm run mac:release
npm run web:install
npm run web:dev
npm run web:check
npm run web:build
npm run backend:start
npm run backend:db:reset
npm run backend:serve
```

## Direct Commands

Build the macOS app directly:

```bash
xcodebuild -project apps/mac/Stet.xcodeproj -scheme Stet -configuration Debug -destination 'platform=macOS' build
```

Build the release app bundle into `dist/`:

```bash
./scripts/build-macos-release.sh
```

Build a notarized GitHub distribution zip and optional Sparkle appcast:

```bash
cp .env.release.example .env.release
npm run mac:notary:setup
npm run mac:release:github
npm run mac:publish:github
```

The GitHub release pipeline expects:

- A local `Developer ID Application` certificate installed in Xcode/Keychain
- A `notarytool` Keychain profile, referenced by `NOTARY_PROFILE`
- `GITHUB_REPOSITORY` and `GITHUB_TAG` in `.env.release`
- Optional Sparkle signing input via `SPARKLE_PRIVATE_KEY_PATH` or `SPARKLE_KEYCHAIN_ACCOUNT`

Artifacts are written to `dist/github-release/<tag>/`.

The publish step uses GitHub CLI to create or update the release for `GITHUB_TAG`
and uploads the notarized zip plus `appcast.xml` when it exists.

Run the site locally:

```bash
cd apps/web
npm install
npm run dev
```

Run the Supabase relay locally:

```bash
cd apps/backend
cp .env.example .env.local
npx supabase start --workdir .
npx supabase functions serve relay --workdir . --env-file .env.local
```
