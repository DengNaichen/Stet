# Stet Managed Relay Backend

Managed-mode relay backend for `Stet`, built on Supabase Edge Functions.

The relay core now talks to a swappable billing backend via
`RelayBillingBackend`. That separation lets you keep the protocol and AI
pipeline open source while moving the managed billing implementation to a
private repo later.

For the beta rollout, the public trust surface is the relay contract, auth
shape, provider abstraction, and privacy posture. Managed billing internals,
trial-grant operations, and abuse-control policy are implementation details and
should not be treated as stable public API.

## What it does

- validates Supabase access tokens
- lazily provisions per-user billing accounts
- enforces invite-only managed access, request-rate limits, and pay-as-you-go
  credit checks
- transcribes audio via AI SDK (OpenAI / Groq)
- optionally rewrites transcripts (controlled by client)
- stores usage and credit ledger metadata only

## What it does not do

- subscription billing
- automated recharge
- client integration
- transcript or audio storage
- user-facing purchases in beta

## Billing backend modes

- `managed` (default): current wallet + credit ledger + Stripe top-up behavior
- `unmetered`: open-core/self-host mode with no wallet enforcement and no Stripe
  top-ups

Set `RELAY_BILLING_BACKEND=managed` or `RELAY_BILLING_BACKEND=unmetered`.

### Open-core split boundary

The public repo should keep:

- relay API routes and request/response contract
- auth gating and provider abstractions
- transcription and rewrite pipeline shape
- unmetered/self-host backend
- privacy and data-handling documentation

The managed/private boundary should move out:

- `supabase/functions/relay/managed_billing_backend.ts`
- `supabase/functions/relay/billing.ts`
- `supabase/functions/relay/usage.ts`
- `supabase/migrations/20260318120000_payg_wallet_v1.sql`
- `supabase/migrations/20260318123000_precision_model_billing_v1.sql`
- trial-grant issuance and invite cohort operations
- abuse thresholds and future monetization policy

This repository still contains managed-mode code for development, but those
pieces are not intended to be a stable public integration surface.

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

Returns current wallet balance and usage summary. Requires auth.

### `POST /functions/v1/relay/v1/billing/stripe/webhook`

Stripe webhook boundary for prepaid credit top-ups. It is disabled by default in
beta and requires `RELAY_ENABLE_STRIPE_WEBHOOK=true`. When enabled, it expects a
valid `Stripe-Signature` header and event metadata containing `user_id` and
`credits`.

### `POST /functions/v1/relay/v1/audio/transcriptions`

The main dictation pipeline endpoint. Requires auth.

**Headers:**

| Header          | Required | Description                      |
| --------------- | -------- | -------------------------------- |
| `Authorization` | Yes      | `Bearer <supabase-access-token>` |

**Form fields (multipart/form-data):**

| Field                    | Required | Description                                                                                                             |
| ------------------------ | -------- | ----------------------------------------------------------------------------------------------------------------------- |
| `file`                   | Yes      | Audio file — WAV (macOS) or M4A (iOS)                                                                                   |
| `audio_duration_seconds` | Yes      | Duration of the audio clip in seconds. Requests are rejected if the duration is implausible for the uploaded file size. |
| `language`               | No       | ISO-639-1 locale code (e.g. `en`)                                                                                       |
| `prompt`                 | No       | Transcription prompt for improved accuracy                                                                              |
| `rewrite`                | No       | `"true"` to enable post-transcription cleanup                                                                           |
| `preferred_spellings`    | No       | Comma-separated names/terms for rewrite                                                                                 |

**Response:**

```json
{
  "text": "The final transcribed (and optionally rewritten) text.",
  "rewritten": true
}
```

## Audio formats

| Client | Format | Details                  |
| ------ | ------ | ------------------------ |
| macOS  | WAV    | 16 kHz, mono, 16-bit PCM |
| iOS    | M4A    | AAC, 44.1 kHz, mono      |

## Notes

- Set `AI_PROVIDER` env var to `groq` (default) or `openai`.
- ASR is billed by audio duration and rewrite is billed by model token usage.
- Groq managed-mode defaults to `openai/gpt-oss-120b` for rewrite and
  `whisper-large-v3-turbo` for transcription.
- The relay requires `audio_duration_seconds` for managed mode requests.
- Managed mode is invite-only by default. New billing accounts start with
  `managed_enabled=false`.
- Approved beta users receive a one-time trial grant of `3000` credits on first
  successful managed authentication.
- The relay logs request metadata only. Transcript and rewrite content are
  intentionally excluded from logs.
- The relay enforces upload-size, duration, concurrency, request-rate, and
  daily-credit sanity checks before upstream usage.
- Credits are prepaid and deducted from the user's wallet before upstream calls.
  Failed upstream calls are refunded, and successful rewrite calls reconcile any
  difference between the pre-reserved and actual token-based cost.
- Stripe top-ups are intentionally skeleton-only for beta. Do not expose a live
  purchase flow until you are ready to move the managed billing internals behind
  a private boundary.
- `BYOK` is out of scope for this backend and remains a direct path.
