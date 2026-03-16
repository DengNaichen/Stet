import "@supabase/functions-js/edge-runtime.d.ts";

import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";
import { Hono } from "hono";

type RouteKind = "responses" | "audio_transcriptions";

type ManagedEntitlement = {
	user_id: string;
	managed_enabled: boolean;
	requests_per_minute: number;
	daily_audio_seconds: number;
	created_at: string;
	updated_at: string;
};

type UsageCheckResult = {
	allowed: boolean;
	reason: string | null;
	retry_after_seconds: number | null;
	request_id: string;
	usage_event_id: string | null;
	requests_remaining: number;
	daily_audio_seconds_remaining: number;
	requests_used_last_minute: number;
	audio_seconds_used_last_day: number;
};

type UsageSummary = {
	requests_used_last_minute: number;
	audio_seconds_used_last_day: number;
};

type HonoVariables = {
	requestId: string;
	admin: SupabaseClient;
	user: User;
	entitlement: ManagedEntitlement;
};

class ApiError extends Error {
	status: number;
	code: string;
	retryAfterSeconds?: number;

	constructor(status: number, code: string, message: string, retryAfterSeconds?: number) {
		super(message);
		this.status = status;
		this.code = code;
		this.retryAfterSeconds = retryAfterSeconds;
	}
}

const TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe";
const RESPONSES_MODEL = "gpt-5-mini";
const PROVIDER = "openai";

const app = new Hono<{ Variables: HonoVariables }>();

app.use("*", async (c, next) => {
	const requestId = c.req.header("x-request-id")?.trim() || crypto.randomUUID();
	c.set("requestId", requestId);
	await next();
	c.header("x-request-id", requestId);
});

app.get("/healthz", (c) => {
	log("info", "healthz", c.get("requestId"), {
		openaiConfigured: Boolean(Deno.env.get("OPENAI_API_KEY")?.trim())
	});

	return c.json({
		status: "ok",
		service: "airtype-managed-relay",
		version: 1,
		provider: PROVIDER,
		openai_configured: Boolean(Deno.env.get("OPENAI_API_KEY")?.trim())
	});
});

app.use("/me/*", authGuard);
app.use("/audio/*", authGuard);
app.use("/responses", authGuard);

app.get("/me/quota", async (c) => {
	const admin = c.get("admin");
	const user = c.get("user");
	const entitlement = c.get("entitlement");
	const usage = await getUsageSummary(admin, user.id);

	return c.json({
		user: {
			id: user.id,
			email: user.email ?? null
		},
		entitlement,
		usage
	});
});

app.post("/audio/transcriptions", async (c) => {
	const requestId = c.get("requestId");
	const admin = c.get("admin");
	const user = c.get("user");
	const durationSeconds = parseAudioDurationSeconds(
		c.req.header("x-airtype-audio-duration-seconds")
	);

	const formData = await c.req.raw.formData();
	const file = formData.get("file");
	if (!(file instanceof File)) {
		throw new ApiError(400, "missing_file", "The transcription request must include a file.");
	}

	const prompt = readFormDataString(formData, "prompt");
	const language = readFormDataString(formData, "language");
	const usage = await checkAndRecordUsage(admin, {
		userId: user.id,
		requestId,
		routeKind: "audio_transcriptions",
		audioSeconds: durationSeconds
	});

	const upstreamForm = new FormData();
	upstreamForm.set("file", file, file.name);
	upstreamForm.set("model", TRANSCRIPTION_MODEL);
	if (prompt) upstreamForm.set("prompt", prompt);
	if (language) upstreamForm.set("language", language);

	return await relayToOpenAI({
		requestId,
		admin,
		usageEventId: usage.usage_event_id,
		path: "/audio/transcriptions",
		method: "POST",
		body: upstreamForm
	});
});

app.post("/responses", async (c) => {
	const requestId = c.get("requestId");
	const admin = c.get("admin");
	const user = c.get("user");
	const payload = (await c.req.json().catch(() => {
		throw new ApiError(400, "invalid_json", "The responses request body must be valid JSON.");
	})) as Record<string, unknown>;

	if (!("input" in payload) || payload.input == null) {
		throw new ApiError(400, "missing_input", "The responses request must include input.");
	}

	const usage = await checkAndRecordUsage(admin, {
		userId: user.id,
		requestId,
		routeKind: "responses",
		audioSeconds: 0
	});

	return await relayToOpenAI({
		requestId,
		admin,
		usageEventId: usage.usage_event_id,
		path: "/responses",
		method: "POST",
		body: JSON.stringify({
			model: RESPONSES_MODEL,
			input: payload.input,
			store: false
		}),
		headers: {
			"content-type": "application/json"
		}
	});
});

