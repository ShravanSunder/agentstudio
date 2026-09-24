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
  it("ends at the install row where the gutter has room and above the call to action on phones", async () => {
    // Act
    const observations = await commands.verifyTopologyEnd(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );

    // Assert
    for (const observation of observations) {
      expect(observation.lowestRailY).toBeLessThanOrEqual(observation.endNodeY + 7.5);
      expect(observation.pointsOverEndContent).toBe(0);
      if (observation.width < 620) {
        expect(observation.lowestRailY).toBeLessThan(observation.ctaTop);
      } else {
        expect(Math.abs(observation.endNodeY - observation.installCenterY)).toBeLessThanOrEqual(1);
      }
    }
  });
});
