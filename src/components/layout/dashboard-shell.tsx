"use client";

import dynamic from "next/dynamic";
import { useEffect, useMemo, useState } from "react";
import {
  type BarangayLeaderboardItem,
  type DashboardPin,
  type DashboardRoutePath,
  type FleetTruck,
  type IncidentItem,
  type RiskZoneItem,
} from "@/components/layout/dashboard-mock-data";
import { getBrowserSupabaseClient } from "@/lib/supabase-browser";
import { BarangayLeaderboardPanel } from "@/components/panels/barangay-leaderboard-panel";
import { FleetStatusPanel } from "@/components/panels/fleet-status-panel";
import { IncidentFeedPanel } from "@/components/panels/incident-feed-panel";
import { RiskZonesPanel } from "@/components/panels/risk-zones-panel";

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
  zone_id: string | null;
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

type RouteRow = {
  id: string;
  truck_id: string;
  route_date: string;
  status: string;
  estimated_distance_km: number | null;
  estimated_fuel_liters: number | null;
  polyline: string | null;
};

type RouteProgressRow = {
  route_id: string;
  stop_id: string | null;
  status: "pending" | "arrived" | "completed" | "skipped";
  updated_at: string;
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

type CollectionPointRow = {
  id: string;
  label: string;
  lat: number;
  lng: number;
  is_active: boolean;
  zone_id: string | null;
};

type RouteTemplateRow = {
  id: string;
  name: string;
  recurrence_day: string;
  is_active: boolean;
};

type RiskZoneRow = {
  id: string;
  name: string;
  center_lat: number;
  center_lng: number;
  score: number;
  level: "low" | "medium" | "high" | "critical";
};

type ZoneRow = {
  id: string;
  name: string;
};

type RouteAuditRow = {
  id: string;
  route_id: string;
  event_type: "route_started" | "truck_arriving" | "stop_completed" | "route_completed" | "exception";
  area_label: string | null;
  event_time: string;
};

type DriverProfileRow = {
  user_id: string;
  display_name: string | null;
};

type RouteNotificationRow = {
  id: string;
  event_type: "route_started" | "truck_arriving" | "route_completed" | "exception";
  title: string;
  body: string;
  target_scope: "admin" | "citizen_zone" | "both";
  created_at: string;
};

// Blue-family palette — distinct from teal collection points
const routeColors = ["#2563EB", "#1D4ED8", "#3B82F6", "#1E40AF", "#60A5FA", "#1E3A8A"];
const INCIDENT_LIMIT = 12;

function formatCreatedAgo(createdAt: string): string {
  const now = Date.now();
  const created = new Date(createdAt).getTime();
  const diffMinutes = Math.max(1, Math.floor((now - created) / 60000));
  if (diffMinutes < 60) return `${diffMinutes}m`;
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours}h`;
  return `${Math.floor(diffHours / 24)}d`;
}

function parsePolyline(polyline: string | null): [number, number][] {
  if (!polyline) return [];
  return polyline
    .split(";")
    .map((segment) => segment.trim())
    .filter(Boolean)
    .map((segment) => {
      const [latRaw, lngRaw] = segment.split(",");
      const lat = Number(latRaw);
      const lng = Number(lngRaw);
      if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
      return [lat, lng] as [number, number];
    })
    .filter((point): point is [number, number] => point !== null);
}

export function DashboardShell() {
  const [reportPins, setReportPins] = useState<DashboardPin[]>([]);
  const [hotspotPins, setHotspotPins] = useState<DashboardPin[]>([]);
  const [collectionPointPins, setCollectionPointPins] = useState<DashboardPin[]>([]);
  const [riskZonePins, setRiskZonePins] = useState<DashboardPin[]>([]);
  const [routePaths, setRoutePaths] = useState<DashboardRoutePath[]>([]);
  const [fleet, setFleet] = useState<FleetTruck[]>([]);
  const [incidents, setIncidents] = useState<IncidentItem[]>([]);
  const [riskZones, setRiskZones] = useState<RiskZoneItem[]>([]);
  const [barangayLeaderboard, setBarangayLeaderboard] = useState<BarangayLeaderboardItem[]>([]);
  const [collectionPoints, setCollectionPoints] = useState<CollectionPointRow[]>([]);
  const [routeTemplates, setRouteTemplates] = useState<RouteTemplateRow[]>([]);
  const [activeRouteRows, setActiveRouteRows] = useState<RouteRow[]>([]);
  const [routeAuditRows, setRouteAuditRows] = useState<RouteAuditRow[]>([]);
  const [routeNotificationRows, setRouteNotificationRows] = useState<RouteNotificationRow[]>([]);
  const [driverProfiles, setDriverProfiles] = useState<DriverProfileRow[]>([]);
  const [pickupReportRows, setPickupReportRows] = useState<Array<{ routeId: string; label: string; status: string }>>([]);
  const [opsToken, setOpsToken] = useState("");
  const [templateName, setTemplateName] = useState("Weekly Thursday Brentwood");
  const [templateDay, setTemplateDay] = useState("thursday");
  const [templateZoneId, setTemplateZoneId] = useState("");
  const [selectedRouteId, setSelectedRouteId] = useState("");
  const [selectedDriverId, setSelectedDriverId] = useState("");
  const [routeOpsMessage, setRouteOpsMessage] = useState<string | null>(null);
  const [isRoutePlannerMode, setIsRoutePlannerMode] = useState(false);
  const [isAddingCollectionPoint, setIsAddingCollectionPoint] = useState(false);
  const [pendingCPCoords, setPendingCPCoords] = useState<{ lat: number; lng: number } | null>(null);
  const [newCPLabel, setNewCPLabel] = useState("");
  const [newCPZoneId, setNewCPZoneId] = useState("");
  const [isSubmittingCP, setIsSubmittingCP] = useState(false);
  const [cpMessage, setCPMessage] = useState<string | null>(null);
  const [draftRouteStops, setDraftRouteStops] = useState<
    { id: string; label: string; lat: number; lng: number }[]
  >([]);
  const [showRouteConfirmModal, setShowRouteConfirmModal] = useState(false);
  const [isLoadingPins, setIsLoadingPins] = useState(true);
  const [isOptimizingRoutes, setIsOptimizingRoutes] = useState(false);
  const [optimizeMessage, setOptimizeMessage] = useState<string | null>(null);
  const [pinError, setPinError] = useState<string | null>(null);
  const [zones, setZones] = useState<ZoneRow[]>([]);
  const [activeLogTab, setActiveLogTab] = useState<"all" | "audit" | "notifications" | "pickups">("all");
  const [dashboardRefreshKey, setDashboardRefreshKey] = useState(0);

  const supabase = getBrowserSupabaseClient();
  const pins = useMemo(
    () => [...reportPins, ...hotspotPins, ...collectionPointPins, ...riskZonePins],
    [collectionPointPins, hotspotPins, reportPins, riskZonePins],
  );

  const configError = !supabase ? "Supabase environment is not configured." : null;

  useEffect(() => {
    if (!supabase) return;
    const client = supabase;

    function mapReportToPin(report: ReportRow): DashboardPin {
      return {
        id: report.id,
        lat: report.lat,
        lng: report.lng,
        type: report.report_type === "dumpsite" ? "reported_garbage_point" : "missed_pickup",
        label: report.description?.trim() || "Citizen report",
        wasteType: report.waste_type,
      };
    }

    function mapReportToIncident(report: ReportRow): IncidentItem {
      const type = report.report_type;
      return {
        id: report.id,
        type: type === "dumpsite" ? "reported_garbage_point" : "missed_pickup",
        title: report.description?.trim() || "Citizen report submitted",
        locationLabel: `${report.lat.toFixed(5)}, ${report.lng.toFixed(5)}`,
        createdAgo: formatCreatedAgo(report.created_at),
        severity: type === "missed_pickup" ? "medium" : "high",
      };
    }

    function mapCollectionPointToPin(row: CollectionPointRow): DashboardPin {
      return {
        id: `collection-point-${row.id}`,
        lat: row.lat,
        lng: row.lng,
        type: "collection_point",
        label: row.label,
      };
    }

    function mapRiskZoneToPin(row: RiskZoneRow): DashboardPin {
      const radiusByLevel: Record<RiskZoneRow["level"], number> = {
        low: 60,
        medium: 90,
        high: 120,
        critical: 150,
      };
      return {
        id: `risk-zone-${row.id}`,
        lat: row.center_lat,
        lng: row.center_lng,
        type: "risk_zone",
        label: `${row.name} (${row.level.toUpperCase()}, ${(row.score * 100).toFixed(1)}%)`,
        radiusMeters: radiusByLevel[row.level],
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
      const { data: zonesData } = await client.from("zones").select("id, name");
      const zoneNameById = new Map((zonesData ?? []).map((zone) => [zone.id as string, (zone as ZoneRow).name]));

      const { data, error } = await client
        .from("reports")
        .select("id, created_at, lat, lng, zone_id, report_type, waste_type, description")
        .order("created_at", { ascending: false })
        .limit(250);

      if (error) {
        setPinError("Failed to load live report pins.");
        setIsLoadingPins(false);
        return;
      }

      const mappedRows = (data ?? []).map((row) => row as ReportRow);
      setReportPins(mappedRows.map((row) => mapReportToPin(row)));
      setIncidents(mappedRows.slice(0, INCIDENT_LIMIT).map((row) => mapReportToIncident(row)));

      const countByZone = new Map<string, number>();
      for (const row of mappedRows) {
        const zoneId = row.zone_id ?? "__unassigned__";
        countByZone.set(zoneId, (countByZone.get(zoneId) ?? 0) + 1);
      }

      const leaderboard = Array.from(countByZone.entries())
        .map(([zoneId, reportCount]) => ({
          id: zoneId,
          name: zoneId === "__unassigned__" ? "Unassigned Area" : (zoneNameById.get(zoneId) ?? "Unknown Barangay"),
          reportCount,
        }))
        .sort((a, b) => b.reportCount - a.reportCount)
        .slice(0, 10);
      setBarangayLeaderboard(leaderboard);
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

    async function loadCollectionPoints() {
      const { data, error } = await client
        .from("collection_points")
        .select("id, label, lat, lng, is_active, zone_id")
        .eq("is_active", true)
        .order("created_at", { ascending: false })
        .limit(300);
      if (error) return;
      const rows = (data ?? []).map((row) => row as CollectionPointRow);
      setCollectionPoints(rows);
      setCollectionPointPins(rows.map((row) => mapCollectionPointToPin(row)));
    }

    async function loadRiskZones() {
      const { data, error } = await client
        .from("risk_zones")
        .select("id, name, center_lat, center_lng, score, level")
        .order("score", { ascending: false })
        .limit(50);
      if (error) return;
      const rows = (data ?? []).map((row) => row as RiskZoneRow);
      const zonePins = rows.map((row) => mapRiskZoneToPin(row));
      setRiskZonePins(zonePins);
      setRiskZones(
        rows.slice(0, 5).map((row) => ({
          id: row.id,
          name: row.name,
          score: row.score,
          level: row.level,
        })),
      );
    }

    async function loadRoutesAndProgress() {
      const routeDate = new Date().toISOString().slice(0, 10);
      const { data: trucksData } = await client
        .from("trucks")
        .select("id, truck_code, driver_name")
        .limit(50);
      const truckById = new Map(
        (trucksData ?? []).map((row) => [row.id as string, { code: row.truck_code, driver: row.driver_name }]),
      );

      const { data, error } = await client
        .from("routes")
        .select("id, truck_id, route_date, status, estimated_distance_km, estimated_fuel_liters, polyline")
        .eq("route_date", routeDate)
        .in("status", ["published", "scheduled", "in_progress", "completed", "completed_with_issues"])
        .order("created_at", { ascending: false })
        .limit(20);
      if (error) return;
      const rows = (data ?? []).map((row) => row as RouteRow);
      setActiveRouteRows(rows);
      if (!selectedRouteId && rows.length > 0) {
        setSelectedRouteId(rows[0].id);
      }
      void loadRouteAssignmentsAndAudit(rows.map((row) => row.id));
      const mapped = rows
        .map((row, index) => {
          const points = parsePolyline(row.polyline);
          if (points.length < 2) return null;
          const truckMatch = truckById.get(row.truck_id);
          const truckLabel = truckMatch
            ? `${truckMatch.code} • ${truckMatch.driver ?? "Unassigned"}`
            : `Truck ${index + 1}`;
          return {
            id: row.id,
            truckLabel,
            color: routeColors[index % routeColors.length],
            points,
          } as DashboardRoutePath;
        })
        .filter((item): item is DashboardRoutePath => item !== null);
      setRoutePaths(mapped);

      const routeIds = rows.map((row) => row.id);
      let progressRows: RouteProgressRow[] = [];
      const stopCountByRoute = new Map<string, number>();

      if (routeIds.length > 0) {
        const { data: routeStopsData } = await client
          .from("route_stops")
          .select("route_id")
          .in("route_id", routeIds);
        for (const row of routeStopsData ?? []) {
          const routeId = row.route_id as string;
          stopCountByRoute.set(routeId, (stopCountByRoute.get(routeId) ?? 0) + 1);
        }

        const { data: progressData } = await client
          .from("route_progress")
          .select("route_id, stop_id, status, updated_at")
          .in("route_id", routeIds)
          .order("updated_at", { ascending: false });
        progressRows = (progressData ?? []).map((row) => row as RouteProgressRow);
      }

      const latestProgressByStop = new Map<string, RouteProgressRow>();
      for (const progress of progressRows) {
        if (!progress.stop_id) continue;
        const key = `${progress.route_id}:${progress.stop_id}`;
        if (!latestProgressByStop.has(key)) {
          latestProgressByStop.set(key, progress);
        }
      }

      const completedByRoute = new Map<string, number>();
      for (const progress of latestProgressByStop.values()) {
        if (progress.status === "completed") {
          completedByRoute.set(progress.route_id, (completedByRoute.get(progress.route_id) ?? 0) + 1);
        }
      }

      setFleet((previous) =>
        previous.map((truck) => {
          const truckRoutes = rows.filter((route) => route.truck_id === truck.id);
          if (truckRoutes.length === 0) {
            return { ...truck, progressPercent: 0, lastSeen: "live" };
          }

          const totalStops = truckRoutes.reduce((total, route) => total + (stopCountByRoute.get(route.id) ?? 0), 0);
          const completedStops = truckRoutes.reduce((total, route) => total + (completedByRoute.get(route.id) ?? 0), 0);
          const progressPercent =
            totalStops === 0 ? 0 : Math.max(0, Math.min(100, Math.round((completedStops / totalStops) * 100)));
          const status: FleetTruck["status"] =
            progressPercent === 100
              ? "idle"
              : progressPercent > 0
                ? "collecting"
                : truck.status === "idle"
                  ? "en_route"
                  : truck.status;

          return {
            ...truck,
            status,
            progressPercent,
            lastSeen: "live",
          };
        }),
      );

    }

    async function loadRouteAssignmentsAndAudit(routeIds: string[]) {
      if (routeIds.length === 0) {
        setRouteAuditRows([]);
        setRouteNotificationRows([]);
        setPickupReportRows([]);
        return;
      }

      const { data: auditData } = await client
        .from("route_audit_logs")
        .select("id, route_id, event_type, area_label, event_time")
        .in("route_id", routeIds)
        .order("event_time", { ascending: false })
        .limit(30);
      setRouteAuditRows((auditData ?? []) as RouteAuditRow[]);

      const { data: stopData } = await client
        .from("route_stops")
        .select("route_id, label, status")
        .in("route_id", routeIds)
        .order("created_at", { ascending: false })
        .limit(200);
      const pickupRows = (stopData ?? []).map((row) => ({
        routeId: row.route_id as string,
        label: row.label as string,
        status: row.status as string,
      }));
      setPickupReportRows(pickupRows);

      const { data: notificationData } = await client
        .from("route_notifications_log")
        .select("id, event_type, title, body, target_scope, created_at")
        .in("route_id", routeIds)
        .order("created_at", { ascending: false })
        .limit(30);
      setRouteNotificationRows((notificationData ?? []) as RouteNotificationRow[]);
    }

    async function loadDrivers() {
      const { data } = await client
        .from("app_user_profiles")
        .select("user_id, display_name")
        .eq("role", "driver")
        .limit(100);
      setDriverProfiles((data ?? []) as DriverProfileRow[]);
    }

    async function loadZones() {
      const { data } = await client.from("zones").select("id, name").order("name", { ascending: true }).limit(50);
      setZones((data ?? []) as ZoneRow[]);
    }

    async function loadRouteTemplates() {
      const { data } = await client
        .from("route_templates")
        .select("id, name, recurrence_day, is_active")
        .eq("is_active", true)
        .order("created_at", { ascending: false })
        .limit(40);
      setRouteTemplates((data ?? []) as RouteTemplateRow[]);
    }

    void loadReports();
    void loadHotspots();
    void loadFleet();
    void loadCollectionPoints();
    void loadRiskZones();
    void loadRoutesAndProgress();
    void loadDrivers();
    void loadZones();
    void loadRouteTemplates();

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

    const routesChannel = client
      .channel("dashboard-routes-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "routes" },
        () => {
          void loadRoutesAndProgress();
        },
      )
      .subscribe();

    const routeProgressChannel = client
      .channel("dashboard-route-progress-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "route_progress" },
        () => {
          void loadRoutesAndProgress();
        },
      )
      .subscribe();

    const routeStopsChannel = client
      .channel("dashboard-route-stops-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "route_stops" },
        () => {
          void loadRoutesAndProgress();
        },
      )
      .subscribe();

    const collectionPointsChannel = client
      .channel("dashboard-collection-points-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "collection_points" },
        () => {
          void loadCollectionPoints();
        },
      )
      .subscribe();

    const routeTemplatesChannel = client
      .channel("dashboard-route-templates-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "route_templates" },
        () => {
          void loadRouteTemplates();
        },
      )
      .subscribe();

    const riskZonesChannel = client
      .channel("dashboard-risk-zones-live-v1")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "risk_zones" },
        () => {
          void loadRiskZones();
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(reportsChannel);
      void client.removeChannel(trucksChannel);
      void client.removeChannel(hotspotsChannel);
      void client.removeChannel(routesChannel);
      void client.removeChannel(routeProgressChannel);
      void client.removeChannel(routeStopsChannel);
      void client.removeChannel(collectionPointsChannel);
      void client.removeChannel(routeTemplatesChannel);
      void client.removeChannel(riskZonesChannel);
    };
  }, [supabase, selectedRouteId, dashboardRefreshKey]);

  async function callOpsDelete(path: string): Promise<boolean> {
    setRouteOpsMessage(null);
    if (!opsToken.trim()) {
      setRouteOpsMessage("Route ops token required.");
      return false;
    }
    const response = await fetch(path, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${opsToken.trim()}` },
    });
    const payload = (await response.json()) as { ok?: boolean; message?: string };
    if (!response.ok || !payload.ok) {
      setRouteOpsMessage(payload.message ?? "Delete failed.");
      return false;
    }
    return true;
  }

  async function callRouteOps(path: string, body: Record<string, unknown>) {
    setRouteOpsMessage(null);
    if (!opsToken.trim()) {
      setRouteOpsMessage("Route ops token required.");
      return null;
    }
    const response = await fetch(path, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${opsToken.trim()}`,
      },
      body: JSON.stringify(body),
    });
    const payload = (await response.json()) as { ok?: boolean; message?: string };
    if (!response.ok || !payload.ok) {
      throw new Error(payload.message ?? "Route operation failed.");
    }
    return payload;
  }

  function handleMapCollectionPointClick(pin: { id: string; lat: number; lng: number; label: string }) {
    if (!isRoutePlannerMode) return;
    const rawId = pin.id.replace("collection-point-", "");
    const cpRow = collectionPoints.find((cp) => cp.id === rawId);
    if (!cpRow) return;
    setDraftRouteStops((prev) => {
      const exists = prev.find((s) => s.id === rawId);
      if (exists) return prev.filter((s) => s.id !== rawId);
      return [...prev, { id: rawId, label: cpRow.label, lat: cpRow.lat, lng: cpRow.lng }];
    });
  }

  async function handleCreateTemplate() {
    try {
      if (draftRouteStops.length === 0) {
        setRouteOpsMessage("Pick at least one collection point on the map.");
        return;
      }
      if (!supabase) {
        setRouteOpsMessage("Supabase not configured.");
        return;
      }

      // Zone: optional in UI — API resolves from picker, stop zone_ids, first DB zone, or creates default.
      let zoneForApi: string | undefined = templateZoneId.trim() || undefined;
      if (!zoneForApi && zones.length > 0) {
        zoneForApi = zones[0].id;
      }

      const templatePayload = await callRouteOps("/api/routes/templates", {
        name: templateName,
        ...(zoneForApi ? { zoneId: zoneForApi } : {}),
        recurrenceDay: templateDay,
        stops: draftRouteStops.map((stop, index) => ({ collectionPointId: stop.id, stopOrder: index + 1 })),
      });

      if (!templatePayload) return;
      const templateId = (templatePayload as { templateId?: string }).templateId;

      // Immediately materialize today's route from template
      if (templateId) {
        try {
          const materializePayload = await callRouteOps(`/api/routes/templates/${templateId}/materialize`, {});
          const routeId = (materializePayload as { routeId?: string } | null)?.routeId;
          if (routeId && !selectedRouteId) setSelectedRouteId(routeId);
        } catch {
          // Materialize failure is non-fatal — template still created
        }
      }

      setRouteOpsMessage(`Route "${templateName}" created (${draftRouteStops.length} stops). Ready to assign driver.`);
      setIsRoutePlannerMode(false);
      setDraftRouteStops([]);
      setShowRouteConfirmModal(false);
      setDashboardRefreshKey((k) => k + 1);
    } catch (error) {
      setRouteOpsMessage(error instanceof Error ? error.message : "Template create failed.");
    }
  }

  async function handleDeleteRoute(routeId: string) {
    if (!window.confirm("Delete this route and related stops, progress, and assignments?")) return;
    const ok = await callOpsDelete(`/api/routes/${routeId}`);
    if (ok) {
      setRouteOpsMessage("Route deleted.");
      if (selectedRouteId === routeId) setSelectedRouteId("");
      setDashboardRefreshKey((k) => k + 1);
    }
  }

  async function handleDeleteTemplate(templateId: string) {
    if (!window.confirm("Delete this weekly route template and its stop list?")) return;
    const ok = await callOpsDelete(`/api/routes/templates/${templateId}`);
    if (ok) {
      setRouteOpsMessage("Weekly template deleted.");
      setDashboardRefreshKey((k) => k + 1);
    }
  }

  async function handleDeleteCollectionPoint(cpId: string, label: string) {
    if (!window.confirm(`Remove collection point "${label}"? Templates referencing it will lose those stops.`)) return;
    const ok = await callOpsDelete(`/api/collection-points/${cpId}`);
    if (ok) {
      setRouteOpsMessage("Collection point deleted.");
      setDashboardRefreshKey((k) => k + 1);
    }
  }

  async function handleAssignDriver(mode: "manual" | "auto") {
    try {
      if (!selectedRouteId) {
        setRouteOpsMessage("Select route first.");
        return;
      }
      await callRouteOps(`/api/routes/${selectedRouteId}/assign`, {
        mode,
        driverId: mode === "manual" ? selectedDriverId : undefined,
      });
      setRouteOpsMessage("Driver assigned.");
    } catch (error) {
      setRouteOpsMessage(error instanceof Error ? error.message : "Driver assign failed.");
    }
  }

  async function handleAddCollectionPoint() {
    if (!pendingCPCoords || !newCPLabel.trim()) return;
    setIsSubmittingCP(true);
    setCPMessage(null);
    try {
      const response = await fetch("/api/collection-points", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${opsToken.trim()}`,
        },
        body: JSON.stringify({
          label: newCPLabel.trim(),
          lat: pendingCPCoords.lat,
          lng: pendingCPCoords.lng,
          zoneId: newCPZoneId || null,
        }),
      });
      const payload = (await response.json()) as { ok?: boolean; message?: string; snapped?: boolean };
      if (!response.ok || !payload.ok) throw new Error(payload.message ?? "Failed to add collection point.");
      setCPMessage(payload.message ?? "Collection point added.");
      setPendingCPCoords(null);
      setNewCPLabel("");
      setIsAddingCollectionPoint(false);
    } catch (error) {
      setCPMessage(error instanceof Error ? error.message : "Failed to add collection point.");
    } finally {
      setIsSubmittingCP(false);
    }
  }

  async function handleOptimizeNow() {
    setIsOptimizingRoutes(true);
    setOptimizeMessage(null);
    try {
      const response = await fetch("/api/optimize-routes", { method: "POST" });
      const payload = (await response.json()) as { ok?: boolean; message?: string; mode?: string };
      if (!response.ok || !payload.ok) {
        throw new Error(payload.message ?? "Failed to optimize routes.");
      }
      setOptimizeMessage(`Routes optimized (${payload.mode ?? "mock"} mode).`);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Failed to optimize routes.";
      setOptimizeMessage(message);
    } finally {
      setIsOptimizingRoutes(false);
    }
  }

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
          <div className="mb-3 flex items-center justify-between gap-3">
            <h2 className="text-sm font-semibold uppercase tracking-wide text-zinc-800">Map Overview</h2>
            <div className="flex items-center gap-3">
              <div className="flex items-center gap-3 text-xs text-zinc-600">
                <span className="inline-flex items-center gap-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-orange-500" />
                  Reported Garbage Point
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-blue-500" />
                  Missed Pickup
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-red-500" />
                  Hotspot
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-teal-500" />
                  Collection Point
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-blue-600" />
                  Routes
                </span>
                <span className="inline-flex items-center gap-1">
                  <span className="h-2.5 w-2.5 rounded-full bg-amber-400" />
                  Risk Zone
                </span>
              </div>
              <button
                type="button"
                onClick={() => {
                  void handleOptimizeNow();
                }}
                disabled={isOptimizingRoutes}
                className="rounded-md bg-emerald-600 px-3 py-1.5 text-xs font-semibold text-white transition hover:bg-emerald-700 disabled:cursor-not-allowed disabled:bg-emerald-300"
              >
                {isOptimizingRoutes ? "Optimizing..." : "Optimize Now"}
              </button>
            </div>
          </div>
          {optimizeMessage ? (
            <div className="mb-3 rounded-md border border-zinc-200 bg-zinc-50 px-3 py-2 text-xs text-zinc-700">
              {optimizeMessage}
            </div>
          ) : null}
          {isRoutePlannerMode ? (
            <div className="mb-3 flex items-center gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
              <span className="inline-block h-2 w-2 animate-pulse rounded-full bg-amber-500" />
              Route Planning Active — Click teal pins on map to add stops. Selected stops shown in gold.
            </div>
          ) : null}
          {isAddingCollectionPoint ? (
            <div className="mb-3 flex items-center gap-2 rounded-lg border border-violet-300 bg-violet-50 px-3 py-2 text-xs font-semibold text-violet-800">
              <span className="inline-block h-2 w-2 animate-pulse rounded-full bg-violet-500" />
              Click anywhere on a road to place a new Collection Point.
            </div>
          ) : null}
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
              <LGUMap
                pins={pins}
                routes={routePaths}
                planningMode={isRoutePlannerMode}
                addingCollectionPoint={isAddingCollectionPoint}
                draftStopIds={draftRouteStops.map((s) => s.id)}
                draftRoutePoints={draftRouteStops.map((s) => [s.lat, s.lng] as [number, number])}
                onCollectionPointClick={handleMapCollectionPointClick}
                onMapClick={(lat, lng) => {
                  if (isAddingCollectionPoint) {
                    setPendingCPCoords({ lat, lng });
                  }
                }}
              />
            )}
          </div>
        </section>

        <aside className="space-y-4">
          {/* ── Route Planner ─────────────────────────────────── */}
          <section className="rounded-2xl border border-zinc-200 bg-white shadow-sm">
            <div className="flex items-center justify-between border-b border-zinc-100 px-4 py-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-zinc-800">Route Planner</h3>
              {isRoutePlannerMode ? (
                <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2 py-0.5 text-[10px] font-semibold text-amber-800">
                  <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500" />
                  Planning
                </span>
              ) : isAddingCollectionPoint ? (
                <span className="inline-flex items-center gap-1 rounded-full bg-violet-100 px-2 py-0.5 text-[10px] font-semibold text-violet-800">
                  <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-violet-500" />
                  Pin CP
                </span>
              ) : null}
            </div>

            {!isRoutePlannerMode && !isAddingCollectionPoint ? (
              <div className="space-y-2 px-4 py-4">
                <p className="text-xs text-zinc-500">
                  Click teal collection point pins on the map to build a weekly route in order.
                </p>
                <button
                  type="button"
                  onClick={() => {
                    setDraftRouteStops([]);
                    setRouteOpsMessage(null);
                    setIsRoutePlannerMode(true);
                  }}
                  className="w-full cursor-pointer rounded-lg bg-teal-600 px-3 py-2 text-sm font-semibold text-white transition-colors hover:bg-teal-700 active:bg-teal-800"
                >
                  Create Weekly Route
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setCPMessage(null);
                    setPendingCPCoords(null);
                    setNewCPLabel("");
                    setIsAddingCollectionPoint(true);
                  }}
                  className="w-full cursor-pointer rounded-lg border border-violet-400 px-3 py-2 text-sm font-semibold text-violet-700 transition-colors hover:bg-violet-50 active:bg-violet-100"
                >
                  + Add Collection Point
                </button>
                {cpMessage ? (
                  <p className="rounded-md bg-zinc-50 px-2 py-1.5 text-xs text-zinc-700">{cpMessage}</p>
                ) : null}
              </div>
            ) : isAddingCollectionPoint ? (
              <div className="space-y-3 px-4 py-4">
                {pendingCPCoords ? (
                  <p className="rounded-md bg-violet-50 px-2 py-1.5 text-xs text-violet-800">
                    Point selected: {pendingCPCoords.lat.toFixed(5)}, {pendingCPCoords.lng.toFixed(5)}
                  </p>
                ) : (
                  <p className="text-xs text-zinc-500">Click on a road on the map to place the point.</p>
                )}
                <div>
                  <label className="mb-0.5 block text-[11px] font-semibold text-zinc-700">Label *</label>
                  <input
                    value={newCPLabel}
                    onChange={(e) => setNewCPLabel(e.target.value)}
                    placeholder="e.g. Zone 3 Corner Stop"
                    className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-violet-500"
                  />
                </div>
                <div>
                  <label className="mb-0.5 block text-[11px] font-semibold text-zinc-700">Zone</label>
                  <select
                    value={newCPZoneId}
                    onChange={(e) => setNewCPZoneId(e.target.value)}
                    className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 focus:outline-none focus:ring-2 focus:ring-violet-500"
                  >
                    <option value="">Auto-assign zone</option>
                    {zones.map((z) => <option key={z.id} value={z.id}>{z.name}</option>)}
                  </select>
                </div>
                <div>
                  <label className="mb-0.5 block text-[11px] font-semibold text-zinc-700">Ops Token</label>
                  <input
                    type="password"
                    value={opsToken}
                    onChange={(e) => setOpsToken(e.target.value)}
                    placeholder="Route ops token"
                    className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-violet-500"
                  />
                </div>
                {cpMessage ? (
                  <p className="rounded-md bg-zinc-50 px-2 py-1.5 text-xs text-zinc-700">{cpMessage}</p>
                ) : null}
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => { setIsAddingCollectionPoint(false); setPendingCPCoords(null); setCPMessage(null); }}
                    className="flex-1 cursor-pointer rounded-lg border border-zinc-300 px-3 py-2 text-xs font-semibold text-zinc-700 transition-colors hover:bg-zinc-100"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    disabled={!pendingCPCoords || !newCPLabel.trim() || !opsToken.trim() || isSubmittingCP}
                    onClick={() => { void handleAddCollectionPoint(); }}
                    className="flex-1 cursor-pointer rounded-lg bg-violet-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-violet-700 disabled:cursor-not-allowed disabled:bg-violet-300"
                  >
                    {isSubmittingCP ? "Adding..." : "Add Point"}
                  </button>
                </div>
              </div>
            ) : (
              <div className="px-4 py-4">
                <div className="mb-3 space-y-1">
                  {draftRouteStops.length === 0 ? (
                    <p className="rounded-md bg-zinc-50 px-3 py-3 text-center text-xs text-zinc-500">
                      No stops selected yet. Click teal pins on the map.
                    </p>
                  ) : (
                    <ul className="max-h-40 space-y-1 overflow-y-auto">
                      {draftRouteStops.map((stop, idx) => (
                        <li
                          key={stop.id}
                          className="flex items-center gap-2 rounded-md border border-zinc-200 bg-zinc-50 px-2 py-1.5 text-xs"
                        >
                          <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-white">
                            {idx + 1}
                          </span>
                          <span className="min-w-0 flex-1 truncate font-medium text-zinc-800">{stop.label}</span>
                          <button
                            type="button"
                            onClick={() =>
                              setDraftRouteStops((prev) => prev.filter((s) => s.id !== stop.id))
                            }
                            className="shrink-0 cursor-pointer text-zinc-400 hover:text-red-500"
                            aria-label="Remove stop"
                          >
                            ✕
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
                <div className="flex gap-2">
                  <button
                    type="button"
                    onClick={() => {
                      setIsRoutePlannerMode(false);
                      setDraftRouteStops([]);
                      setRouteOpsMessage(null);
                    }}
                    className="flex-1 cursor-pointer rounded-lg border border-zinc-300 px-3 py-2 text-xs font-semibold text-zinc-700 transition-colors hover:bg-zinc-100"
                  >
                    Cancel
                  </button>
                  <button
                    type="button"
                    disabled={draftRouteStops.length === 0}
                    onClick={() => setShowRouteConfirmModal(true)}
                    className="flex-1 cursor-pointer rounded-lg bg-teal-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-teal-700 disabled:cursor-not-allowed disabled:bg-teal-300"
                  >
                    Confirm Route ({draftRouteStops.length})
                  </button>
                </div>
                {routeOpsMessage ? (
                  <p className="mt-2 rounded-md bg-zinc-50 px-2 py-1.5 text-xs text-zinc-700">{routeOpsMessage}</p>
                ) : null}
              </div>
            )}
          </section>

          {/* ── Driver Assignment ─────────────────────────────── */}
          <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
            <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-zinc-800">Driver Assignment</h3>
            <div className="space-y-2">
              <input
                type="password"
                value={opsToken}
                onChange={(event) => setOpsToken(event.target.value)}
                placeholder="Route ops token"
                className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-teal-500"
              />
              <select
                value={selectedRouteId}
                onChange={(event) => setSelectedRouteId(event.target.value)}
                className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 focus:outline-none focus:ring-2 focus:ring-teal-500"
              >
                <option value="">Select route…</option>
                {activeRouteRows.map((route) => (
                  <option key={route.id} value={route.id}>
                    {route.route_date} · {route.status} · {route.id.slice(0, 8)}…
                  </option>
                ))}
              </select>
              <select
                value={selectedDriverId}
                onChange={(event) => setSelectedDriverId(event.target.value)}
                className="w-full rounded-md border border-zinc-300 bg-white px-2 py-1.5 text-xs text-zinc-900 focus:outline-none focus:ring-2 focus:ring-teal-500"
              >
                <option value="">Select driver…</option>
                {driverProfiles.map((driver) => (
                  <option key={driver.user_id} value={driver.user_id}>
                    {driver.display_name ?? driver.user_id.slice(0, 8)}
                  </option>
                ))}
              </select>
              <div className="flex gap-2">
                <button
                  type="button"
                  onClick={() => { void handleAssignDriver("manual"); }}
                  className="flex-1 cursor-pointer rounded-lg bg-emerald-600 px-2 py-2 text-xs font-semibold text-white transition-colors hover:bg-emerald-700"
                >
                  Assign Manual
                </button>
                <button
                  type="button"
                  onClick={() => { void handleAssignDriver("auto"); }}
                  className="flex-1 cursor-pointer rounded-lg bg-zinc-700 px-2 py-2 text-xs font-semibold text-white transition-colors hover:bg-zinc-900"
                >
                  Assign Auto
                </button>
              </div>
              {!isRoutePlannerMode && routeOpsMessage ? (
                <p className="rounded-md bg-zinc-50 px-2 py-1.5 text-xs text-zinc-700">{routeOpsMessage}</p>
              ) : null}
            </div>
          </section>

          {/* ── Delete / manage entities ─────────────────────── */}
          <section className="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
            <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-zinc-800">Manage Data</h3>
            <p className="mb-3 text-[11px] text-zinc-500">Uses route ops token above. Deletes cannot be undone.</p>

            <div className="mb-4">
              <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Today&apos;s routes</p>
              <div className="max-h-28 space-y-1 overflow-y-auto text-xs">
                {activeRouteRows.length === 0 ? (
                  <p className="text-zinc-400">No routes for today.</p>
                ) : (
                  activeRouteRows.map((r) => (
                    <div key={r.id} className="flex items-center justify-between gap-2 rounded border border-zinc-100 px-2 py-1">
                      <span className="min-w-0 truncate text-zinc-700">
                        {r.status} · {r.id.slice(0, 8)}
                      </span>
                      <button
                        type="button"
                        onClick={() => { void handleDeleteRoute(r.id); }}
                        className="shrink-0 cursor-pointer rounded bg-red-50 px-2 py-0.5 text-[10px] font-semibold text-red-700 hover:bg-red-100"
                      >
                        Delete
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div className="mb-4">
              <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Weekly templates</p>
              <div className="max-h-28 space-y-1 overflow-y-auto text-xs">
                {routeTemplates.length === 0 ? (
                  <p className="text-zinc-400">No templates yet.</p>
                ) : (
                  routeTemplates.map((t) => (
                    <div key={t.id} className="flex items-center justify-between gap-2 rounded border border-zinc-100 px-2 py-1">
                      <span className="min-w-0 truncate text-zinc-700" title={t.name}>
                        {t.name} · {t.recurrence_day}
                      </span>
                      <button
                        type="button"
                        onClick={() => { void handleDeleteTemplate(t.id); }}
                        className="shrink-0 cursor-pointer rounded bg-red-50 px-2 py-0.5 text-[10px] font-semibold text-red-700 hover:bg-red-100"
                      >
                        Delete
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>

            <div>
              <p className="mb-1 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">Collection points</p>
              <div className="max-h-36 space-y-1 overflow-y-auto text-xs">
                {collectionPoints.length === 0 ? (
                  <p className="text-zinc-400">No active collection points.</p>
                ) : (
                  collectionPoints.map((cp) => (
                    <div key={cp.id} className="flex items-center justify-between gap-2 rounded border border-zinc-100 px-2 py-1">
                      <span className="min-w-0 truncate text-zinc-700" title={cp.label}>
                        {cp.label}
                      </span>
                      <button
                        type="button"
                        onClick={() => { void handleDeleteCollectionPoint(cp.id, cp.label); }}
                        className="shrink-0 cursor-pointer rounded bg-red-50 px-2 py-0.5 text-[10px] font-semibold text-red-700 hover:bg-red-100"
                      >
                        Delete
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>
          </section>

          {/* ── Ops Activity Log (merged tabbed) ──────────────── */}
          <section className="rounded-2xl border border-zinc-200 bg-white shadow-sm">
            <div className="border-b border-zinc-100 px-4 py-3">
              <h3 className="text-sm font-semibold uppercase tracking-wide text-zinc-800">Ops Activity Log</h3>
              <div className="mt-2 flex gap-1">
                {(["all", "audit", "notifications", "pickups"] as const).map((tab) => (
                  <button
                    key={tab}
                    type="button"
                    onClick={() => setActiveLogTab(tab)}
                    className={`cursor-pointer rounded-md px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide transition-colors ${
                      activeLogTab === tab
                        ? "bg-zinc-800 text-white"
                        : "bg-zinc-100 text-zinc-600 hover:bg-zinc-200"
                    }`}
                  >
                    {tab === "all" ? "All" : tab === "audit" ? "Audit" : tab === "notifications" ? "Alerts" : "Pickups"}
                  </button>
                ))}
              </div>
            </div>
            <div className="max-h-80 overflow-y-auto divide-y divide-zinc-100">
              {/* Audit rows */}
              {(activeLogTab === "all" || activeLogTab === "audit") && routeAuditRows.length === 0 && activeLogTab === "audit" ? (
                <p className="px-4 py-3 text-xs text-zinc-500">No audit events yet.</p>
              ) : null}
              {(activeLogTab === "all" || activeLogTab === "audit") && routeAuditRows.map((row) => (
                <div key={row.id} className="flex items-start gap-3 px-4 py-2.5">
                  <span className="mt-0.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-blue-500" />
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold text-zinc-800">{row.event_type.replace(/_/g, " ")}</p>
                    <p className="text-[11px] text-zinc-500">{row.area_label ?? "—"} · {new Date(row.event_time).toLocaleTimeString()}</p>
                    <p className="text-[10px] text-zinc-400">route {row.route_id.slice(0, 8)}</p>
                  </div>
                  <span className="shrink-0 rounded-full bg-blue-50 px-1.5 py-0.5 text-[9px] font-semibold uppercase text-blue-700">audit</span>
                </div>
              ))}
              {/* Notification rows */}
              {(activeLogTab === "all" || activeLogTab === "notifications") && routeNotificationRows.length === 0 && activeLogTab === "notifications" ? (
                <p className="px-4 py-3 text-xs text-zinc-500">No notifications yet.</p>
              ) : null}
              {(activeLogTab === "all" || activeLogTab === "notifications") && routeNotificationRows.map((row) => (
                <div key={row.id} className="flex items-start gap-3 px-4 py-2.5">
                  <span className="mt-0.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full bg-emerald-500" />
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold text-zinc-800">{row.title}</p>
                    <p className="text-[11px] text-zinc-600">{row.body}</p>
                    <p className="text-[10px] text-zinc-400">{new Date(row.created_at).toLocaleTimeString()} · {row.target_scope}</p>
                  </div>
                  <span className="shrink-0 rounded-full bg-emerald-50 px-1.5 py-0.5 text-[9px] font-semibold uppercase text-emerald-700">alert</span>
                </div>
              ))}
              {/* Pickup rows */}
              {(activeLogTab === "all" || activeLogTab === "pickups") && pickupReportRows.length === 0 && activeLogTab === "pickups" ? (
                <p className="px-4 py-3 text-xs text-zinc-500">No pickup confirmations yet.</p>
              ) : null}
              {(activeLogTab === "all" || activeLogTab === "pickups") && pickupReportRows.map((row, idx) => (
                <div key={`${row.routeId}-${idx}`} className="flex items-start gap-3 px-4 py-2.5">
                  <span className={`mt-0.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full ${
                    row.status === "completed" ? "bg-teal-500" : row.status === "skipped" ? "bg-amber-400" : "bg-zinc-400"
                  }`} />
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold text-zinc-800">{row.label}</p>
                    <p className="text-[10px] text-zinc-400">route {row.routeId.slice(0, 8)}</p>
                  </div>
                  <span className={`shrink-0 rounded-full px-1.5 py-0.5 text-[9px] font-semibold uppercase ${
                    row.status === "completed" ? "bg-teal-50 text-teal-700" :
                    row.status === "skipped" ? "bg-amber-50 text-amber-700" :
                    "bg-zinc-100 text-zinc-600"
                  }`}>{row.status}</span>
                </div>
              ))}
              {activeLogTab === "all" && routeAuditRows.length === 0 && routeNotificationRows.length === 0 && pickupReportRows.length === 0 ? (
                <p className="px-4 py-4 text-xs text-zinc-500">No activity yet. Start a route to see logs here.</p>
              ) : null}
            </div>
          </section>
          <IncidentFeedPanel incidents={incidents} title="Waste Report Feed" />
          <FleetStatusPanel trucks={fleet} />
          <BarangayLeaderboardPanel items={barangayLeaderboard} />
          <RiskZonesPanel zones={riskZones} />
        </aside>
      </main>

      {/* ── Route Confirmation Modal ──────────────────────────── */}
      {showRouteConfirmModal ? (
        <div
          className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/40 backdrop-blur-sm"
          onClick={() => setShowRouteConfirmModal(false)}
        >
          <div
            className="mx-4 w-full max-w-sm rounded-2xl bg-white shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="border-b border-zinc-100 px-6 py-4">
              <h2 className="text-base font-bold text-zinc-900">Confirm Weekly Route</h2>
              <p className="mt-0.5 text-xs text-zinc-500">
                {draftRouteStops.length} stop{draftRouteStops.length !== 1 ? "s" : ""} selected
              </p>
            </div>
            <div className="px-6 py-5 space-y-4">
              <div>
                <label className="mb-1 block text-xs font-semibold text-zinc-700">Route Name</label>
                <input
                  value={templateName}
                  onChange={(e) => setTemplateName(e.target.value)}
                  placeholder="e.g. Weekly Thursday Brentwood"
                  className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-teal-500"
                />
              </div>
              <div>
                <label className="mb-1 block text-xs font-semibold text-zinc-700">Recurrence Day</label>
                <select
                  value={templateDay}
                  onChange={(e) => setTemplateDay(e.target.value)}
                  className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-teal-500"
                >
                  {["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].map((day) => (
                    <option key={day} value={day}>
                      {day.charAt(0).toUpperCase() + day.slice(1)}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="mb-1 block text-xs font-semibold text-zinc-700">Zone (optional)</label>
                <select
                  value={templateZoneId}
                  onChange={(e) => setTemplateZoneId(e.target.value)}
                  className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 focus:outline-none focus:ring-2 focus:ring-teal-500"
                >
                  <option value="">Auto — from stops, DB, or new default zone</option>
                  {zones.map((z) => (
                    <option key={z.id} value={z.id}>
                      {z.name}
                    </option>
                  ))}
                </select>
                <p className="mt-1 text-[11px] text-zinc-500">
                  Leave auto if stops share one zone_id, or if zones table is empty (server creates default).
                </p>
              </div>
              <div>
                <label className="mb-1 block text-xs font-semibold text-zinc-700">Ops Token</label>
                <input
                  type="password"
                  value={opsToken}
                  onChange={(e) => setOpsToken(e.target.value)}
                  placeholder="Route ops token"
                  className="w-full rounded-lg border border-zinc-300 bg-white px-3 py-2 text-sm text-zinc-900 placeholder-zinc-400 focus:outline-none focus:ring-2 focus:ring-teal-500"
                />
              </div>
              <div className="rounded-lg border border-zinc-100 bg-zinc-50 px-3 py-2">
                <p className="mb-1.5 text-[10px] font-semibold uppercase tracking-wider text-zinc-500">Stops in order</p>
                <ol className="space-y-1 text-xs text-zinc-800">
                  {draftRouteStops.map((stop, idx) => (
                    <li key={stop.id} className="flex items-center gap-2">
                      <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-amber-500 text-[9px] font-bold text-white">
                        {idx + 1}
                      </span>
                      {stop.label}
                    </li>
                  ))}
                </ol>
              </div>
              {routeOpsMessage ? (
                <p className="rounded-md bg-red-50 px-3 py-2 text-xs text-red-700">{routeOpsMessage}</p>
              ) : null}
            </div>
            <div className="flex gap-3 border-t border-zinc-100 px-6 py-4">
              <button
                type="button"
                onClick={() => setShowRouteConfirmModal(false)}
                className="flex-1 cursor-pointer rounded-lg border border-zinc-300 px-3 py-2 text-sm font-semibold text-zinc-700 transition-colors hover:bg-zinc-50"
              >
                Back
              </button>
              <button
                type="button"
                onClick={() => { void handleCreateTemplate(); }}
                disabled={!templateName.trim() || !opsToken.trim()}
                className="flex-1 cursor-pointer rounded-lg bg-teal-600 px-3 py-2 text-sm font-semibold text-white transition-colors hover:bg-teal-700 disabled:cursor-not-allowed disabled:bg-teal-300"
              >
                Create Route
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