app.notFound(() => {
	throw new ApiError(404, "not_found", "The requested relay endpoint was not found.");
});

app.onError((error, c) => {
	const requestId = c.get("requestId") || crypto.randomUUID();

	if (error instanceof ApiError) {
		log(error.status >= 500 ? "error" : "warn", "api_error", requestId, {
			status: error.status,
			code: error.code
		});

		return c.json(
			{
				code: error.code,
				message: error.message,
				retry_after_seconds: error.retryAfterSeconds ?? null,
				request_id: requestId
			},
			error.status
		);
	}

	log("error", "unhandled_error", requestId, { message: error.message });
	return c.json(
		{
			code: "internal_error",
			message: "The relay encountered an unexpected error.",
			request_id: requestId
		},
		500
	);
});

Deno.serve((request) => app.fetch(rewriteForRelayBasePath(request)));

async function authGuard(
	c: Parameters<Parameters<typeof app.use>[1]>[0],
	next: Parameters<Parameters<typeof app.use>[1]>[1]
) {
	const token = parseBearerToken(c.req.header("authorization"));
	if (!token) {
		throw new ApiError(401, "unauthorized", "A Supabase access token is required.");
	}

	const admin = createAdminClient();
	const { data, error } = await admin.auth.getUser(token);
	if (error || !data.user) {
		throw new ApiError(401, "unauthorized", "The Supabase access token is invalid or expired.");
	}

	const entitlement = await ensureEntitlement(admin, data.user.id);
	if (!entitlement.managed_enabled) {
		throw new ApiError(403, "managed_disabled", "Managed mode is disabled for this account.");
	}

	c.set("admin", admin);
	c.set("user", data.user);
	c.set("entitlement", entitlement);

	log("info", "authenticated_request", c.get("requestId"), {
		userId: data.user.id,
		path: c.req.path
	});

	await next();
}

function rewriteForRelayBasePath(request: Request): Request {
	const url = new URL(request.url);
	const marker = "/v1";
	const markerIndex = url.pathname.lastIndexOf(marker);

	if (markerIndex >= 0) {
		url.pathname = url.pathname.slice(markerIndex + marker.length) || "/";
	}

	return new Request(url, request);
}

function parseBearerToken(value: string | undefined): string | null {
	if (!value) return null;

	const [scheme, token] = value.trim().split(/\s+/, 2);
	if (scheme?.toLowerCase() !== "bearer" || !token) {
		return null;
	}

	return token;
}

function parseAudioDurationSeconds(value: string | undefined): number {
	if (!value) {
		throw new ApiError(
			400,
			"missing_audio_duration",
			"The transcription request requires X-AirType-Audio-Duration-Seconds."
		);
	}

	const parsed = Number.parseInt(value, 10);
	if (!Number.isFinite(parsed) || parsed <= 0) {
		throw new ApiError(
			400,
			"invalid_audio_duration",
			"X-AirType-Audio-Duration-Seconds must be a positive integer."
		);
	}

	return parsed;
}

function readFormDataString(formData: FormData, key: string): string | null {
	const value = formData.get(key);
	return typeof value === "string" && value.trim() ? value.trim() : null;
}

function createAdminClient(): SupabaseClient {
	const supabaseUrl = requireEnv("SUPABASE_URL");
	const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

	return createClient(supabaseUrl, serviceRoleKey, {
		auth: {
			autoRefreshToken: false,
			persistSession: false
		}
	});
}

async function ensureEntitlement(
	admin: SupabaseClient,
	userId: string
): Promise<ManagedEntitlement> {
	const { data, error } = await admin
		.from("user_entitlements")
		.upsert({ user_id: userId }, { onConflict: "user_id" })
		.select("*")
		.single();

	if (error || !data) {
		throw new ApiError(500, "entitlement_error", "The relay could not resolve user entitlements.");
	}

	return data as ManagedEntitlement;
}

async function getUsageSummary(admin: SupabaseClient, userId: string): Promise<UsageSummary> {
	const { data, error } = await admin.rpc("get_managed_usage_summary", {
		p_user_id: userId
	});

	if (error || !data || !Array.isArray(data) || !data[0]) {
		throw new ApiError(500, "usage_summary_error", "The relay could not load quota usage.");
	}

	return data[0] as UsageSummary;
}

