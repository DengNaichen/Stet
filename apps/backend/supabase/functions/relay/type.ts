import { SupabaseClient, User } from "@supabase/supabase-js";

export type RouteKind = "responses" | "audio_transcriptions"

export type UsageLimitReason =
    | "request_limit_exceeded"
    | "words_limit_exceeded"
    | "account_disabled";


export type ManagedEntitlement = {
    user_id: string;
    managed_enabled: boolean;
    requests_per_minute: number;
    words_per_week: number;
    created_at: string;
    updated_at: string;
}

export type UsageCheckResult = {
    request_id: string;
    usage_event_id: string | null;
    allowed: boolean;
    reason: UsageLimitReason | null;
    retry_after_seconds: number | null;
    requests_remaining: number;
    words_per_week_remaining: number;
    requests_used_last_minute: number;
}

export type UsageSummary = {
    words_used_last_week: number;
    audio_seconds_used_last_week: number;
}

export type HonoVariables = {
    requestId: string;
    admin: SupabaseClient;
    user: User;
    entitlement: ManagedEntitlement;
}
