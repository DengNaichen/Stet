import type { SupabaseClient } from "@supabase/supabase-js";
import type { TextUsage } from "./providers/provider.ts";

export type ProviderName = "openai" | "groq";
export type UsageKind = "asr" | "rewrite";

export type RelayAccount = {
  user_id: string;
  balance_credits: number;
  currency: string;
  managed_enabled: boolean;
  auto_recharge_enabled: boolean;
  billing_backend: string;
  created_at?: string;
  updated_at?: string;
};

export type WalletSummary = {
  balance_credits: number;
  recent_usage_credits_7d: number;
  recent_topup_credits_7d: number;
  total_usage_credits: number;
  total_topup_credits: number;
};

export type UsageReservation = {
  request_id: string;
  usage_event_id: string;
  allowed: boolean;
  reason:
    | "request_limit_exceeded"
    | "insufficient_credits"
    | "account_disabled"
    | null;
  retry_after_seconds: number | null;
  balance_credits: number;
  reserved_credits: number;
  usage_kind: UsageKind;
  provider: string;
  quantity: number;
};

export type UsageSettlement = {
  billedCredits: number;
  transcriptionChars: number;
};

export type CreditTopupResult = {
  balance_credits: number;
  ledger_id: string;
};

export type TopupWebhookResult = {
  received: boolean;
  balance_credits?: number;
};

export interface RelayBillingBackend {
  readonly kind: string;

  resolveAccount(admin: SupabaseClient, userId: string): Promise<RelayAccount>;
  getWalletSummary(
    admin: SupabaseClient,
    userId: string,
  ): Promise<WalletSummary>;

  beginTranscriptionUsage(args: {
    admin: SupabaseClient;
    userId: string;
    requestId: string;
    provider: ProviderName;
    modelId: string;
    audioDurationSeconds: number;
    requestMetadata?: Record<string, unknown>;
  }): Promise<UsageReservation>;

  finalizeTranscriptionUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    provider: ProviderName;
    audioDurationSeconds: number;
    transcriptionText: string;
    upstreamStatus: number;
  }): Promise<UsageSettlement>;

  beginRewriteUsage(args: {
    admin: SupabaseClient;
    userId: string;
    requestId: string;
    provider: ProviderName;
    modelId: string;
    inputText: string;
  }): Promise<UsageReservation>;

  finalizeRewriteUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    provider: ProviderName;
    inputText: string;
    outputText: string;
    usage: TextUsage;
    upstreamStatus: number;
  }): Promise<UsageSettlement>;

  refundUsage(args: {
    admin: SupabaseClient;
    usageEventId: string;
    upstreamStatus?: number | null;
  }): Promise<void>;

  handleStripeWebhook(args: {
    admin: SupabaseClient;
    requestId: string;
    rawBody: string;
    signatureHeader: string;
  }): Promise<TopupWebhookResult>;
}
