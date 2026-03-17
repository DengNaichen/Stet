import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "../error.ts";
import { beginTranscriptionUsage, finalizeTranscriptionUsage } from "../usage.ts";
import { log } from "../log.ts";
import type { AIProvider, TranscribeOptions } from "../providers/provider.ts";

export async function performTranscription(args: {
    requestId: string;
    admin: SupabaseClient;
    userId: string;
    audio: Uint8Array;
    options?: TranscribeOptions;
    provider: AIProvider;
    providerName: "openai" | "groq";
}) {
    const usage = await beginTranscriptionUsage(args.admin, {
        userId: args.userId,
        requestId: args.requestId,
        provider: args.providerName,
    });

    log("info", "transcription_started", args.requestId, {
        userId: args.userId,
        audioBytes: args.audio.length,
        language: args.options?.language ?? null,
        hasPrompt: Boolean(args.options?.prompt),
        reservedBilledChars: usage.reserved_billed_chars,
    });

    try {
        const result = await args.provider.transcribe(args.audio, args.options);
        const finalizedUsage = await finalizeTranscriptionUsage(args.admin, {
            usageEventId: usage.usage_event_id,
            upstreamStatus: 200,
            rawText: result.text,
            reservedBilledChars: usage.reserved_billed_chars,
        });

        log("info", "transcription_completed", args.requestId, {
            userId: args.userId,
            textLength: result.text.length,
            transcriptionChars: finalizedUsage.transcription_chars,
            billedChars: finalizedUsage.billed_chars,
        });

        return {
            text: result.text,
            usageEventId: usage.usage_event_id,
            transcriptionChars: finalizedUsage.transcription_chars,
            billedChars: finalizedUsage.billed_chars,
        };
    } catch (error) {
        await finalizeTranscriptionUsage(args.admin, {
            usageEventId: usage.usage_event_id,
            upstreamStatus: 502,
            rawText: "",
            reservedBilledChars: usage.reserved_billed_chars,
        }).catch(() => { });

        log("error", "transcription_failed", args.requestId, {
            userId: args.userId,
            error: error instanceof Error ? error.message : "unknown_error",
        });

        if (error instanceof ApiError) throw error;
        throw new ApiError(502, "transcription_error", "The upstream transcription service failed.");
    }
}
