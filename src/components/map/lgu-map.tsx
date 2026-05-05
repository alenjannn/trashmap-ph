"use client";

import "leaflet/dist/leaflet.css";
import { CircleMarker, MapContainer, Popup, TileLayer } from "react-leaflet";
import type { DashboardPin } from "@/components/layout/dashboard-mock-data";

type Props = {
  pins: DashboardPin[];
};

const colorByType: Record<DashboardPin["type"], string> = {
  dumpsite: "#f59e0b",
  missed_pickup: "#3b82f6",
  hotspot: "#ef4444",
};

export function LGUMap({ pins }: Props) {
  return (
    <MapContainer
      center={[14.676, 121.0437]}
      zoom={14}
      scrollWheelZoom={false}
      className="h-full w-full rounded-xl"
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />

      {pins.map((pin) => (
        <CircleMarker
          key={pin.id}
          center={[pin.lat, pin.lng]}
          radius={pin.type === "hotspot" ? 16 : 9}
          pathOptions={{
            color: colorByType[pin.type],
            fillColor: colorByType[pin.type],
            fillOpacity: pin.type === "hotspot" ? 0.25 : 0.75,
            weight: 2,
          }}
        >
          <Popup>
            <div className="space-y-1">
              <p className="text-sm font-semibold uppercase tracking-wide">{pin.type.replace("_", " ")}</p>
              <p className="text-sm">{pin.label}</p>
              {pin.wasteType ? (
                <p className="text-xs text-zinc-500">Waste: {pin.wasteType.replaceAll("_", " ")}</p>
              ) : null}
            </div>
          </Popup>
        </CircleMarker>
      ))}
    </MapContainer>
  );
}
