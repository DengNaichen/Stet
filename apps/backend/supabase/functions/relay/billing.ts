import type { TextUsage } from "./providers/provider.ts";

type ProviderName = "openai" | "groq";
type UsageKind = "asr" | "rewrite";

const GROQ_HOURLY_USD = 0.04;
const GROQ_GPT_OSS_120B_INPUT_USD_PER_M_TOKENS = 0.15;
const GROQ_GPT_OSS_120B_OUTPUT_USD_PER_M_TOKENS = 0.60;
const MICRO_CREDITS_PER_USD = 1_000_000;

const LEGACY_OPENAI_ASR_CREDITS_PER_SECOND = 1;
const LEGACY_OPENAI_REWRITE_CREDITS_PER_100_CHARS = 1;

export function quoteReservedCredits(args: {
    provider: ProviderName;
    usageKind: UsageKind;
    quantity: number;
    text?: string;
}): {
    reservedCredits: number;
    estimatedInputTokens?: number;
    estimatedOutputTokens?: number;
} {
    if (args.provider === "groq") {
        if (args.usageKind === "asr") {
            return {
                reservedCredits: quoteGroqAsrCredits(args.quantity),
            };
        }

        const estimatedInputTokens = estimateTokensFromText(args.text ?? "");
        const estimatedOutputTokens = Math.max(32, Math.ceil(estimatedInputTokens * 0.75));
        return {
            reservedCredits: quoteGroqRewriteCredits({
                inputTokens: estimatedInputTokens,
                outputTokens: estimatedOutputTokens,
            }),
            estimatedInputTokens,
            estimatedOutputTokens,
        };
    }

    if (args.usageKind === "asr") {
        return {
            reservedCredits: Math.max(1, Math.ceil(args.quantity) * LEGACY_OPENAI_ASR_CREDITS_PER_SECOND),
        };
    }

    const estimatedInputTokens = estimateTokensFromText(args.text ?? "");
    return {
        reservedCredits: Math.max(
            1,
            Math.ceil(normalizeText(args.text ?? "").length / 100) * LEGACY_OPENAI_REWRITE_CREDITS_PER_100_CHARS
        ),
        estimatedInputTokens,
        estimatedOutputTokens: undefined,
    };
}

export function quoteActualCredits(args: {
    provider: ProviderName;
    usageKind: UsageKind;
    quantity: number;
    text?: string;
    usage?: TextUsage;
}): number {
    if (args.provider === "groq") {
        if (args.usageKind === "asr") {
            return quoteGroqAsrCredits(args.quantity);
        }

        const usage = args.usage ?? {
            inputTokens: estimateTokensFromText(args.text ?? ""),
            outputTokens: 0,
            totalTokens: 0,
        };
        return quoteGroqRewriteCredits({
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
        });
    }

    if (args.usageKind === "asr") {
        return Math.max(1, Math.ceil(args.quantity) * LEGACY_OPENAI_ASR_CREDITS_PER_SECOND);
    }

    const normalizedText = normalizeText(args.text ?? "");
    return Math.max(
        1,
        Math.ceil(normalizedText.length / 100) * LEGACY_OPENAI_REWRITE_CREDITS_PER_100_CHARS
    );
}

export function quoteGroqAsrCredits(durationSeconds: number): number {
    if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
        return 1;
    }

    const creditsPerSecond = (GROQ_HOURLY_USD / 3600) * MICRO_CREDITS_PER_USD;
    return Math.max(1, Math.ceil(durationSeconds * creditsPerSecond));
}

export function quoteGroqRewriteCredits(args: {
    inputTokens: number;
    outputTokens: number;
}): number {
    const inputCredits = Math.max(0, args.inputTokens) * GROQ_GPT_OSS_120B_INPUT_USD_PER_M_TOKENS;
    const outputCredits = Math.max(0, args.outputTokens) * GROQ_GPT_OSS_120B_OUTPUT_USD_PER_M_TOKENS;
    return Math.max(1, Math.ceil(inputCredits + outputCredits));
}

export function estimateTokensFromText(text: string): number {
    const normalized = normalizeText(text);
    if (!normalized) return 0;
    // We use a safe length/3 baseline.
    // Thanks to the finalization fix allowing negative balances,
    // if this underestimates for Chinese characters, the user simply goes slightly into the negative,
    // avoiding the transaction rollback bug entirely while keeping reservations low for English users.
    return Math.max(1, Math.ceil(normalized.length / 3));
}

export function normalizeText(text: string): string {
    return text.trim().replace(/\s+/gu, " ");
}
