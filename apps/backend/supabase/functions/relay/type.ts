import { SupabaseClient, User } from "@supabase/supabase-js";

export type UsageLimitReason =
    | "request_limit_exceeded"
    | "transcription_chars_limit_exceeded"
    | "account_disabled";


export type ManagedEntitlement = {
    user_id: string;
    managed_enabled: boolean;
    requests_per_minute: number;
    weekly_transcription_chars: number;
    min_billed_chars_per_transcription: number;
    created_at: string;
    updated_at: string;
}

export type TranscriptionUsageReservation = {
    request_id: string;
    usage_event_id: string;
    allowed: boolean;
    reason: UsageLimitReason | null;
    retry_after_seconds: number | null;
    requests_remaining: number;
    weekly_transcription_chars_remaining: number;
    requests_used_last_minute: number;
    transcription_chars_used_last_week: number;
    reserved_billed_chars: number;
}

export type FinalizedTranscriptionUsage = {
    transcription_chars: number;
    billed_chars: number;
}

export type UsageSummary = {
    requests_used_last_minute: number;
    transcription_chars_used_last_week: number;
}

export type HonoVariables = {
    requestId: string;
    admin: SupabaseClient;
    user: User;
    entitlement: ManagedEntitlement;
}
