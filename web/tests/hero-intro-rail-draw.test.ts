import { describe, expect, it } from "vitest";

import { planHeroRailStaircase } from "../src/hero-intro/hero-intro-rail-draw";

describe("hero rail staircase", () => {
  it("holds the draw at each dot before the next hop and forks after its pop", () => {
    const schedule = planHeroRailStaircase(5);
    expect(schedule.hops).toHaveLength(5);
    expect(schedule.hops[0]?.drawDuration).toBeCloseTo(0.1);
    expect(schedule.hops[1]?.start).toBeCloseTo(6.14);
    for (const [index, hop] of schedule.hops.entries()) {
      const dotArrival = index === 0 ? schedule.start : (schedule.hops[index - 1]?.arrival ?? 0);
      expect(hop.forkStart).toBeGreaterThanOrEqual(dotArrival + 0.18 + 0.06 - 0.001);
      if (index > 0) {
        const previous = schedule.hops[index - 1];
        expect(previous).toBeDefined();
        expect(hop.start - (previous?.arrival ?? 0)).toBeGreaterThanOrEqual(0.09 - 0.001);
      }
    }
    expect(schedule.end - schedule.start).toBeLessThanOrEqual(1.600001);
  });

  it("keeps at least a short hold when many dots share the finale", () => {
    const schedule = planHeroRailStaircase(12);
    expect(
      (schedule.hops[1]?.start ?? 0) - (schedule.hops[0]?.arrival ?? 0),
    ).toBeGreaterThanOrEqual(0.05 - 0.001);
    expect(schedule.end - schedule.start).toBeLessThanOrEqual(1.600001);
  });
});
