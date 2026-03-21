
export const OpenAIModels = {
    REWRITE: "gpt-5.4-nano-2026-03-17",
    TRANSCRIBE: "whisper-1",
} as const;

/**
 * Groq 模型家族
 */
export const GroqModels = {
    REWRITE: "openai/gpt-oss-120b",
    TRANSCRIBE: "whisper-large-v3-turbo",
} as const;
