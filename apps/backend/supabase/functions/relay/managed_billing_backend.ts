import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "./error.ts";
import { log } from "./log.ts";
import { getRelayPolicy } from "./config.ts";
import type {
  RelayAccount,
  RelayBillingBackend,
  TopupWebhookResult,
  UsageSettlement,
  WalletSummary,
} from "./billing_backend.ts";
import { quoteActualCredits, quoteReservedCredits } from "./billing.ts";
import {
  applyCreditTopup as applyCreditTopupRpc,
  beginUsage as beginUsageRpc,
  countTranscriptionChars,
  finalizeUsage as finalizeUsageRpc,
  getWalletSummary as getWalletSummaryRpc,
  refundUsage as refundUsageRpc,
} from "./usage.ts";
import type { TextUsage } from "./providers/provider.ts";

export class ManagedRelayBillingBackend implements RelayBillingBackend {
  readonly kind = "managed";

  async resolveAccount(
    admin: SupabaseClient,
    userId: string,
  ): Promise<RelayAccount> {
    const { data, error } = await admin
      .from("billing_accounts")
      .upsert({ user_id: userId }, { onConflict: "user_id" })
      .select("*")
      .single();

    if (error || !data) {
      throw new ApiError(
        500,
        "billing_account_error",
        "The relay could not resolve billing account details.",
      );
    }

    let relayAccount = {
      ...(data as Omit<RelayAccount, "billing_backend">),
      billing_backend: this.kind,
    };

    if (relayAccount.managed_enabled) {
      relayAccount = await this.ensureBetaTrialCredits(admin, relayAccount);
    }

    return relayAccount;
  }

  getWalletSummary(
    admin: SupabaseClient,
    userId: string,
  ): Promise<WalletSummary> {
    return getWalletSummaryRpc(admin, userId);
  }

  async beginTranscriptionUsage(args: {
    admin: SupabaseClient;
    userId: string;
    requestId: string;
    provider: "openai" | "groq";
    modelId: string;
    audioDurationSeconds: number;
    requestMetadata?: Record<string, unknown>;
  }) {
    const reservation = quoteReservedCredits({
      provider: args.provider,
      usageKind: "asr",
      quantity: args.audioDurationSeconds,
    });

    return beginUsageRpc(args.admin, {
      userId: args.userId,
      requestId: args.requestId,
      usageKind: "asr",
      provider: args.provider,
      quantity: args.audioDurationSeconds,
      reservedCredits: reservation.reservedCredits,
      modelId: args.modelId,
      requestMetadata: args.requestMetadata,
    });
  }

