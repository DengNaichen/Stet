import type { RelayBillingBackend } from "./billing_backend.ts";
import { ManagedRelayBillingBackend } from "./managed_billing_backend.ts";
import { UnmeteredRelayBillingBackend } from "./unmetered_billing_backend.ts";

export function makeRelayBillingBackend(): RelayBillingBackend {
  const configured = Deno.env.get("RELAY_BILLING_BACKEND")?.trim()
    .toLowerCase();

  switch (configured) {
    case "unmetered":
      return new UnmeteredRelayBillingBackend();
    case "managed":
    case "":
    case undefined:
    default:
      return new ManagedRelayBillingBackend();
  }
}
