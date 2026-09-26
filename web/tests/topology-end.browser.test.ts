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
  it("ends at the final glass center with no path below the terminal node", async () => {
    const observations = await commands.verifyTopologyEnd(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );
    for (const observation of observations) {
      expect(observation.endNodeY, String(observation.width)).toBeCloseTo(
        observation.lastGlassCenterY,
        0,
      );
      expect(observation.lowestRailY).toBeLessThanOrEqual(observation.endNodeY + 0.01);
      expect(observation.ctaEndMarkers).toBe(0);
      expect(observation.terminalHalo).toBe(true);
      expect(observation.haloAnimationCount).toBe("1");
      if (observation.laneCount > 0) {
        expect(observation.endKind).toBe("merge");
        expect(observation.mergeRing).toBe(true);
        expect(observation.mergeCore).toBe(true);
      } else {
        expect(observation.endKind).toBe("end");
      }
    }
  });
});
