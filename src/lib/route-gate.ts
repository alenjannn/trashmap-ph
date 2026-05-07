export type RouteGate = "on_time" | "early" | "late";

const DAY_ORDER: Record<string, number> = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6,
};

export type TemplateGateInput = {
  recurrence_day: string;
  start_hour: number;
  end_hour: number;
};

/**
 * Compare scheduled window vs "now" in Asia/Manila (route ops TZ for TrashMap PH).
 */
export function computeGate(template: TemplateGateInput, now: Date): RouteGate {
  const scheduledDay = DAY_ORDER[template.recurrence_day.toLowerCase()];
  if (scheduledDay === undefined) {
    return "on_time";
  }

  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Manila",
    weekday: "long",
    hour: "numeric",
    hour12: false,
  });
  const parts = formatter.formatToParts(now);
  const weekdayName = (parts.find((p) => p.type === "weekday")?.value ?? "sunday").toLowerCase();
  const hourRaw = parts.find((p) => p.type === "hour")?.value ?? "0";
  const today = DAY_ORDER[weekdayName] ?? 0;
  const hour = Number.parseInt(hourRaw, 10);
  const safeHour = Number.isFinite(hour) ? hour : 0;

  if (today < scheduledDay) return "early";
  if (today > scheduledDay) return "late";

  if (safeHour < template.start_hour) return "early";
  if (safeHour >= template.end_hour) return "late";
  return "on_time";
}

/** Calendar date YYYY-MM-DD in Asia/Manila (for route_date column). */
export function routeDateInManila(d: Date = new Date()): string {
  return d.toLocaleDateString("en-CA", { timeZone: "Asia/Manila" });
}
