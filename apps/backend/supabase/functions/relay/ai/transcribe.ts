import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "../error.ts";
import { checkAndRecordUsage, markUsageEventStatus } from "../usage.ts";
import { log } from "../log.ts";
import type { AIProvider, TranscribeOptions } from "../providers/provider.ts";

export async function performTranscription(args: {
    requestId: string;
    admin: SupabaseClient;
    userId: string;
    audio: Uint8Array;
    options?: TranscribeOptions;
    provider: AIProvider;
    audioSeconds: number;
}) {
    const usage = await checkAndRecordUsage(args.admin, {
        userId: args.userId,
        requestId: args.requestId,
        routeKind: "audio_transcriptions",
        audioSeconds: args.audioSeconds,
    });

    log("info", "transcription_started", args.requestId, {
        userId: args.userId,
        audioBytes: args.audio.length,
        audioSeconds: args.audioSeconds,
        language: args.options?.language ?? null,
        hasPrompt: Boolean(args.options?.prompt),
    });

    try {
        const result = await args.provider.transcribe(args.audio, args.options);

        await markUsageEventStatus(args.admin, usage.usage_event_id!, 200);

        log("info", "transcription_completed", args.requestId, {
            userId: args.userId,
            textLength: result.text.length,
        });

        return {
            text: result.text,
            usageEventId: usage.usage_event_id,
        };
    } catch (error) {
        if (usage.usage_event_id) {
            await markUsageEventStatus(args.admin, usage.usage_event_id, 502).catch(() => { });
        }

        log("error", "transcription_failed", args.requestId, {
            userId: args.userId,
            error: error instanceof Error ? error.message : "unknown_error",
        });

        if (error instanceof ApiError) throw error;
        throw new ApiError(502, "transcription_error", "The upstream transcription service failed.");
    }
}
