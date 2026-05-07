import { describe, expect, it } from "vitest";
import { buildMissedPickupReports, computeRouteEndStatus } from "@/lib/route-end";

describe("route end missed-pickup integration", () => {
  it("builds one missed_pickup report per unresolved stop", () => {
    const reports = buildMissedPickupReports({
      zoneId: "zone-1",
      reporterId: "driver-1",
      stops: [
        { id: "s1", label: "Blk 1", lat: 14.6, lng: 121.0 },
        { id: "s2", label: "Blk 2", lat: 14.7, lng: 121.1 },
      ],
    });

    expect(reports).toHaveLength(2);
    expect(reports[0]).toMatchObject({
      report_type: "missed_pickup",
      zone_id: "zone-1",
      reporter_id: "driver-1",
      waste_type: "unknown",
      status: "pending",
      description: "Missed pickup: Blk 1 (route end)",
    });
    expect(reports[1].description).toBe("Missed pickup: Blk 2 (route end)");
  });

  it("returns completed_with_issues when route has missed stops", () => {
    expect(computeRouteEndStatus(2)).toBe("completed_with_issues");
  });

  it("returns completed when no missed stops", () => {
    expect(computeRouteEndStatus(0)).toBe("completed");
  });
});
