export type DashboardPin = {
  id: string;
  lat: number;
  lng: number;
  type: "reported_garbage_point" | "missed_pickup" | "hotspot" | "collection_point" | "risk_zone";
  label: string;
  wasteType?: "biodegradable" | "recyclable" | "special_hazardous" | "mixed" | "unknown";
  radiusMeters?: number;
};

export type DashboardRoutePath = {
  id: string;
  truckLabel: string;
  color: string;
  points: [number, number][];
};

export type FleetTruck = {
  id: string;
  code: string;
  driver: string;
  status: "idle" | "en_route" | "collecting" | "maintenance";
  progressPercent: number;
  lastSeen: string;
};

export type IncidentItem = {
  id: string;
  type: "reported_garbage_point" | "missed_pickup" | "hotspot";
  title: string;
  locationLabel: string;
  createdAgo: string;
  severity: "low" | "medium" | "high";
};

export type RiskZoneItem = {
  id: string;
  name: string;
  score: number;
  level: "low" | "medium" | "high" | "critical";
};

export type BarangayLeaderboardItem = {
  id: string;
  name: string;
  reportCount: number;
};
