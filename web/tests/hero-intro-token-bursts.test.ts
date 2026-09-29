import { describe, expect, it } from "vitest";

import {
  heroBurstTokenOpacity,
  pointAlongHeroRoute,
} from "../src/hero-intro/hero-intro-token-bursts";

describe("hero token bursts", () => {
  it("travels each polyline segment by distance and fades before both text endpoints", () => {
    const route = [
      { x: 0, y: 0 },
      { x: 40, y: 0 },
      { x: 40, y: 60 },
    ];
    expect(pointAlongHeroRoute(route, 0.2)).toMatchObject({ x: 20, y: 0 });
    expect(pointAlongHeroRoute(route, 0.7)).toMatchObject({ x: 40, y: 30 });
    expect(heroBurstTokenOpacity(0.08)).toBe(0);
    expect(heroBurstTokenOpacity(0.51)).toBeCloseTo(0.95, 2);
    expect(heroBurstTokenOpacity(0.94)).toBe(0);
    expect(heroBurstTokenOpacity(0.15)).toBeGreaterThan(0);
    expect(heroBurstTokenOpacity(0.9)).toBeGreaterThan(0);
  });
});
