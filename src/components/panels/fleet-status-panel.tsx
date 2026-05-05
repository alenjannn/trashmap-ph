import type { FleetTruck } from "@/components/layout/dashboard-mock-data";

type Props = {
  trucks: FleetTruck[];
};

const statusColor: Record<FleetTruck["status"], string> = {
  idle: "bg-zinc-400",
  en_route: "bg-blue-500",
  collecting: "bg-emerald-500",
  maintenance: "bg-amber-500",
};

export function FleetStatusPanel({ trucks }: Props) {
  return (
    <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-800">Fleet Status</h2>
        <span className="rounded-full bg-zinc-100 px-2 py-1 text-xs text-zinc-600">{trucks.length} trucks</span>
      </div>

      <ul className="space-y-3">
        {trucks.map((truck) => (
          <li key={truck.id} className="rounded-xl border border-zinc-100 p-3">
            <div className="mb-2 flex items-center justify-between">
              <p className="text-sm font-semibold text-zinc-900">{truck.code}</p>
              <span className="text-xs text-zinc-500">{truck.lastSeen}</span>
            </div>
            <p className="text-xs text-zinc-600">Driver: {truck.driver}</p>
            <div className="mt-2 flex items-center gap-2">
              <span className={`h-2.5 w-2.5 rounded-full ${statusColor[truck.status]}`} />
              <p className="text-xs capitalize text-zinc-700">{truck.status.replace("_", " ")}</p>
            </div>
            <div className="mt-2 h-2 w-full rounded-full bg-zinc-100">
              <div
                className="h-2 rounded-full bg-emerald-500 transition-all"
                style={{ width: `${truck.progressPercent}%` }}
              />
            </div>
            <p className="mt-1 text-right text-[11px] text-zinc-500">{truck.progressPercent}% route complete</p>
          </li>
        ))}
      </ul>
    </section>
  );
}
