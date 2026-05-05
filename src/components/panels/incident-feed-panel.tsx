import type { IncidentItem } from "@/components/layout/dashboard-mock-data";

type Props = {
  incidents: IncidentItem[];
};

const severityTone: Record<IncidentItem["severity"], string> = {
  low: "text-emerald-700 bg-emerald-50",
  medium: "text-amber-700 bg-amber-50",
  high: "text-red-700 bg-red-50",
};

export function IncidentFeedPanel({ incidents }: Props) {
  return (
    <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-800">Live Incident Feed</h2>
      {incidents.length === 0 ? (
        <p className="rounded-xl border border-dashed border-zinc-200 p-3 text-sm text-zinc-500">
          No live incidents yet.
        </p>
      ) : null}
      <ul className="space-y-3">
        {incidents.map((incident) => (
          <li key={incident.id} className="rounded-xl border border-zinc-100 p-3">
            <div className="flex items-center justify-between gap-2">
              <p className="text-sm font-medium text-zinc-900">{incident.title}</p>
              <span className={`rounded px-2 py-0.5 text-[11px] font-medium ${severityTone[incident.severity]}`}>
                {incident.severity}
              </span>
            </div>
            <p className="mt-1 text-xs text-zinc-600">{incident.locationLabel}</p>
            <div className="mt-2 flex items-center justify-between text-[11px] uppercase tracking-wide text-zinc-500">
              <span>{incident.type.replace("_", " ")}</span>
              <span>{incident.createdAgo}</span>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}
