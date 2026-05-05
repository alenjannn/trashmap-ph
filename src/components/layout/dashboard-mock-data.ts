export type DashboardPin = {
  id: string;
  lat: number;
  lng: number;
  type: "dumpsite" | "missed_pickup" | "hotspot";
  label: string;
  wasteType?: "biodegradable" | "recyclable" | "mixed" | "unknown";
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

export const dashboardPins: DashboardPin[] = [
  {
    id: "pin-1",
    lat: 14.676,
    lng: 121.0437,
    type: "dumpsite",
    label: "Uncollected sacks near alley",
    wasteType: "mixed",
  },
  {
    id: "pin-2",
    lat: 14.6732,
    lng: 121.0475,
    type: "missed_pickup",
    label: "Missed pickup on Tuesday route",
    wasteType: "unknown",
  },
  {
    id: "pin-3",
    lat: 14.6788,
    lng: 121.0492,
    type: "hotspot",
    label: "High report cluster zone",
    wasteType: "mixed",
  },
];

export const fleetTrucks: FleetTruck[] = [
  {
    id: "truck-1",
    code: "QC-TRK-01",
    driver: "A. Dela Cruz",
    status: "collecting",
    progressPercent: 62,
    lastSeen: "2 min ago",
  },
  {
    id: "truck-2",
    code: "QC-TRK-03",
    driver: "R. Santos",
    status: "en_route",
    progressPercent: 28,
    lastSeen: "1 min ago",
  },
  {
    id: "truck-3",
    code: "QC-TRK-08",
    driver: "M. Rivera",
    status: "maintenance",
    progressPercent: 0,
    lastSeen: "14 min ago",
  },
];

export const incidentFeed: IncidentItem[] = [
  {
    id: "inc-1",
    type: "hotspot",
    title: "Cluster reached hotspot threshold",
    locationLabel: "Brgy. Central Avenue",
    createdAgo: "3m",
    severity: "high",
  },
  {
    id: "inc-2",
    type: "missed_pickup",
    title: "Missed pickup report submitted",
    locationLabel: "Westbound Service Road",
    createdAgo: "9m",
    severity: "medium",
  },
  {
    id: "inc-3",
    type: "dumpsite",
    title: "New dumpsite with photo evidence",
    locationLabel: "Aurora Street corner",
    createdAgo: "15m",
    severity: "low",
  },
];
