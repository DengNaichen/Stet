import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "./error.ts";
import { RouteKind, UsageCheckResult, UsageSummary } from "./type.ts";


const PROVIDER = "openai";

export async function getUsageSummary(admin: SupabaseClient, userId: string): Promise<UsageSummary> {
    const { data, error } = await admin.rpc("get_managed_usage_summary", {
        p_user_id: userId
    });

    if (error || !data || !Array.isArray(data) || !data[0]) {
        throw new ApiError(500, "usage_summary_error", "The relay could not load quota usage.");
    }

    return data[0] as UsageSummary;
}

export async function checkAndRecordUsage(
    admin: SupabaseClient,
    args: {
        userId: string;
        requestId: string;
        routeKind: RouteKind;
        audioSeconds: number;
    }
): Promise<UsageCheckResult> {
    const { data, error } = await admin.rpc("check_and_record_managed_usage", {
        p_user_id: args.userId,
        p_request_id: args.requestId,
        p_route_kind: args.routeKind,
        p_request_units: 1,
        p_audio_seconds: args.audioSeconds,
        p_provider: PROVIDER
    });

    if (error || !data || !Array.isArray(data) || !data[0]) {
        throw new ApiError(500, "quota_error", "The relay could not evaluate the current quota.");
    }

    const result = data[0] as UsageCheckResult;

    if (!result.allowed) {
        throw new ApiError(
            429,
            result.reason === "words_limit_exceeded" ? "quota_exceeded" : "rate_limited",
            result.reason === "words_limit_exceeded"
                ? "This account has exhausted its weekly managed quota."
                : "This account has hit its managed request rate limit.",
            result.retry_after_seconds ?? undefined
        );
    }

    return result;
}


export async function markUsageEventStatus(
    admin: SupabaseClient,
    usageEventId: string,
    upstreamStatus: number
) {
    await admin.from("usage_events")
        .update({ upstream_status: upstreamStatus })
        .eq("id", usageEventId);
}
