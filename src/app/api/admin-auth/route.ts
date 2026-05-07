import { NextResponse } from "next/server";
import { verifyAdminAccessSecrets } from "@/lib/admin-access-verify";

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

  const gate = await verifyAdminAccessSecrets(supabaseUrl, supabaseAnonKey, username, password);
  if (!gate.ok) {
    return NextResponse.json({ ok: false, message: gate.message }, { status: gate.status });
  }

  return NextResponse.json({
    ok: true,
    message: "Admin login successful.",
    admin: { username, authorityConfirmed: true },
  });
}
