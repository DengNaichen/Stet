import { generateText, experimental_transcribe as transcribe } from "npm:ai";
import { createOpenAI } from "npm:@ai-sdk/openai";
import { AIProvider, RewriteResult, TranscribeOptions } from "./provider.ts";
import { requireEnv } from "../utils.ts";
import { OpenAIModels } from "./models.ts";

export class OpenAIProvider implements AIProvider {
    private client: any;
    private model: any;
    private transcriptionModelId: string;

    constructor(options?: { modelId?: string; transcriptionModelId?: string }) {
        const apiKey = requireEnv("OPENAI_API_KEY");

        this.client = createOpenAI({
            apiKey: apiKey,
        });
        this.model = this.client(options?.modelId || OpenAIModels.REWRITE);
        this.transcriptionModelId = options?.transcriptionModelId || OpenAIModels.TRANSCRIBE;
    }

    async rewrite(text: string, systemPrompt: string): Promise<RewriteResult> {
        const result = await generateText({
            model: this.model,
            system: systemPrompt,
            prompt: text,
        });

        return {
            text: result.text,
            usage: {
                inputTokens: result.usage.inputTokens ?? 0,
                outputTokens: result.usage.outputTokens ?? 0,
                totalTokens: result.usage.totalTokens ?? 0,
            },
        };
    }

    async transcribe(audio: Uint8Array, options?: TranscribeOptions): Promise<{ text: string }> {
        const providerOpts: Record<string, string> = {};
        if (options?.language) providerOpts.language = options.language;
        if (options?.prompt) providerOpts.prompt = options.prompt;

        const { text } = await transcribe({
            model: this.client.transcription(this.transcriptionModelId),
            audio: audio,
            ...(Object.keys(providerOpts).length > 0
                ? { providerOptions: { openai: providerOpts } }
                : {}),
        });

        return { text };
    }
}
