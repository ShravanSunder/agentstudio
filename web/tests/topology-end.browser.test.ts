import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import { marketingCopy } from "../src/marketing-copy";
import type {
  TopologyEndObservation,
  TopologyEndPulseObservation,
} from "./topology-end-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyTopologyEnd(
      pageUrl: string,
      widths: readonly number[],
    ): Promise<TopologyEndObservation[]>;
    verifyTopologyEndPulse(pageUrl: string): Promise<TopologyEndPulseObservation>;
  }
}

describe("where the rail ends on the home page", () => {
  it("pulses the final star action once when the rail finishes", async () => {
    const observation = await commands.verifyTopologyEndPulse(inject("siteHeaderBrowserTestUrl"));
    expect(observation.eventCount).toBe(1);
    expect(observation.pulsed).toBe(true);
    expect(observation.href).toBe(marketingCopy.githubUrl);
    expect(observation.animationName).toBe("final-star-pulse");
    expect(observation.reducedMotionAnimationName).toBe("none");
  });
  it("ends at the Star button after the lanes close below the final glass", async () => {
    const observations = await commands.verifyTopologyEnd(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );
    for (const observation of observations) {
      expect(observation.branchEndX, String(observation.width)).toBeCloseTo(
        observation.buttonLeft,
        0,
      );
      expect(observation.branchEndY, String(observation.width)).toBeCloseTo(
        observation.buttonCenterY,
        0,
      );
      expect(observation.lowestRailY).toBeLessThanOrEqual(observation.buttonCenterY + 0.01);
      expect(observation.terminalNodeCount).toBe(0);
      expect(observation.terminalRouteCount).toBe(1);
      expect(observation.branchViewportMaxFraction).toBeLessThan(0.75);
      expect(observation.minimumCopyClearance).toBeGreaterThanOrEqual(12);
      expect(observation.laneMergeYs).toHaveLength(observation.laneCount);
      for (const mergeY of observation.laneMergeYs) {
        expect(mergeY).toBeGreaterThan(observation.lastGlassBottomY);
        expect(mergeY).toBeLessThan(observation.branchStartY);
      }
    }
  });
});
