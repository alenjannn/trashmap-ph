"use client";

import { useEffect, useMemo, useState } from "react";
import { DashboardShell } from "@/components/layout/dashboard-shell";
import { getBrowserSupabaseClient } from "@/lib/supabase-browser";

const SESSION_KEY = "tm_admin_session";

type AdminSession = {
  username: string;
  authorityConfirmed: boolean;
};

function readSession(): AdminSession | null {
  if (typeof window === "undefined") return null;
  const raw = window.sessionStorage.getItem(SESSION_KEY);
  if (!raw) return null;

  try {
    const parsed = JSON.parse(raw) as AdminSession;
    if (!parsed.username || !parsed.authorityConfirmed) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function AdminLoginGate() {
  const [session, setSession] = useState<AdminSession | null>(() => readSession());
  const [authBootstrapDone, setAuthBootstrapDone] = useState(() => readSession() === null);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isAuthed = useMemo(() => Boolean(session?.authorityConfirmed), [session]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const stored = readSession();
      if (!stored) {
        setAuthBootstrapDone(true);
        return;
      }

      const supabase = getBrowserSupabaseClient();
      if (!supabase) {
        setAuthBootstrapDone(true);
        return;
      }

      void supabase.auth.getSession().then(({ data: { session: s } }) => {
        if (!s) {
          window.sessionStorage.removeItem(SESSION_KEY);
          setSession(null);
          setError("Database session expired. Sign in again.");
          setAuthBootstrapDone(true);
          return;
        }
        void supabase.auth.refreshSession().finally(() => {
          setAuthBootstrapDone(true);
        });
      });
    }, 0);

    return () => window.clearTimeout(timer);
  }, []);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSubmitting(true);
    setError(null);

    try {
      const response = await fetch("/api/admin-auth", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      const payload = (await response.json()) as {
        ok: boolean;
        message?: string;
        admin?: AdminSession;
      };

      if (!response.ok || !payload.ok || !payload.admin) {
        setError(payload.message ?? "Unable to authenticate.");
        return;
      }

      const sessionRes = await fetch("/api/admin-supabase-session", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password }),
      });
      const sessionPayload = (await sessionRes.json()) as {
        ok?: boolean;
        message?: string;
        access_token?: string;
        refresh_token?: string;
      };

      if (!sessionRes.ok || !sessionPayload.ok || !sessionPayload.access_token || !sessionPayload.refresh_token) {
        setError(sessionPayload.message ?? "Unable to establish database session.");
        return;
      }

      const supabase = getBrowserSupabaseClient();
      if (!supabase) {
        setError("Supabase client is not available.");
        return;
      }

      const { error: setSessionError } = await supabase.auth.setSession({
        access_token: sessionPayload.access_token,
        refresh_token: sessionPayload.refresh_token,
      });

      if (setSessionError) {
        setError(setSessionError.message);
        return;
      }

      window.sessionStorage.setItem(SESSION_KEY, JSON.stringify(payload.admin));
      setSession(payload.admin);
      setUsername("");
      setPassword("");
    } catch {
      setError("Network error while verifying admin authority.");
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleLogout() {
    const supabase = getBrowserSupabaseClient();
    if (supabase) {
      await supabase.auth.signOut();
    }
    window.sessionStorage.removeItem(SESSION_KEY);
    setSession(null);
  }

  if (!authBootstrapDone) {
    return (
      <main className="flex min-h-screen items-center justify-center bg-zinc-100 px-4">
        <p className="text-sm text-zinc-600">Restoring session…</p>
      </main>
    );
  }

  if (isAuthed) {
    return (
      <div className="relative">
        <div className="absolute right-4 top-4 z-[1000] rounded-full border border-zinc-200 bg-white/95 px-3 py-1.5 text-xs text-zinc-700 shadow-sm">
          <span className="mr-2">Admin: {session?.username}</span>
          <button
            type="button"
            onClick={() => void handleLogout()}
            className="cursor-pointer font-semibold text-emerald-700 hover:text-emerald-800"
          >
            Logout
          </button>
        </div>
        <DashboardShell />
      </div>
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-zinc-100 px-4">
      <section className="w-full max-w-md rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
        <p className="text-xs font-semibold uppercase tracking-[0.2em] text-emerald-700">TrashMap PH</p>
        <h1 className="mt-2 text-2xl font-semibold text-zinc-900">LGU Admin Sign In</h1>
        <p className="mt-2 text-sm text-zinc-600">
          Authorized admins only. Demo gate credentials: <code className="rounded bg-zinc-100 px-1 py-0.5 text-xs font-medium text-zinc-800">admin123</code> / <code className="rounded bg-zinc-100 px-1 py-0.5 text-xs font-medium text-zinc-800">admin123</code>.
        </p>

        <form onSubmit={handleSubmit} className="mt-5 space-y-4">
          <label className="block space-y-1">
            <span className="text-sm font-medium text-zinc-800">Username</span>
            <input
              className="w-full rounded-xl border border-zinc-300 px-3 py-2 text-sm outline-none ring-emerald-300 focus:ring"
              value={username}
              onChange={(event) => setUsername(event.target.value)}
              placeholder="admin123"
              autoComplete="username"
            />
          </label>

          <label className="block space-y-1">
            <span className="text-sm font-medium text-zinc-800">Password</span>
            <input
              className="w-full rounded-xl border border-zinc-300 px-3 py-2 text-sm outline-none ring-emerald-300 focus:ring"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              placeholder="admin123"
              type="password"
              autoComplete="current-password"
            />
          </label>

          {error ? (
            <p className="rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>
          ) : null}

          <button
            type="submit"
            disabled={isSubmitting}
            className="w-full cursor-pointer rounded-xl bg-emerald-700 px-3 py-2 text-sm font-semibold text-white transition hover:bg-emerald-800 disabled:cursor-not-allowed disabled:opacity-70"
          >
            {isSubmitting ? "Verifying..." : "Sign In as Admin"}
          </button>
        </form>
      </section>
    </main>
  );
}
