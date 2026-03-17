# Stet Managed Relay Backend

Managed-mode relay backend for `Stet`, built on Supabase Edge Functions.

## What it does

- validates Supabase access tokens
- lazily provisions per-user managed entitlements
- enforces request and audio quotas
- transcribes audio via AI SDK (OpenAI / Groq)
- optionally rewrites transcripts (controlled by client)
- stores usage metadata only

## What it does not do

- billing
- Stripe
- client integration
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

## API

### `GET /functions/v1/relay/v1/healthz`

Returns relay status and provider info.

### `GET /functions/v1/relay/v1/me/quota`

Returns current user quota and usage. Requires auth.

### `POST /functions/v1/relay/v1/audio/transcriptions`

The main dictation pipeline endpoint. Requires auth.

**Headers:**

| Header | Required | Description |
|--------|----------|-------------|
| `Authorization` | Yes | `Bearer <supabase-access-token>` |
| `X-Stet-Audio-Duration-Seconds` | Yes | Positive integer, audio duration |

**Form fields (multipart/form-data):**

| Field | Required | Description |
|-------|----------|-------------|
| `file` | Yes | Audio file — WAV (macOS) or M4A (iOS) |
| `language` | No | ISO-639-1 locale code (e.g. `en`) |
| `prompt` | No | Transcription prompt for improved accuracy |
| `rewrite` | No | `"true"` to enable post-transcription cleanup |
| `preferred_spellings` | No | Comma-separated names/terms for rewrite |

**Response:**

```json
{
  "text": "The final transcribed (and optionally rewritten) text.",
  "rewritten": true
}
```

## Audio formats

| Client | Format | Details |
|--------|--------|---------|
| macOS | WAV | 16 kHz, mono, 16-bit PCM |
| iOS | M4A | AAC, 44.1 kHz, mono |

## Notes

- Set `AI_PROVIDER` env var to `openai` (default) or `groq`.
- `BYOK` is out of scope for this backend and remains a direct path.
