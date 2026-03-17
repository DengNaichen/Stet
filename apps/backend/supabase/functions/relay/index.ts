import "@supabase/functions-js/edge-runtime.d.ts";

import { Hono } from "hono";
import { authGuard } from "./middleware/auth.ts";
import { log } from "./log.ts";
import { ApiError } from "./error.ts";
import { getUsageSummary } from "./usage.ts";
import { performTranscription } from "./ai/transcribe.ts";
import { performRewrite } from "./ai/rewrite.ts";
import { OpenAIProvider } from "./providers/openai.ts";
import { GroqProvider } from "./providers/groq.ts";
import type { AIProvider } from "./providers/provider.ts";
import type { HonoVariables } from "./type.ts";

// ---------------------------------------------------------------------------
// Provider selection
// ---------------------------------------------------------------------------

type ProviderName = "openai" | "groq";

const configuredProvider = Deno.env.get("AI_PROVIDER")?.trim().toLowerCase();
const PROVIDER_NAME: ProviderName = configuredProvider === "groq" ? "groq" : "openai";

function makeProvider(): AIProvider {
	switch (PROVIDER_NAME) {
		case "groq":
			return new GroqProvider();
		case "openai":
		default:
			return new OpenAIProvider();
	}
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

const app = new Hono<{ Variables: HonoVariables }>();

// Request-ID middleware
app.use("*", async (c, next) => {
	const requestId = sanitizeRequestId(c.req.header("x-request-id"));
	c.set("requestId", requestId);
	await next();
	c.header("x-request-id", requestId);
});

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

app.get("/healthz", (c) => {
	log("info", "healthz", c.get("requestId"), {
		provider: PROVIDER_NAME,
		openaiConfigured: Boolean(Deno.env.get("OPENAI_API_KEY")?.trim()),
		groqConfigured: Boolean(Deno.env.get("GROQ_API_KEY")?.trim()),
	});

	return c.json({
		status: "ok",
		service: "stet-managed-relay",
		version: 2,
		provider: PROVIDER_NAME,
	});
});

// ---------------------------------------------------------------------------
// Auth guard
// ---------------------------------------------------------------------------

app.use("/me/*", authGuard);
app.use("/audio/*", authGuard);

// ---------------------------------------------------------------------------
// GET /me/quota
// ---------------------------------------------------------------------------

app.get("/me/quota", async (c) => {
	const admin = c.get("admin");
	const user = c.get("user");
	const entitlement = c.get("entitlement");
	const usage = await getUsageSummary(admin, user.id);

	return c.json({
		user: {
			id: user.id,
			email: user.email ?? null,
		},
		entitlement,
		usage,
	});
});

// ---------------------------------------------------------------------------
// POST /audio/transcriptions
//
// Single endpoint for the full dictation pipeline:
//   1. Transcribe audio to text
//   2. Optionally rewrite the transcript (controlled by `rewrite` field)
//
// Accepts multipart/form-data:
//   file                  audio file (required) — WAV or M4A
//   prompt                transcription prompt / preferred spellings (optional)
//   language              ISO-639-1 locale code (optional)
//   rewrite               "true" to enable post-transcription cleanup (optional)
//   preferred_spellings   comma-separated list of names/terms (optional)
//
// Response: { text, rewritten }
// ---------------------------------------------------------------------------

app.post("/audio/transcriptions", async (c) => {
	const requestId = c.get("requestId");
	const admin = c.get("admin");
	const user = c.get("user");

	// Parse multipart form
	const formData = await c.req.raw.formData();
	const file = formData.get("file");
	if (!(file instanceof File)) {
		throw new ApiError(400, "missing_file", "The transcription request must include a file.");
	}

	const prompt = readFormDataString(formData, "prompt");
	const language = readFormDataString(formData, "language");
	const shouldRewrite = readFormDataString(formData, "rewrite") === "true";
	const preferredSpellings = parsePreferredSpellings(formData);

	const provider = makeProvider();
	const audioBytes = new Uint8Array(await file.arrayBuffer());

	log("info", "dictation_pipeline_started", requestId, {
		userId: user.id,
		provider: PROVIDER_NAME,
		fileName: file.name,
		fileSize: file.size,
		language,
		hasPrompt: Boolean(prompt),
		rewrite: shouldRewrite,
		preferredSpellingsCount: preferredSpellings.length,
	});

	// Step 1: Transcribe
	const transcription = await performTranscription({
		requestId,
		admin,
		userId: user.id,
		audio: audioBytes,
		options: {
			language: language ?? undefined,
			prompt: prompt ?? undefined,
		},
		provider,
		providerName: PROVIDER_NAME,
	});

	let finalText = transcription.text;
	let rewritten = false;

	// Step 2: Optionally rewrite
	if (shouldRewrite && finalText.trim()) {
		const rewriteResult = await performRewrite({
			requestId,
			userId: user.id,
			rawText: finalText,
			provider,
			preferredSpellings,
		});

		finalText = rewriteResult.text;
		rewritten = true;
	}

	log("info", "dictation_pipeline_completed", requestId, {
		userId: user.id,
		textLength: finalText.length,
		transcriptionChars: transcription.transcriptionChars,
		billedChars: transcription.billedChars,
		rewritten,
	});

	return c.json({
		text: finalText,
		rewritten,
	});
});

// ---------------------------------------------------------------------------
// Fallback
// ---------------------------------------------------------------------------

app.notFound(() => {
	throw new ApiError(404, "not_found", "The requested relay endpoint was not found.");
});

// ---------------------------------------------------------------------------
// Error handler
// ---------------------------------------------------------------------------

app.onError((error, c) => {
	const requestId = c.get("requestId") || crypto.randomUUID();

	if (error instanceof ApiError) {
		log(error.status >= 500 ? "error" : "warn", "api_error", requestId, {
			status: error.status,
			code: error.code,
		});

		return c.json(
			{
				code: error.code,
				message: error.message,
				retry_after_seconds: error.retryAfterSeconds ?? null,
				request_id: requestId,
			},
			error.status
		);
	}

	log("error", "unhandled_error", requestId, { message: error.message });
	return c.json(
		{
			code: "internal_error",
			message: "The relay encountered an unexpected error.",
			request_id: requestId,
		},
		500
	);
});

// ---------------------------------------------------------------------------
// Serve
// ---------------------------------------------------------------------------

Deno.serve((request) => app.fetch(rewriteForRelayBasePath(request)));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function rewriteForRelayBasePath(request: Request): Request {
	const url = new URL(request.url);
	const marker = "/v1";
	const markerIndex = url.pathname.lastIndexOf(marker);

	if (markerIndex >= 0) {
		url.pathname = url.pathname.slice(markerIndex + marker.length) || "/";
	}

	return new Request(url, request);
}

function sanitizeRequestId(value: string | undefined): string {
	const trimmed = value?.trim();
	if (!trimmed) {
		return crypto.randomUUID();
	}

	if (trimmed.length > 128) {
		return crypto.randomUUID();
	}

	return trimmed;
}

function readFormDataString(formData: FormData, key: string): string | null {
	const value = formData.get(key);
	return typeof value === "string" && value.trim() ? value.trim() : null;
}

function parsePreferredSpellings(formData: FormData): string[] {
	const raw = readFormDataString(formData, "preferred_spellings");
	if (!raw) return [];
	return raw
		.split(",")
		.map((s) => s.trim())
		.filter(Boolean);
}