  async finalizeTranscriptionUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    provider: "openai" | "groq";
    audioDurationSeconds: number;
    transcriptionText: string;
    upstreamStatus: number;
  }): Promise<UsageSettlement> {
    const billedCredits = quoteActualCredits({
      provider: args.provider,
      usageKind: "asr",
      quantity: args.audioDurationSeconds,
    });
    const transcriptionChars = countTranscriptionChars(args.transcriptionText);

    await finalizeUsageRpc(args.admin, {
      usageEventId: args.usageEventId,
      actualQuantity: args.audioDurationSeconds,
      billedCredits,
      transcriptionChars,
      inputTokens: 0,
      outputTokens: 0,
      upstreamStatus: args.upstreamStatus,
    });

    return {
      billedCredits,
      transcriptionChars,
    };
  }

  async beginRewriteUsage(args: {
    admin: SupabaseClient;
    userId: string;
    requestId: string;
    provider: "openai" | "groq";
    modelId: string;
    inputText: string;
  }) {
    const reservation = quoteReservedCredits({
      provider: args.provider,
      usageKind: "rewrite",
      quantity: countTranscriptionChars(args.inputText),
      text: args.inputText,
    });

    return beginUsageRpc(args.admin, {
      userId: args.userId,
      requestId: args.requestId,
      usageKind: "rewrite",
      provider: args.provider,
      quantity: (reservation.estimatedInputTokens ?? 0) +
          (reservation.estimatedOutputTokens ?? 0) ||
        countTranscriptionChars(args.inputText),
      reservedCredits: reservation.reservedCredits,
      modelId: args.modelId,
    });
  }

  async finalizeRewriteUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    provider: "openai" | "groq";
    inputText: string;
    outputText: string;
    usage: TextUsage;
    upstreamStatus: number;
  }): Promise<UsageSettlement> {
    const inputChars = countTranscriptionChars(args.inputText);
    const billedCredits = args.provider === "groq"
      ? quoteActualCredits({
        provider: args.provider,
        usageKind: "rewrite",
        quantity: inputChars,
        text: args.outputText,
        usage: args.usage,
      })
      : quoteActualCredits({
        provider: args.provider,
        usageKind: "rewrite",
        quantity: inputChars,
        text: args.inputText,
      });
    const transcriptionChars = countTranscriptionChars(args.outputText);

    await finalizeUsageRpc(args.admin, {
      usageEventId: args.usageEventId,
      actualQuantity: inputChars,
      billedCredits,
      transcriptionChars,
      inputTokens: args.usage.inputTokens,
      outputTokens: args.usage.outputTokens,
      upstreamStatus: args.upstreamStatus,
    });

    return {
      billedCredits,
      transcriptionChars,
    };
  }

  refundUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    upstreamStatus?: number | null;
  }): Promise<void> {
    return refundUsageRpc(args.admin, {
      usageEventId: args.usageEventId,
      upstreamStatus: args.upstreamStatus,
    });
  }

  async handleStripeWebhook(args: {
    admin: SupabaseClient;
    requestId: string;
    rawBody: string;
    signatureHeader: string;
  }): Promise<TopupWebhookResult> {
    if (
      !(await verifyStripeWebhookSignature(args.rawBody, args.signatureHeader))
    ) {
      throw new ApiError(
        401,
        "invalid_stripe_signature",
        "The Stripe webhook signature is invalid.",
      );
    }

    let event: StripeWebhookEvent;
    try {
      event = JSON.parse(args.rawBody) as StripeWebhookEvent;
    } catch (error) {
      log("error", "stripe_webhook_invalid_json", args.requestId, {
        message: error instanceof Error ? error.message : String(error),
      });
      throw new ApiError(
        400,
        "invalid_stripe_event",
        "The Stripe webhook body could not be parsed.",
      );
    }

    if (!isSupportedStripeEvent(event.type)) {
      return { received: true };
    }

    const payload = extractStripeTopupPayload(event);
    if (!payload) {
      throw new ApiError(
        400,
        "missing_topup_metadata",
        "The Stripe event did not include top-up metadata.",
      );
    }

    const topup = await applyCreditTopupRpc(args.admin, {
      userId: payload.userId,
      credits: payload.credits,
      externalReference: event.id,
      provider: "stripe",
      metadata: {
        stripe_event_type: event.type,
        stripe_customer_id: payload.customerId ?? null,
        stripe_checkout_session_id: payload.checkoutSessionId ?? null,
      },
    });

    log("info", "stripe_topup_applied", args.requestId, {
      stripeEventId: event.id,
      userId: payload.userId,
      credits: payload.credits,
      balanceCredits: topup.balance_credits,
    });

    return {
      received: true,
      balance_credits: topup.balance_credits,
    };
  }

  private async ensureBetaTrialCredits(
    admin: SupabaseClient,
    relayAccount: RelayAccount,
  ): Promise<RelayAccount> {
    const policy = getRelayPolicy();
    const trialReference = betaTrialReference(relayAccount.user_id);

    await applyCreditTopupRpc(admin, {
      userId: relayAccount.user_id,
      credits: policy.betaTrialCredits,
      externalReference: trialReference,
      provider: "manual",
      metadata: {
        grant_kind: "beta_trial",
        grant_version: 1,
        managed_enabled: relayAccount.managed_enabled,
      },
    });

    const { data, error } = await admin
      .from("billing_accounts")
      .select("*")
      .eq("user_id", relayAccount.user_id)
      .single();

    if (error || !data) {
      throw new ApiError(
        500,
        "billing_account_error",
        "The relay could not refresh billing account details.",
      );
    }

    return {
      ...(data as Omit<RelayAccount, "billing_backend">),
      billing_backend: this.kind,
    };
  }
}

