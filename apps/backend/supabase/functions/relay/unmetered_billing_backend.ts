import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "./error.ts";
import type {
  RelayAccount,
  RelayBillingBackend,
  TopupWebhookResult,
  UsageSettlement,
  WalletSummary,
} from "./billing_backend.ts";
import type { TextUsage } from "./providers/provider.ts";

const EMPTY_WALLET_SUMMARY: WalletSummary = {
  balance_credits: 0,
  recent_usage_credits_7d: 0,
  recent_topup_credits_7d: 0,
  total_usage_credits: 0,
  total_topup_credits: 0,
};

export class UnmeteredRelayBillingBackend implements RelayBillingBackend {
  readonly kind = "unmetered";

  async resolveAccount(
    _: SupabaseClient,
    userId: string,
  ): Promise<RelayAccount> {
    return {
      user_id: userId,
      balance_credits: 0,
      currency: "usd",
      managed_enabled: true,
      auto_recharge_enabled: false,
      billing_backend: this.kind,
    };
  }

  async getWalletSummary(
    _: SupabaseClient,
    __: string,
  ): Promise<WalletSummary> {
    return EMPTY_WALLET_SUMMARY;
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
    return {
      request_id: `${args.requestId}:asr`,
      usage_event_id: crypto.randomUUID(),
      allowed: true,
      reason: null,
      retry_after_seconds: null,
      balance_credits: 0,
      reserved_credits: 0,
      usage_kind: "asr" as const,
      provider: args.provider,
      quantity: args.audioDurationSeconds,
    };
  }

  async finalizeTranscriptionUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    provider: "openai" | "groq";
    audioDurationSeconds: number;
    transcriptionText: string;
    upstreamStatus: number;
  }): Promise<UsageSettlement> {
    return {
      billedCredits: 0,
      transcriptionChars: countNormalizedChars(args.transcriptionText),
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
    return {
      request_id: `${args.requestId}:rewrite`,
      usage_event_id: crypto.randomUUID(),
      allowed: true,
      reason: null,
      retry_after_seconds: null,
      balance_credits: 0,
      reserved_credits: 0,
      usage_kind: "rewrite" as const,
      provider: args.provider,
      quantity: countNormalizedChars(args.inputText),
    };
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
    return {
      billedCredits: 0,
      transcriptionChars: countNormalizedChars(args.outputText),
    };
  }

  async refundUsage(_: {
    admin: SupabaseClient;
    usageEventId: string;
    upstreamStatus?: number | null;
  }): Promise<void> {
    return;
  }

  async handleStripeWebhook(_: {
    admin: SupabaseClient;
    requestId: string;
    rawBody: string;
    signatureHeader: string;
  }): Promise<TopupWebhookResult> {
    throw new ApiError(
      501,
      "billing_backend_unavailable",
      "Stripe top-ups are not available when RELAY_BILLING_BACKEND=unmetered.",
    );
  }
}

function countNormalizedChars(text: string): number {
  const normalized = text.trim().replace(/\s+/gu, " ");
  return normalized ? Array.from(normalized).length : 0;
}
