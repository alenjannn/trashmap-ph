import { describe, expect, it } from "vitest";
import { computeGate } from "@/lib/route-gate";

function computeAt(isoUtc: string) {
  return computeGate({ recurrence_day: "thursday", start_hour: 6, end_hour: 12 }, new Date(isoUtc));
}

describe("computeGate", () => {
  it("returns early when scheduled day is later than today", () => {
    const gate = computeAt("2026-05-05T01:00:00.000Z"); // Tue 09:00 Manila
    expect(gate).toBe("early");
  });

  it("returns late when scheduled day already passed", () => {
    const gate = computeAt("2026-05-08T01:00:00.000Z"); // Fri 09:00 Manila
    expect(gate).toBe("late");
  });

  it("returns early when same day but before start hour", () => {
    const gate = computeAt("2026-05-06T21:00:00.000Z"); // Thu 05:00 Manila
    expect(gate).toBe("early");
  });

  it("returns on_time inside allowed hour window", () => {
    const gate = computeAt("2026-05-07T00:00:00.000Z"); // Thu 08:00 Manila
    expect(gate).toBe("on_time");
  });

  it("returns late at or after end hour", () => {
    const gate = computeAt("2026-05-07T04:00:00.000Z"); // Thu 12:00 Manila
    expect(gate).toBe("late");
  });
});
