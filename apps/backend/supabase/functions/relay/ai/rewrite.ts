import { SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "../error.ts";
import { checkAndRecordUsage } from "../usage.ts";
import { log } from "../log.ts";
import type { AIProvider } from "../providers/provider.ts";

const DEFAULT_REWRITE_PROMPT = `
You are a master editor. Your job is to transform raw speech transcripts into clear, professional, and grammatically correct text. 
Preserve the speaker's original intent and tone, but fix disfluencies (like "um", "uh"), repetitive words, and broken sentences.
`.trim();

export function buildRewritePrompt(options?: {
    customPrompt?: string;
    preferredSpellings?: string[];
}): string {
    let prompt = options?.customPrompt || DEFAULT_REWRITE_PROMPT;

    if (options?.preferredSpellings && options.preferredSpellings.length > 0) {
        prompt += ` Preserve the exact spelling of these names, brands, jargon, and technical terms when they appear or are clearly intended: ${options.preferredSpellings.join(", ")}.`;
    }

    return prompt;
}

export async function performRewrite(args: {
    requestId: string;
    admin: SupabaseClient;
    userId: string;
    rawText: string;
    provider: AIProvider;
    customPrompt?: string;
    preferredSpellings?: string[];
}) {
    const input = args.rawText?.trim();
    if (!input) {
        log("info", "rewrite_skipped_empty", args.requestId, { userId: args.userId });
        return { text: "" };
    }

    const usage = await checkAndRecordUsage(args.admin, {
        userId: args.userId,
        requestId: args.requestId,
        routeKind: "responses",
        audioSeconds: 0
    });

    const systemPrompt = buildRewritePrompt({
        customPrompt: args.customPrompt,
        preferredSpellings: args.preferredSpellings,
    });

    log("info", "rewrite_started", args.requestId, {
        userId: args.userId,
        inputLength: input.length,
        hasPreferredSpellings: Boolean(args.preferredSpellings?.length),
    });

    try {
        const result = await args.provider.rewrite(input, systemPrompt);

        log("info", "rewrite_completed", args.requestId, {
            userId: args.userId,
            usageEventId: usage.usage_event_id
        });

        return {
            text: result.text,
            usageEventId: usage.usage_event_id
        };

    } catch (error) {
        log("error", "rewrite_failed", args.requestId, {
            userId: args.userId,
            error: error instanceof Error ? error.message : "unknown_ai_error"
        });
        throw new ApiError(502, "ai_rewrite_error", "The AI failed to polish your transcript.");
    }
}
