import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "./error.ts";
import {
    FinalizedTranscriptionUsage,
    TranscriptionUsageReservation,
    UsageSummary,
} from "./type.ts";

type ProviderName = "openai" | "groq";

export async function getUsageSummary(
    admin: SupabaseClient,
    userId: string
): Promise<UsageSummary> {
    const { data, error } = await admin.rpc("get_managed_usage_summary", {
        p_user_id: userId,
    });

    if (error || !data || !Array.isArray(data) || !data[0]) {
        throw new ApiError(500, "usage_summary_error", "The relay could not load quota usage.");
    }

    return data[0] as UsageSummary;
}

export async function beginTranscriptionUsage(
    admin: SupabaseClient,
    args: {
        userId: string;
        requestId: string;
        provider: ProviderName;
    }
): Promise<TranscriptionUsageReservation> {
    const { data, error } = await admin.rpc("begin_managed_transcription_usage", {
        p_user_id: args.userId,
        p_request_id: args.requestId,
        p_provider: args.provider,
    });

    if (error?.code === "23505") {
        throw new ApiError(409, "duplicate_request", "This request has already been processed.");
    }

    if (error || !data || !Array.isArray(data) || !data[0]) {
        throw new ApiError(500, "quota_error", "The relay could not evaluate the current quota.");
    }

    const result = data[0] as TranscriptionUsageReservation;

    if (!result.allowed) {
        throw new ApiError(
            429,
            result.reason === "transcription_chars_limit_exceeded"
                ? "quota_exceeded"
                : "rate_limited",
            result.reason === "transcription_chars_limit_exceeded"
                ? "This account has exhausted its weekly managed transcription quota."
                : "This account has hit its managed request rate limit.",
            result.retry_after_seconds ?? undefined
        );
    }

    if (!result.usage_event_id) {
        throw new ApiError(500, "quota_error", "The relay could not reserve usage for this request.");
    }

    return result;
}

export async function finalizeTranscriptionUsage(
    admin: SupabaseClient,
    args: {
        usageEventId: string;
        upstreamStatus: number;
        rawText: string;
        reservedBilledChars: number;
    }
): Promise<FinalizedTranscriptionUsage> {
    const transcriptionChars = countTranscriptionChars(args.rawText);
    const billedChars =
        args.upstreamStatus >= 200 && args.upstreamStatus < 300
            ? Math.max(args.reservedBilledChars, transcriptionChars)
            : 0;

    const { error } = await admin.rpc("finalize_managed_transcription_usage", {
        p_usage_event_id: args.usageEventId,
        p_transcription_chars: transcriptionChars,
        p_billed_chars: billedChars,
        p_upstream_status: args.upstreamStatus,
    });

    if (error) {
        throw new ApiError(500, "usage_finalize_error", "The relay could not finalize usage.");
    }

    return {
        transcription_chars: transcriptionChars,
        billed_chars: billedChars,
    };
}

function countTranscriptionChars(text: string): number {
    const normalized = normalizeTranscriptionText(text);
    return normalized ? Array.from(normalized).length : 0;
}

function normalizeTranscriptionText(text: string): string {
    return text.trim().replace(/\s+/gu, " ");
}
