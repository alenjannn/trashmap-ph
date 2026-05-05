"use client";

import dynamic from "next/dynamic";
import { createClient } from "@supabase/supabase-js";
import { useEffect, useMemo, useState } from "react";
import {
  type DashboardPin,
  fleetTrucks,
  incidentFeed,
} from "@/components/layout/dashboard-mock-data";
import { FleetStatusPanel } from "@/components/panels/fleet-status-panel";
import { IncidentFeedPanel } from "@/components/panels/incident-feed-panel";

const LGUMap = dynamic(() => import("@/components/map/lgu-map").then((mod) => mod.LGUMap), {
  ssr: false,
  loading: () => (
    <div className="flex h-full w-full items-center justify-center bg-zinc-50 text-sm text-zinc-500">
      Loading map shell...
    </div>
  ),
});

type ReportRow = {
  id: string;
  lat: number;
  lng: number;
  report_type: "dumpsite" | "missed_pickup";
  waste_type: "biodegradable" | "recyclable" | "special_hazardous" | "mixed" | "unknown";
  description: string | null;
};

export function DashboardShell() {
  const [pins, setPins] = useState<DashboardPin[]>([]);
  const [isLoadingPins, setIsLoadingPins] = useState(true);
  const [pinError, setPinError] = useState<string | null>(null);

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  const supabase = useMemo(() => {
    if (!supabaseUrl || !supabaseAnonKey) return null;
    return createClient(supabaseUrl, supabaseAnonKey);
  }, [supabaseAnonKey, supabaseUrl]);

  const configError = !supabase ? "Supabase environment is not configured." : null;

  useEffect(() => {
    if (!supabase) return;
    const client = supabase;

    function mapReportToPin(report: ReportRow): DashboardPin {
      return {
        id: report.id,
        lat: report.lat,
        lng: report.lng,
        type: report.report_type,
        label: report.description?.trim() || "Citizen report",
        wasteType: report.waste_type,
      };
    }

    async function loadReports() {
      setIsLoadingPins(true);
      const { data, error } = await client
        .from("reports")
        .select("id, lat, lng, report_type, waste_type, description")
        .order("created_at", { ascending: false })
        .limit(250);

      if (error) {
        setPinError("Failed to load live report pins.");
        setIsLoadingPins(false);
        return;
      }

      setPins((data ?? []).map((row) => mapReportToPin(row as ReportRow)));
      setPinError(null);
      setIsLoadingPins(false);
    }

    void loadReports();

    const channel = client
      .channel("dashboard-reports-live")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "reports" },
        () => {
          void loadReports();
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [supabase]);

  return (
    <div className="min-h-screen bg-zinc-100">
      <header className="border-b border-emerald-100 bg-white">
        <div className="mx-auto flex max-w-[1400px] items-center justify-between px-6 py-4">
          <div>
            <p className="text-xs uppercase tracking-[0.2em] text-emerald-800">TrashMap PH</p>
            <h1 className="text-xl font-semibold text-zinc-900">LGU Live Operations Dashboard</h1>
          </div>
          <div className="rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-800">
            Day 1 Static Shell
          </div>
        </div>
      </header>

      <main className="mx-auto grid max-w-[1400px] grid-cols-1 gap-4 px-6 py-6 lg:grid-cols-[minmax(0,1fr)_380px]">
        <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-800">Map Overview</h2>
            <div className="flex items-center gap-3 text-xs text-zinc-600">
              <span className="inline-flex items-center gap-1">
                <span className="h-2.5 w-2.5 rounded-full bg-amber-500" />
                Dumpsite
              </span>
              <span className="inline-flex items-center gap-1">
                <span className="h-2.5 w-2.5 rounded-full bg-blue-500" />
                Missed Pickup
              </span>
              <span className="inline-flex items-center gap-1">
                <span className="h-2.5 w-2.5 rounded-full bg-red-500" />
                Hotspot
              </span>
            </div>
          </div>
          <div className="h-[560px] overflow-hidden rounded-xl border border-zinc-200">
            {pinError ? (
              <div className="flex h-full items-center justify-center px-4 text-center text-sm text-red-700">
                {pinError}
              </div>
            ) : configError ? (
              <div className="flex h-full items-center justify-center px-4 text-center text-sm text-red-700">
                {configError}
              </div>
            ) : isLoadingPins ? (
              <div className="flex h-full items-center justify-center text-sm text-zinc-500">
                Loading live report pins...
              </div>
            ) : (
              <LGUMap pins={pins} />
            )}
          </div>
        </section>

        <aside className="space-y-4">
          <FleetStatusPanel trucks={fleetTrucks} />
          <IncidentFeedPanel incidents={incidentFeed} />
        </aside>
      </main>
    </div>
  );
}
