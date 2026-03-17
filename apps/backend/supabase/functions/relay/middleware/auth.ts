import { Context, Next } from "hono"
import { HonoVariables, ManagedEntitlement } from "../type.ts"
import { createClient, type SupabaseClient } from "@supabase/supabase-js"
import { ApiError } from "../error.ts";
import { log } from "../log.ts";
import { requireEnv } from "../utils.ts";

export const authGuard = async (
    c: Context<{ Variables: HonoVariables }>,
    next: Next) => {
    const authHeader = c.req.header("authorization");
    const token = parseBearerToken(authHeader);
    if (!token) {
        throw new ApiError(401, "unauthorized", "A supabase access token is required");
    }
    const admin = createAdminClient();
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data.user) {
        throw new ApiError(401, "unauthorized", "The Supabase access token is invalid or expired.")
    }
    const entitlement = await ensureEntitlement(admin, data.user.id);
    if (!entitlement.managed_enabled) {
        throw new ApiError(403, "managed_disabled", "Managed mode is disabled for this account.");
    }

    c.set("admin", admin);
    c.set("user", data.user);
    c.set("entitlement", entitlement)

    log("info", "authenticated_request", c.get("requestId"), {
        userId: data.user.id,
        path: c.req.path
    });

    await next();
}

function parseBearerToken(value: string | undefined): string | null {
    if (!value) return null;

    const [scheme, token] = value.trim().split(/\s+/, 2);
    if (scheme?.toLowerCase() !== "bearer" || !token) {
        return null;
    }
    return token;
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
    return data as ManagedEntitlement
}





