import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

type LoginBody = {
  username?: string;
  password?: string;
};

export async function POST(request: Request) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!supabaseUrl || !supabaseAnonKey) {
    return NextResponse.json(
      { ok: false, message: "Supabase environment is not configured." },
      { status: 500 },
    );
  }

  const body = (await request.json()) as LoginBody;
  const username = body.username?.trim();
  const password = body.password?.trim();

  if (!username || !password) {
    return NextResponse.json(
      { ok: false, message: "Username and password are required." },
      { status: 400 },
    );
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { data, error } = await supabase
    .from("admin_access_secrets")
    .select("username, password_plain, is_active")
    .eq("username", username)
    .maybeSingle();

  if (error) {
    return NextResponse.json(
      { ok: false, message: "Unable to validate admin credentials." },
      { status: 500 },
    );
  }

  if (!data || !data.is_active) {
    return NextResponse.json(
      { ok: false, message: "Admin authority is not confirmed." },
      { status: 401 },
    );
  }

  if (data.password_plain !== password) {
    return NextResponse.json(
      { ok: false, message: "Invalid admin username or password." },
      { status: 401 },
    );
  }

  return NextResponse.json({
    ok: true,
    message: "Admin login successful.",
    admin: { username: data.username, authorityConfirmed: data.is_active },
  });
}
