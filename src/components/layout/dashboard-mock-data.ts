export type DashboardPin = {
  id: string;
  lat: number;
  lng: number;
  type: "dumpsite" | "missed_pickup" | "hotspot";
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
  type: "dumpsite" | "missed_pickup" | "hotspot";
  title: string;
  locationLabel: string;
  createdAgo: string;
  severity: "low" | "medium" | "high";
};
