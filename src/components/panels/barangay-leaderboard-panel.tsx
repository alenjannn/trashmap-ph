import type { BarangayLeaderboardItem } from "@/components/layout/dashboard-mock-data";

type Props = {
  items: BarangayLeaderboardItem[];
};

export function BarangayLeaderboardPanel({ items }: Props) {
  return (
    <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-800">Barangay Leaderboard</h2>
      {items.length === 0 ? (
        <p className="rounded-xl border border-dashed border-zinc-200 p-3 text-sm text-zinc-500">
          No barangay report data yet.
        </p>
      ) : (
        <ul className="space-y-2">
          {items.map((item, index) => (
            <li key={item.id} className="flex items-center justify-between rounded-xl border border-zinc-100 px-3 py-2">
              <div className="flex items-center gap-2">
                <span className="inline-flex h-5 w-5 items-center justify-center rounded-full bg-zinc-100 text-[11px] font-semibold text-zinc-700">
                  {index + 1}
                </span>
                <p className="text-sm font-medium text-zinc-900">{item.name}</p>
              </div>
              <span className="text-xs font-semibold uppercase tracking-wide text-zinc-600">{item.reportCount} reports</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