function betaTrialReference(userId: string): string {
  return `beta_trial_v1:${userId}`;
}

type StripeWebhookEvent = {
  id: string;
  type: string;
  data: {
    object: Record<string, unknown>;
  };
};

type StripeTopupPayload = {
  userId: string;
  credits: number;
  customerId: string | null;
  checkoutSessionId: string | null;
};

function isSupportedStripeEvent(type: string): boolean {
  return type === "checkout.session.completed" ||
    type === "payment_intent.succeeded";
}

function extractStripeTopupPayload(
  event: StripeWebhookEvent,
): StripeTopupPayload | null {
  const object = event.data?.object ?? {};
  const metadata = parseStripeMetadata(object["metadata"]);
  const userId = firstNonEmptyString(
    metadata.user_id,
    metadata.userId,
    typeof object["client_reference_id"] === "string"
      ? object["client_reference_id"]
      : null,
  );
  const credits = parsePositiveInteger(firstNonEmptyString(
    metadata.credits,
    metadata.credit_amount,
    metadata.topup_credits,
  ));

  if (!userId || credits === null) {
    return null;
  }

  return {
    userId,
    credits,
    customerId: firstNonEmptyString(
      typeof object["customer"] === "string" ? object["customer"] : null,
      typeof object["customer_id"] === "string" ? object["customer_id"] : null,
    ),
    checkoutSessionId: firstNonEmptyString(
      typeof object["id"] === "string" ? object["id"] : null,
      null,
    ),
  };
}

function parseStripeMetadata(value: unknown): Record<string, string> {
  if (!value || typeof value !== "object") {
    return {};
  }

  const metadata: Record<string, string> = {};
  for (const [key, raw] of Object.entries(value as Record<string, unknown>)) {
    if (typeof raw === "string" && raw.trim()) {
      metadata[key] = raw.trim();
    }
  }
  return metadata;
}

function parsePositiveInteger(value: string | null): number | null {
  if (!value) return null;

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    return null;
  }

  return parsed;
}

function firstNonEmptyString(
  ...values: Array<string | null | undefined>
): string | null {
  for (const value of values) {
    if (typeof value === "string") {
      const trimmed = value.trim();
      if (trimmed) {
        return trimmed;
      }
    }
  }

  return null;
}

async function verifyStripeWebhookSignature(
  rawBody: string,
  signatureHeader: string,
): Promise<boolean> {
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET")?.trim();
  if (!secret) {
    throw new ApiError(
      500,
      "stripe_webhook_misconfigured",
      "The Stripe webhook secret is not configured.",
    );
  }

  const parsed = parseStripeSignatureHeader(signatureHeader);
  if (!parsed) {
    return false;
  }

  const toleranceSeconds = 300;
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - parsed.timestamp) > toleranceSeconds) {
    return false;
  }

  const payload = `${parsed.timestamp}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payload),
  );
  const expected = bytesToHex(new Uint8Array(signature));

  return parsed.signatures.some((candidate) =>
    timingSafeEqualHex(candidate, expected)
  );
}

function parseStripeSignatureHeader(
  value: string,
): { timestamp: number; signatures: string[] } | null {
  const parts = value.split(",").map((part) => part.trim()).filter(Boolean);
  let timestamp: number | null = null;
  const signatures: string[] = [];

  for (const part of parts) {
    const [key, raw] = part.split("=", 2);
    if (!key || !raw) {
      continue;
    }

    if (key === "t") {
      const parsed = Number(raw);
      if (Number.isInteger(parsed)) {
        timestamp = parsed;
      }
    } else if (key === "v1") {
      signatures.push(raw.trim().toLowerCase());
    }
  }

  if (timestamp === null || signatures.length === 0) {
    return null;
  }

  return { timestamp, signatures };
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let mismatch = 0;
  for (let index = 0; index < a.length; index += 1) {
    mismatch |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }

  return mismatch === 0;
}
