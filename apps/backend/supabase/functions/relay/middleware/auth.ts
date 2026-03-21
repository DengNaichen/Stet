import { Context, Next } from "hono";
import { HonoVariables } from "../type.ts";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { ApiError } from "../error.ts";
import { log } from "../log.ts";
import { requireEnv } from "../utils.ts";
import type { RelayBillingBackend } from "../billing_backend.ts";

export function createAuthGuard(billingBackend: RelayBillingBackend) {
  return async (
    c: Context<{ Variables: HonoVariables }>,
    next: Next,
  ) => {
    const authHeader = c.req.header("authorization");
    const token = parseBearerToken(authHeader);
    if (!token) {
      throw new ApiError(
        401,
        "unauthorized",
        "A supabase access token is required",
      );
    }

    const admin = createAdminClient();
    let data;
    let error;
    try {
      ({ data, error } = await admin.auth.getUser(token));
    } catch (authLookupError) {
      log("error", "auth_lookup_failed", c.get("requestId"), {
        path: c.req.path,
        message: authLookupError instanceof Error
          ? authLookupError.message
          : String(authLookupError),
      });
      throw new ApiError(
        500,
        "auth_lookup_failed",
        "The relay could not validate the Supabase session.",
      );
    }

    if (error || !data.user) {
      throw new ApiError(
        401,
        "unauthorized",
        "The Supabase access token is invalid or expired.",
      );
    }

    let relayAccount;
    try {
      relayAccount = await billingBackend.resolveAccount(admin, data.user.id);
    } catch (relayAccountError) {
      if (relayAccountError instanceof ApiError) {
        throw relayAccountError;
      }

      log("error", "relay_account_lookup_failed", c.get("requestId"), {
        userId: data.user.id,
        billingBackend: billingBackend.kind,
        message: relayAccountError instanceof Error
          ? relayAccountError.message
          : String(relayAccountError),
      });
      throw new ApiError(
        500,
        "relay_account_lookup_failed",
        "The relay could not resolve managed account details.",
      );
    }

    if (!relayAccount.managed_enabled) {
      throw new ApiError(
        403,
        "managed_disabled",
        "Managed mode is disabled for this account.",
      );
    }

    c.set("admin", admin);
    c.set("user", data.user);
    c.set("relayAccount", relayAccount);

    log("info", "authenticated_request", c.get("requestId"), {
      userId: data.user.id,
      path: c.req.path,
      billingBackend: billingBackend.kind,
    });

    await next();
  };
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
      persistSession: false,
    },
  });
}
