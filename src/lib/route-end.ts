export type MissedStopInput = {
  id: string;
  label: string;
  lat: number;
  lng: number;
};

export type MissedPickupReportInsert = {
  report_type: "missed_pickup";
  lat: number;
  lng: number;
  zone_id: string | null;
  description: string;
  waste_type: "unknown";
  status: "pending";
  reporter_id: string | null;
};

export function buildMissedPickupReports(opts: {
  zoneId: string | null;
  reporterId: string | null;
  stops: MissedStopInput[];
}): MissedPickupReportInsert[] {
  return opts.stops.map((stop) => ({
    report_type: "missed_pickup",
    lat: stop.lat,
    lng: stop.lng,
    zone_id: opts.zoneId,
    description: `Missed pickup: ${stop.label} (route end)`,
    waste_type: "unknown",
    status: "pending",
    reporter_id: opts.reporterId,
  }));
}

export function computeRouteEndStatus(missedStops: number): "completed" | "completed_with_issues" {
  return missedStops > 0 ? "completed_with_issues" : "completed";
}
