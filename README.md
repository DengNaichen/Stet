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
