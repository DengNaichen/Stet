import { ApiError } from "./error.ts";

export function requireEnv(name: string): string {
    const value = Deno.env.get(name)?.trim();
    if (!value) {
        throw new ApiError(
            500,
            "backend_misconfigured",
            `The relay is missing required environment variable ${name}.`
        )
    }
    return value;
}