"use client";

import dynamic from "next/dynamic";
import { dashboardPins, fleetTrucks, incidentFeed } from "@/components/layout/dashboard-mock-data";
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

export function DashboardShell() {
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
            <LGUMap pins={dashboardPins} />
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
