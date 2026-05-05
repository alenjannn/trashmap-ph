"use client";

import dynamic from "next/dynamic";
import { useEffect, useMemo, useState } from "react";
import {
  type DashboardPin,
  type FleetTruck,
  type IncidentItem,
} from "@/components/layout/dashboard-mock-data";
import { getBrowserSupabaseClient } from "@/lib/supabase-browser";
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
  created_at: string;
  lat: number;
  lng: number;
  report_type: "dumpsite" | "missed_pickup";
  waste_type: "biodegradable" | "recyclable" | "special_hazardous" | "mixed" | "unknown";
  description: string | null;
};

type TruckRow = {
  id: string;
  truck_code: string;
  driver_name: string | null;
  status: "idle" | "en_route" | "collecting" | "maintenance" | "offline";
};

type HotspotRow = {
  id: string;
  center_lat: number;
  center_lng: number;
  severity: "low" | "medium" | "high" | "critical";
  unique_reporters_count: number;
  radius_meters: number;
  status: "active" | "cleared";
};

function formatCreatedAgo(createdAt: string): string {
  const now = Date.now();
  const created = new Date(createdAt).getTime();
  const diffMinutes = Math.max(1, Math.floor((now - created) / 60000));
  if (diffMinutes < 60) return `${diffMinutes}m`;
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours}h`;
  return `${Math.floor(diffHours / 24)}d`;
}

export function DashboardShell() {
  const [reportPins, setReportPins] = useState<DashboardPin[]>([]);
  const [hotspotPins, setHotspotPins] = useState<DashboardPin[]>([]);
  const [fleet, setFleet] = useState<FleetTruck[]>([]);
  const [incidents, setIncidents] = useState<IncidentItem[]>([]);
  const [isLoadingPins, setIsLoadingPins] = useState(true);
  const [pinError, setPinError] = useState<string | null>(null);

  const supabase = getBrowserSupabaseClient();
  const pins = useMemo(() => [...reportPins, ...hotspotPins], [hotspotPins, reportPins]);

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

    function mapReportToIncident(report: ReportRow): IncidentItem {
      const type = report.report_type;
      return {
        id: report.id,
        type,
        title: report.description?.trim() || "Citizen report submitted",
        locationLabel: `${report.lat.toFixed(5)}, ${report.lng.toFixed(5)}`,
        createdAgo: formatCreatedAgo(report.created_at),
        severity: type === "missed_pickup" ? "medium" : "high",
      };
    }

    function mapHotspotToPin(row: HotspotRow): DashboardPin {
      return {
        id: `hotspot-${row.id}`,
        lat: row.center_lat,
        lng: row.center_lng,
        type: "hotspot",
        label: `${row.severity.toUpperCase()} hotspot (${row.unique_reporters_count} reporters, ${row.radius_meters}m)`,
        wasteType: "unknown",
        radiusMeters: row.radius_meters,
      };
    }

    function mapTruckToFleet(row: TruckRow): FleetTruck {
      const status =
        row.status === "offline" ? "idle" : (row.status as FleetTruck["status"]);
      return {
        id: row.id,
        code: row.truck_code,
        driver: row.driver_name ?? "Unassigned",
        status,
        progressPercent: 0,
        lastSeen: "live",
      };
    }

    async function loadReports() {
      setIsLoadingPins(true);
      const { data, error } = await client
        .from("reports")
        .select("id, created_at, lat, lng, report_type, waste_type, description")
        .order("created_at", { ascending: false })
        .limit(250);

      if (error) {
        setPinError("Failed to load live report pins.");
        setIsLoadingPins(false);
        return;
      }

      const mappedRows = (data ?? []).map((row) => row as ReportRow);
      setReportPins(mappedRows.map((row) => mapReportToPin(row)));
      setIncidents(mappedRows.slice(0, 12).map((row) => mapReportToIncident(row)));
      setPinError(null);
      setIsLoadingPins(false);
    }

    async function loadHotspots() {
      const { data, error } = await client
        .from("hotspots")
        .select("id, center_lat, center_lng, severity, unique_reporters_count, radius_meters, status")
        .eq("status", "active")
        .order("updated_at", { ascending: false })
        .limit(200);
      if (error) return;
      const rows = (data ?? []).map((row) => row as HotspotRow);
      setHotspotPins(rows.map((row) => mapHotspotToPin(row)));
    }

    async function loadFleet() {
      const { data, error } = await client
        .from("trucks")
        .select("id, truck_code, driver_name, status")
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) return;
      const rows = (data ?? []).map((row) => row as TruckRow);
      setFleet(rows.map((row) => mapTruckToFleet(row)));
    }

    void loadReports();
    void loadHotspots();
    void loadFleet();

    const reportsChannel = client
      .channel("dashboard-reports-live-v2")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "reports" },
        () => {
          void loadReports();
        },
      )
      .subscribe();

    const trucksChannel = client
      .channel("dashboard-trucks-live-v2")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "trucks" },
        () => {
          void loadFleet();
        },
      )
      .subscribe();

    const hotspotsChannel = client
      .channel("dashboard-hotspots-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "hotspots" },
        () => {
          void loadHotspots();
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(reportsChannel);
      void client.removeChannel(trucksChannel);
      void client.removeChannel(hotspotsChannel);
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
            Live Data Mode
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
          <FleetStatusPanel trucks={fleet} />
          <IncidentFeedPanel incidents={incidents} />
        </aside>
      </main>
    </div>
  );
}
