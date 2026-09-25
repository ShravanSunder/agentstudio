import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { TopologyEndObservation } from "./topology-end-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyTopologyEnd(
      pageUrl: string,
      widths: readonly number[],
    ): Promise<TopologyEndObservation[]>;
  }
}

describe("where the rail ends on the home page", () => {
  it("ends halfway between the last glass and CTA icon at every width", async () => {
    // Act
    const observations = await commands.verifyTopologyEnd(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );

    // Assert
    for (const observation of observations) {
      const expectedMidpoint = (observation.lastGlassBottom + observation.ctaIconTop) / 2;
      expect(Math.abs(observation.endNodeY - expectedMidpoint)).toBeLessThanOrEqual(1);
      expect(observation.hasEndMark).toBe(true);
      expect(observation.lowestRailY).toBeLessThanOrEqual(observation.endNodeY + 0.01);
      expect(observation.pointsOverEndContent).toBe(0);
    }
  });
});
