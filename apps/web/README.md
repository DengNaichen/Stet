# Stet Website

Local-preview marketing site for `Stet`, built with `SvelteKit`.

## Purpose

This site is a Swift.org-inspired single-page front end used to explore:

- product positioning
- visual language
- minimal-edit transcription messaging
- section hierarchy before a public launch

It is intentionally local-only for now:

- no live download link
- no waitlist form
- no analytics
- no backend

## Development

```sh
npm install
npm run dev -- --open
```

## Validation

```sh
npm run check
npm run build
```

## Notes

- The site uses `@sveltejs/adapter-static`.
- The main route is a single landing page.
- Content lives in `src/lib/content/site.ts`.
- Shared styles live in `src/app.css`.
