type FuelSavingsStats = {
  routeCount: number;
  optimizedDistanceKm: number;
  baselineDistanceKm: number;
  optimizedFuelLiters: number;
  baselineFuelLiters: number;
  dieselPricePerLiter: number;
  pesoSavings: number;
};

type Props = {
  stats: FuelSavingsStats;
};

function formatNumber(value: number, fractionDigits = 2): string {
  return new Intl.NumberFormat("en-PH", {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(value);
}

export function FuelSavingsPanel({ stats }: Props) {
  return (
    <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
      <div className="mb-3 flex items-center justify-between">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-800">Fuel Savings</h2>
        <span className="rounded-full bg-emerald-100 px-2 py-1 text-xs font-semibold text-emerald-700">
          {stats.routeCount} routes
        </span>
      </div>

      <div className="rounded-xl border border-zinc-100 bg-zinc-50 p-3">
        <p className="text-xs uppercase tracking-wide text-zinc-500">Estimated Savings</p>
        <p className="mt-1 text-2xl font-bold text-emerald-700">PHP {formatNumber(stats.pesoSavings)}</p>
        <p className="mt-1 text-xs text-zinc-600">
          Diesel rate: PHP {formatNumber(stats.dieselPricePerLiter)} / L
        </p>
      </div>

      <div className="mt-3 space-y-2 text-xs text-zinc-700">
        <div className="flex items-center justify-between">
          <span>Optimized distance</span>
          <span className="font-semibold">{formatNumber(stats.optimizedDistanceKm)} km</span>
        </div>
        <div className="flex items-center justify-between">
          <span>Baseline distance</span>
          <span className="font-semibold">{formatNumber(stats.baselineDistanceKm)} km</span>
        </div>
        <div className="flex items-center justify-between">
          <span>Optimized fuel use</span>
          <span className="font-semibold">{formatNumber(stats.optimizedFuelLiters)} L</span>
        </div>
        <div className="flex items-center justify-between">
          <span>Baseline fuel use</span>
          <span className="font-semibold">{formatNumber(stats.baselineFuelLiters)} L</span>
        </div>
      </div>
    </section>
  );
}
