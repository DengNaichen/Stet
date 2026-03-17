import { generateText, experimental_transcribe as transcribe } from "npm:ai";
import { groq } from "npm:@ai-sdk/groq";
import { AIProvider, TranscribeOptions } from "./provider.ts";
import { requireEnv } from "../utils.ts";
import { GroqModels } from "./models.ts";

export class GroqProvider implements AIProvider {
    private model: any;
    private transcriptionModelId: string;

    constructor(options?: { modelId?: string; transcriptionModelId?: string }) {
        const apiKey = requireEnv("GROQ_API_KEY");

        const client = groq({
            apiKey: apiKey,
        });

        this.model = client(options?.modelId || GroqModels.REWRITE);
        this.transcriptionModelId = options?.transcriptionModelId || GroqModels.TRANSCRIBE;
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
            model: groq.transcription(this.transcriptionModelId),
            audio: audio,
            ...(Object.keys(providerOpts).length > 0
                ? { providerOptions: { groq: providerOpts } }
                : {}),
        });

        return { text };
    }
}

