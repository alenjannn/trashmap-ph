import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { verifyAdminAccessSecrets } from "@/lib/admin-access-verify";

type Body = {
  username?: string;
  password?: string;
};

/**
 * After LGU gate passes, mint Supabase Auth session for seeded LGU admin user
 * so browser client uses JWT (authenticated) and RLS allows fleet reads/writes.
 */
export async function POST(request: Request) {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const lguEmail = process.env.LGU_SUPABASE_AUTH_EMAIL?.trim();
  const lguPassword = process.env.LGU_SUPABASE_AUTH_PASSWORD;

  if (!supabaseUrl || !supabaseAnonKey) {
    return NextResponse.json(
      { ok: false, message: "Supabase environment is not configured." },
      { status: 500 },
    );
  }

  if (!lguEmail || lguPassword === undefined || lguPassword === "") {
    return NextResponse.json(
      {
        ok: false,
        message:
          "LGU database session not configured. Set LGU_SUPABASE_AUTH_EMAIL and LGU_SUPABASE_AUTH_PASSWORD.",
      },
      { status: 503 },
    );
  }

  const body = (await request.json()) as Body;
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

  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { data, error } = await supabase.auth.signInWithPassword({
    email: lguEmail,
    password: lguPassword,
  });

  if (error || !data.session) {
    return NextResponse.json(
      { ok: false, message: error?.message ?? "Unable to establish database session." },
      { status: 401 },
    );
  }

  return NextResponse.json({
    ok: true,
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    expires_at: data.session.expires_at,
  });
}
