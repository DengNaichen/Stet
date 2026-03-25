import { getRelayPolicy } from "./config.ts";

Deno.test("getRelayPolicy uses beta-safe defaults", () => {
  const original = Deno.env.toObject();
  for (const key of Object.keys(original)) {
    if (key.startsWith("RELAY_")) {
      Deno.env.delete(key);
    }
  }

  const policy = getRelayPolicy();

  if (policy.stripeWebhookEnabled !== false) {
    throw new Error("expected Stripe webhook to be disabled by default");
  }

  if (policy.betaTrialCredits !== 3000) {
    throw new Error(
      `expected beta trial credits 3000, received ${policy.betaTrialCredits}`,
    );
  }

  if (policy.dailyCreditLimit !== 1500) {
    throw new Error(
      `expected daily credit limit 1500, received ${policy.dailyCreditLimit}`,
    );
  }

  restoreRelayEnv(original);
});

Deno.test("getRelayPolicy honors env overrides", () => {
  const original = Deno.env.toObject();
  Deno.env.set("RELAY_ENABLE_STRIPE_WEBHOOK", "true");
  Deno.env.set("RELAY_BETA_TRIAL_CREDITS", "4500");
  Deno.env.set("RELAY_MAX_REQUESTS_PER_MINUTE", "9");

  const policy = getRelayPolicy();

  if (policy.stripeWebhookEnabled !== true) {
    throw new Error("expected Stripe webhook override to enable route");
  }

  if (policy.betaTrialCredits !== 4500) {
    throw new Error(
      `expected beta trial credits 4500, received ${policy.betaTrialCredits}`,
    );
  }

  if (policy.maxRequestsPerMinute !== 9) {
    throw new Error(
      `expected maxRequestsPerMinute 9, received ${policy.maxRequestsPerMinute}`,
    );
  }

  restoreRelayEnv(original);
});

function restoreRelayEnv(snapshot: Record<string, string>) {
  for (const [key, value] of Object.entries(snapshot)) {
    if (key.startsWith("RELAY_")) {
      Deno.env.set(key, value);
    }
  }

  for (const key of Object.keys(Deno.env.toObject())) {
    if (key.startsWith("RELAY_") && !(key in snapshot)) {
      Deno.env.delete(key);
    }
  }
}
