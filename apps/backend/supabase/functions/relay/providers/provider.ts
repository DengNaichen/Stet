/**
 * Shared AI provider interface.
 *
 * Transcription and rewrite are separate capabilities that happen to be
 * provided by the same upstream services (OpenAI, Groq).  Keeping them
 * in a single interface makes provider construction simple while letting
 * the business-logic modules (`transcribe.ts`, `rewrite.ts`) each pull
 * only the method they need.
 */

export interface TranscribeOptions {
    language?: string;
    prompt?: string;
}

export interface AIProvider {
    transcribe(audio: Uint8Array, options?: TranscribeOptions): Promise<{ text: string }>;
    rewrite(text: string, systemPrompt: string): Promise<{ text: string }>;
}
