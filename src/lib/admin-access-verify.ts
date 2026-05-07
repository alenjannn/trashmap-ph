import { createClient } from "@supabase/supabase-js";

export type AdminAccessVerifyResult =
  | { ok: true }
  | { ok: false; status: number; message: string };

/**
 * Validates username/password against public.admin_access_secrets (anon client).
 * Same rules as POST /api/admin-auth.
 */
export async function verifyAdminAccessSecrets(
  supabaseUrl: string,
  supabaseAnonKey: string,
  username: string,
  password: string,
): Promise<AdminAccessVerifyResult> {
  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { data, error } = await supabase
    .from("admin_access_secrets")
    .select("password_plain, is_active")
    .eq("username", username)
    .maybeSingle();

  if (error) {
    return { ok: false, status: 500, message: "Unable to validate admin credentials." };
  }

  if (!data || !data.is_active) {
    return { ok: false, status: 401, message: "Admin authority is not confirmed." };
  }

  if (data.password_plain !== password) {
    return { ok: false, status: 401, message: "Invalid admin username or password." };
  }

  return { ok: true };
}
