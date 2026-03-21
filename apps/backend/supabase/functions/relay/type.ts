import { SupabaseClient, User } from "@supabase/supabase-js";
import type { RelayAccount } from "./billing_backend.ts";

export type HonoVariables = {
  requestId: string;
  admin: SupabaseClient;
  user: User;
  relayAccount: RelayAccount;
};