async function checkAndRecordUsage(
	admin: SupabaseClient,
	args: {
		userId: string;
		requestId: string;
		routeKind: RouteKind;
		audioSeconds: number;
	}
): Promise<UsageCheckResult> {
	const { data, error } = await admin.rpc("check_and_record_managed_usage", {
		p_user_id: args.userId,
		p_request_id: args.requestId,
		p_route_kind: args.routeKind,
		p_request_units: 1,
		p_audio_seconds: args.audioSeconds,
		p_provider: PROVIDER
	});

	if (error || !data || !Array.isArray(data) || !data[0]) {
		throw new ApiError(500, "quota_error", "The relay could not evaluate the current quota.");
	}

	const result = data[0] as UsageCheckResult;

	if (!result.allowed) {
		throw new ApiError(
			429,
			result.reason === "audio_limit_exceeded" ? "audio_quota_exceeded" : "rate_limited",
			result.reason === "audio_limit_exceeded"
				? "This account has exhausted its daily managed audio quota."
				: "This account has hit its managed request rate limit.",
			result.retry_after_seconds ?? undefined
		);
	}

	return result;
}

async function relayToOpenAI(args: {
	requestId: string;
	admin: SupabaseClient;
	usageEventId: string | null;
	path: string;
	method: "POST";
	body: BodyInit;
	headers?: HeadersInit;
}): Promise<Response> {
	const openAIURL = buildUpstreamURL(args.path);
	const openAIKey = requireEnv("OPENAI_API_KEY");
	const headers = new Headers(args.headers);
	headers.set("authorization", `Bearer ${openAIKey}`);

	let upstreamStatus = 502;

	try {
		log("info", "relay_upstream_start", args.requestId, {
			path: args.path,
			provider: PROVIDER
		});

		const upstreamResponse = await fetch(openAIURL, {
			method: args.method,
			headers,
			body: args.body
		});
		upstreamStatus = upstreamResponse.status;

		if (args.usageEventId) {
			await markUsageEventStatus(args.admin, args.usageEventId, upstreamStatus);
		}

		if (!upstreamResponse.ok) {
			const message = await readUpstreamErrorMessage(upstreamResponse);
			throw new ApiError(upstreamStatus, "upstream_error", message);
		}

		const responseHeaders = new Headers();
		const contentType = upstreamResponse.headers.get("content-type");
		if (contentType) {
			responseHeaders.set("content-type", contentType);
		}
		responseHeaders.set("x-request-id", args.requestId);

		return new Response(await upstreamResponse.arrayBuffer(), {
			status: upstreamStatus,
			headers: responseHeaders
		});
	} catch (error) {
		if (args.usageEventId) {
			await markUsageEventStatus(args.admin, args.usageEventId, upstreamStatus);
		}

		if (error instanceof ApiError) {
			throw error;
		}

		throw new ApiError(
			502,
			"upstream_unreachable",
			"The relay could not reach the upstream provider."
		);
	}
}

async function markUsageEventStatus(
	admin: SupabaseClient,
	usageEventId: string,
	upstreamStatus: number
) {
	await admin.from("usage_events").update({ upstream_status: upstreamStatus }).eq("id", usageEventId);
}

async function readUpstreamErrorMessage(response: Response): Promise<string> {
	const contentType = response.headers.get("content-type") ?? "";
	if (contentType.includes("application/json")) {
		const payload = (await response.json().catch(() => null)) as
			| { error?: { message?: string }; message?: string }
			| null;

		const message = payload?.error?.message ?? payload?.message;
		if (message?.trim()) {
			return message.trim();
		}
	}

	const rawText = await response.text().catch(() => "");
	if (rawText.trim()) {
		return rawText.trim();
	}

	return "The upstream provider returned an error.";
}

function buildUpstreamURL(path: string): string {
	const baseURL = (Deno.env.get("OPENAI_BASE_URL") || "https://api.openai.com/v1").trim();
	const normalizedBaseURL = baseURL.endsWith("/") ? baseURL : `${baseURL}/`;
	const sanitizedPath = path.startsWith("/") ? path.slice(1) : path;

	return new URL(sanitizedPath, normalizedBaseURL).toString();
}

function requireEnv(name: string): string {
	const value = Deno.env.get(name)?.trim();
	if (!value) {
		throw new ApiError(
			500,
			"backend_misconfigured",
			`The relay is missing required environment variable ${name}.`
		);
	}

	return value;
}

function log(
	level: "info" | "warn" | "error",
	event: string,
	requestId: string,
	metadata: Record<string, unknown> = {}
) {
	const payload = {
		level,
		event,
		request_id: requestId,
		timestamp: new Date().toISOString(),
		...metadata
	};

	console[level](JSON.stringify(payload));
}
