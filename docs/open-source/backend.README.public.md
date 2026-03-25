# Stet Relay Backend

Public relay backend for `Stet`, built on Supabase Edge Functions.

This exported backend is the `open-core` public surface:

- relay API contract
- auth shape
- transcription / rewrite pipeline
- provider abstractions
- unmetered / self-host behavior
- privacy and data-handling documentation

The managed billing implementation, Stripe settlement logic, trial-credit
operations, invite workflow, and abuse thresholds are intentionally omitted from
the public export.

## What it does

- validates Supabase access tokens
- exposes the relay request/response contract used by the client
- transcribes audio via AI SDK providers
- optionally rewrites transcripts
- supports unmetered/self-host setups

## What it does not include

- managed wallet logic
- credit ledger / settlement internals
- trial grant automation
- Stripe purchase or webhook-driven top-ups
- private abuse-control policy

## Billing backend modes

- `unmetered` is the only public export mode

The private source repository may contain additional managed billing
implementations, but they are not part of the public integration surface.

## Privacy posture

- the relay does not store transcript or audio payloads as product data
- request logs should contain metadata only, not transcript content
- managed monetization and anti-abuse internals are intentionally private

## API

### `GET /functions/v1/relay/v1/healthz`

Returns relay status and provider info.

### `GET /functions/v1/relay/v1/me/quota`

Returns current wallet balance and usage summary. In public export mode this is
unmetered/self-host oriented.

### `POST /functions/v1/relay/v1/audio/transcriptions`

Main dictation pipeline endpoint. Requires auth.

Accepted upload formats:

- WAV
- M4A

## Open-core note

This repository is a sanitized public export generated from a private source
repository. If you want the hosted managed product, assume there are private
operational layers that are not represented here.
