import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "./error.ts";
import { getRelayPolicy } from "./config.ts";
import {
  CreditTopupResult,
  UsageKind,
  UsageReservation,
  WalletSummary,
} from "./billing_backend.ts";

type ProviderName = "openai" | "groq";

export async function getWalletSummary(
  admin: SupabaseClient,
  userId: string,
): Promise<WalletSummary> {
  let data;
  let error;
  try {
    ({ data, error } = await admin.rpc("get_managed_wallet_summary", {
      p_user_id: userId,
    }));
  } catch {
    throw new ApiError(
      500,
      "wallet_summary_rpc_failed",
      "The relay could not load wallet details from the database.",
    );
  }

  if (error || !data || !Array.isArray(data) || !data[0]) {
    throw new ApiError(
      500,
      "wallet_summary_error",
      "The relay could not load wallet details.",
    );
  }

  return data[0] as WalletSummary;
}

export async function beginUsage(
  admin: SupabaseClient,
  args: {
    userId: string;
    requestId: string;
    usageKind: UsageKind;
    provider: ProviderName;
    quantity: number;
    reservedCredits: number;
    modelId?: string;
    requestMetadata?: Record<string, unknown>;
  },
): Promise<UsageReservation> {
  const policy = getRelayPolicy();
  let data;
  let error;
  try {
    ({ data, error } = await admin.rpc("begin_managed_usage", {
      p_user_id: args.userId,
      p_request_id: args.requestId,
      p_usage_kind: args.usageKind,
      p_provider: args.provider,
      p_model_id: args.modelId ?? null,
      p_quantity: args.quantity,
      p_reserved_credits: args.reservedCredits,
      p_request_metadata: args.requestMetadata ?? {},
      p_max_requests_per_minute: policy.maxRequestsPerMinute,
      p_max_concurrent_requests: policy.maxConcurrentRequests,
      p_daily_credit_limit: policy.dailyCreditLimit,
    }));
  } catch {
    throw new ApiError(
      500,
      "usage_begin_rpc_failed",
      "The relay could not evaluate account credits in the database.",
    );
  }

  if (error?.code === "23505") {
    throw new ApiError(
      409,
      "duplicate_request",
      "This request has already been processed.",
    );
  }

  if (error || !data || !Array.isArray(data) || !data[0]) {
    throw new ApiError(
      500,
      "usage_begin_error",
      "The relay could not evaluate account credits.",
    );
  }

  const result = data[0] as UsageReservation;

  if (!result.allowed) {
    throw new ApiError(
      result.reason === "insufficient_credits" ? 402 : 429,
      result.reason === "insufficient_credits"
        ? "payment_required"
        : "rate_limited",
      result.reason === "insufficient_credits"
        ? "This account does not have enough credits for this request."
        : "This account has hit its managed request rate limit.",
      result.retry_after_seconds ?? undefined,
    );
  }

  if (!result.usage_event_id) {
    throw new ApiError(
      500,
      "usage_begin_error",
      "The relay could not reserve credits for this request.",
    );
  }

  return result;
}

export async function finalizeUsage(
  admin: SupabaseClient,
  args: {
    usageEventId: string;
    actualQuantity: number;
    billedCredits: number;
    transcriptionChars: number;
    inputTokens: number;
    outputTokens: number;
    upstreamStatus: number;
  },
): Promise<void> {
  let error;
  try {
    ({ error } = await admin.rpc("finalize_managed_usage", {
      p_usage_event_id: args.usageEventId,
      p_actual_quantity: args.actualQuantity,
      p_billed_credits: args.billedCredits,
      p_transcription_chars: args.transcriptionChars,
      p_input_tokens: args.inputTokens,
      p_output_tokens: args.outputTokens,
      p_upstream_status: args.upstreamStatus,
    }));
  } catch {
    throw new ApiError(
      500,
      "usage_finalize_rpc_failed",
      "The relay could not finalize usage in the database.",
    );
  }

  if (error) {
    throw new ApiError(
      500,
      "usage_finalize_error",
      "The relay could not finalize usage.",
    );
  }
}

export async function refundUsage(
  admin: SupabaseClient,
  args: {
    usageEventId: string;
    upstreamStatus?: number | null;
  },
): Promise<void> {
  let error;
  try {
    ({ error } = await admin.rpc("refund_managed_usage", {
      p_usage_event_id: args.usageEventId,
      p_upstream_status: args.upstreamStatus ?? null,
    }));
  } catch {
    throw new ApiError(
      500,
      "usage_refund_rpc_failed",
      "The relay could not refund reserved credits in the database.",
    );
  }

  if (error) {
    throw new ApiError(
      500,
      "usage_refund_error",
      "The relay could not refund reserved credits.",
    );
  }
}

export async function applyCreditTopup(
  admin: SupabaseClient,
  args: {
    userId: string;
    credits: number;
    externalReference: string;
    metadata?: Record<string, unknown>;
    provider?: string;
  },
): Promise<CreditTopupResult> {
  let data;
  let error;
  try {
    ({ data, error } = await admin.rpc("apply_credit_topup", {
      p_user_id: args.userId,
      p_credits: args.credits,
      p_external_reference: args.externalReference,
      p_metadata: args.metadata ?? {},
      p_provider: args.provider ?? "stripe",
    }));
  } catch {
    throw new ApiError(
      500,
      "credit_topup_rpc_failed",
      "The relay could not apply the credit top-up.",
    );
  }

  if (error || !data || !Array.isArray(data) || !data[0]) {
    throw new ApiError(
      500,
      "credit_topup_error",
      "The relay could not apply the credit top-up.",
    );
  }

  return data[0] as CreditTopupResult;
}

export function countTranscriptionChars(text: string): number {
  const normalized = normalizeTranscriptionText(text);
  return normalized ? Array.from(normalized).length : 0;
}

export function normalizeTranscriptionText(text: string): string {
  return text.trim().replace(/\s+/gu, " ");
}
