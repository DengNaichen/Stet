import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "../error.ts";
import { log } from "../log.ts";
import { GroqModels, OpenAIModels } from "../providers/models.ts";
import type { AIProvider, TranscribeOptions } from "../providers/provider.ts";
import type { RelayBillingBackend } from "../billing_backend.ts";

export async function performTranscription(args: {
  requestId: string;
  admin: SupabaseClient;
  userId: string;
  audio: Uint8Array;
  audioDurationSeconds: number;
  options?: TranscribeOptions;
  provider: AIProvider;
  providerName: "openai" | "groq";
  billingBackend: RelayBillingBackend;
}) {
  if (
    !Number.isFinite(args.audioDurationSeconds) ||
    args.audioDurationSeconds <= 0
  ) {
    throw new ApiError(
      400,
      "missing_audio_duration",
      "Managed Relay requires the audio duration for pay-as-you-go billing.",
    );
  }

  const usage = await args.billingBackend.beginTranscriptionUsage({
    admin: args.admin,
    userId: args.userId,
    requestId: args.requestId,
    provider: args.providerName,
    modelId: args.providerName === "groq"
      ? GroqModels.TRANSCRIBE
      : OpenAIModels.TRANSCRIBE,
    audioDurationSeconds: args.audioDurationSeconds,
  });
  const transcriptionModelId = args.providerName === "groq"
    ? GroqModels.TRANSCRIBE
    : OpenAIModels.TRANSCRIBE;

  log("info", "transcription_started", args.requestId, {
    userId: args.userId,
    audioBytes: args.audio.length,
    audioDurationSeconds: args.audioDurationSeconds,
    language: args.options?.language ?? null,
    hasPrompt: Boolean(args.options?.prompt),
    transcriptionModel: transcriptionModelId,
    reservedCredits: usage.reserved_credits,
  });

  try {
    const result = await args.provider.transcribe(args.audio, args.options);
    const settlement = await args.billingBackend.finalizeTranscriptionUsage({
      admin: args.admin,
      usageEventId: usage.usage_event_id,
      provider: args.providerName,
      audioDurationSeconds: args.audioDurationSeconds,
      transcriptionText: result.text,
      upstreamStatus: 200,
    });

    log("info", "transcription_completed", args.requestId, {
      userId: args.userId,
      transcriptionModel: transcriptionModelId,
      textLength: result.text.length,
      transcriptionText: result.text,
      transcriptionChars: settlement.transcriptionChars,
      billedCredits: settlement.billedCredits,
    });

    return {
      text: result.text,
      usageEventId: usage.usage_event_id,
      transcriptionChars: settlement.transcriptionChars,
      billedCredits: settlement.billedCredits,
    };
  } catch (error) {
    await args.billingBackend.refundUsage({
      admin: args.admin,
      usageEventId: usage.usage_event_id,
      upstreamStatus: 502,
    }).catch(() => {});

    log("error", "transcription_failed", args.requestId, {
      userId: args.userId,
      error: error instanceof Error ? error.message : "unknown_error",
    });

    if (error instanceof ApiError) throw error;
    throw new ApiError(
      502,
      "transcription_error",
      "The upstream transcription service failed.",
    );
  }
}
