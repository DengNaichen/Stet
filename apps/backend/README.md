# Stet Managed Relay Backend

Managed-mode relay backend for `Stet`, built on Supabase Edge Functions.

## What it does

- validates Supabase access tokens
- lazily provisions per-user managed entitlements
- enforces request and audio quotas
- relays OpenAI-compatible transcription and `/responses` requests
- stores usage metadata only

## What it does not do

- billing
- Stripe
- client integration
- provider switching
- transcript or audio storage

## Local setup

1. Copy environment values:

```sh
cp .env.example .env.local
```

2. Start Supabase:

```sh
npx supabase start --workdir .
```

3. Apply migrations and seed:

```sh
npx supabase db reset --workdir .
```

4. Serve the relay function:

```sh
npx supabase functions serve relay --workdir . --env-file .env.local
```

The local Supabase API will be available at `http://127.0.0.1:54321`.

## Useful routes

- `GET /functions/v1/relay/v1/healthz`
- `GET /functions/v1/relay/v1/me/quota`
- `POST /functions/v1/relay/v1/audio/transcriptions`
- `POST /functions/v1/relay/v1/responses`

## Notes

- Protected routes require a **Supabase access token** in `Authorization: Bearer ...`.
- `/audio/transcriptions` also requires `X-AirType-Audio-Duration-Seconds`.
- The relay forces server-side fixed models:
  - transcription: `gpt-4o-mini-transcribe`
  - responses: `gpt-5-mini`
- `BYOK` is out of scope for this backend and remains a direct path.
