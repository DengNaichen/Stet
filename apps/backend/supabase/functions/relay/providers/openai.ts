import { generateText, experimental_transcribe as transcribe } from "npm:ai";
import { openai } from "npm:@ai-sdk/openai";
import { AIProvider, TranscribeOptions } from "./provider.ts";
import { requireEnv } from "../utils.ts";
import { OpenAIModels } from "./models.ts";

export class OpenAIProvider implements AIProvider {
    private model: any;
    private transcriptionModelId: string;

    constructor(options?: { modelId?: string; transcriptionModelId?: string }) {
        const apiKey = requireEnv("OPENAI_API_KEY");

        const client = openai({
            apiKey: apiKey,
        });
        this.model = client(options?.modelId || OpenAIModels.REWRITE);
        this.transcriptionModelId = options?.transcriptionModelId || OpenAIModels.TRANSCRIBE;
    }

    async rewrite(text: string, systemPrompt: string): Promise<{ text: string }> {
        const { text: resultText } = await generateText({
            model: this.model,
            system: systemPrompt,
            prompt: text,
        });

        return { text: resultText };
    }

    async transcribe(audio: Uint8Array, options?: TranscribeOptions): Promise<{ text: string }> {
        const providerOpts: Record<string, unknown> = {};
        if (options?.language) providerOpts.language = options.language;
        if (options?.prompt) providerOpts.prompt = options.prompt;

        const { text } = await transcribe({
            model: openai.transcription(this.transcriptionModelId),
            audio: audio,
            ...(Object.keys(providerOpts).length > 0
                ? { providerOptions: { openai: providerOpts } }
                : {}),
        });

        return { text };
    }
}

