import type { RiskZoneItem } from "@/components/layout/dashboard-mock-data";

type Props = {
  zones: RiskZoneItem[];
};

const levelTone: Record<RiskZoneItem["level"], string> = {
  low: "text-emerald-700 bg-emerald-50",
  medium: "text-amber-700 bg-amber-50",
  high: "text-orange-700 bg-orange-50",
  critical: "text-red-700 bg-red-50",
};

export function RiskZonesPanel({ zones }: Props) {
  return (
    <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-800">Risk Zones</h2>
      {zones.length === 0 ? (
        <p className="rounded-xl border border-dashed border-zinc-200 p-3 text-sm text-zinc-500">
          No risk zones available yet.
        </p>
      ) : (
        <ul className="space-y-2">
          {zones.map((zone) => (
            <li key={zone.id} className="rounded-xl border border-zinc-100 p-3">
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-medium text-zinc-900">{zone.name}</p>
                <span className={`rounded px-2 py-0.5 text-[11px] font-medium uppercase ${levelTone[zone.level]}`}>
                  {zone.level}
                </span>
              </div>
              <p className="mt-1 text-xs text-zinc-600">Score: {(zone.score * 100).toFixed(1)}%</p>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
