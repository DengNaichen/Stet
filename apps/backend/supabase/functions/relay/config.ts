export type RelayPolicy = {
  stripeWebhookEnabled: boolean;
  betaTrialCredits: number;
  maxAudioBytes: number;
  maxAudioDurationSeconds: number;
  minBytesPerSecond: number;
  maxBytesPerSecond: number;
  maxRequestsPerMinute: number;
  maxConcurrentRequests: number;
  dailyCreditLimit: number;
};

const DEFAULT_POLICY: RelayPolicy = {
  stripeWebhookEnabled: false,
  betaTrialCredits: 3_000,
  maxAudioBytes: 32 * 1024 * 1024,
  maxAudioDurationSeconds: 15 * 60,
  minBytesPerSecond: 256,
  maxBytesPerSecond: 128 * 1024,
  maxRequestsPerMinute: 6,
  maxConcurrentRequests: 2,
  dailyCreditLimit: 1_500,
};

export function getRelayPolicy(): RelayPolicy {
  return {
    stripeWebhookEnabled: readBooleanEnv(
      "RELAY_ENABLE_STRIPE_WEBHOOK",
      DEFAULT_POLICY.stripeWebhookEnabled,
    ),
    betaTrialCredits: readPositiveIntegerEnv(
      "RELAY_BETA_TRIAL_CREDITS",
      DEFAULT_POLICY.betaTrialCredits,
    ),
    maxAudioBytes: readPositiveIntegerEnv(
      "RELAY_MAX_AUDIO_BYTES",
      DEFAULT_POLICY.maxAudioBytes,
    ),
    maxAudioDurationSeconds: readPositiveIntegerEnv(
      "RELAY_MAX_AUDIO_DURATION_SECONDS",
      DEFAULT_POLICY.maxAudioDurationSeconds,
    ),
    minBytesPerSecond: readPositiveIntegerEnv(
      "RELAY_MIN_BYTES_PER_SECOND",
      DEFAULT_POLICY.minBytesPerSecond,
    ),
    maxBytesPerSecond: readPositiveIntegerEnv(
      "RELAY_MAX_BYTES_PER_SECOND",
      DEFAULT_POLICY.maxBytesPerSecond,
    ),
    maxRequestsPerMinute: readPositiveIntegerEnv(
      "RELAY_MAX_REQUESTS_PER_MINUTE",
      DEFAULT_POLICY.maxRequestsPerMinute,
    ),
    maxConcurrentRequests: readPositiveIntegerEnv(
      "RELAY_MAX_CONCURRENT_REQUESTS",
      DEFAULT_POLICY.maxConcurrentRequests,
    ),
    dailyCreditLimit: readPositiveIntegerEnv(
      "RELAY_DAILY_CREDIT_LIMIT",
      DEFAULT_POLICY.dailyCreditLimit,
    ),
  };
}

function readPositiveIntegerEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name)?.trim();
  if (!raw) return fallback;

  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return fallback;
  }

  return parsed;
}

function readBooleanEnv(name: string, fallback: boolean): boolean {
  const raw = Deno.env.get(name)?.trim().toLowerCase();
  if (!raw) return fallback;
  if (["1", "true", "yes", "on"].includes(raw)) return true;
  if (["0", "false", "no", "off"].includes(raw)) return false;
  return fallback;
}
