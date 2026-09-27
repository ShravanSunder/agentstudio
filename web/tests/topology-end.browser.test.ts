import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import { installCommandText, marketingCopy } from "../src/marketing-copy";
import type {
  TopologyEndObservation,
  FinaleBookendObservation,
} from "./topology-end-browser-command.ts";
import { sharpCornerCount } from "./topology-path-corners";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyTopologyEnd(
      pageUrl: string,
      widths: readonly number[],
    ): Promise<TopologyEndObservation[]>;
    verifyFinaleBookend(pageUrl: string): Promise<FinaleBookendObservation>;
  }
}

describe("where the rail ends on the home page", () => {
  it("plays the finale once at the rail end and copies both install commands", async () => {
    const observation = await commands.verifyFinaleBookend(inject("siteHeaderBrowserTestUrl"));
    expect(observation.eventCount).toBe(1);
    for (const [index, angle] of [0, 7, -12].entries())
      expect(observation.transitionalFanAngles[index]).toBeCloseTo(angle, 1);
    expect(observation.transitionalPlaneBorderWidths).toEqual([1, 1, 1, 1]);
    expect(observation.href).toBe(marketingCopy.githubUrl);
    expect(observation.finalState).toBe("settled");
    expect(observation.logoOpacity).toBe("1");
    expect(observation.traceOpacity).toBe("0.6");
    expect(observation.starFillOpacity).toBe("1");
    expect(observation.railStartFraction).toBeCloseTo(1, 1);
    expect(observation.railArrivalFraction).toBeCloseTo(0, 1);
    expect(observation.nodeStartOpacity).toBe("0");
    expect(observation.nodeArrivalOpacity).toBe("1");
    expect(observation.sectionHeightDelta).toBeCloseTo(0, 1);
    expect(observation.footerTopDelta).toBeCloseTo(0, 1);
    expect(observation.oldInstallBoxCount).toBe(0);
    expect(observation.ctaParagraphCount).toBe(1);
    expect(observation.splitPillCount).toBe(1);
    expect(observation.starText).toContain(marketingCopy.finalCallToAction.starOnGitHub);
    expect(observation.copyText).toContain(marketingCopy.finalCallToAction.copyInstall);
    expect(observation.copiedText).toBe(installCommandText);
    expect(observation.copiedLabel).toBe(marketingCopy.finalCallToAction.copiedInstall);
    expect(observation.phoneOneRow).toBe(true);
    expect(observation.phoneShortLabels).toBe(true);
    expect(observation.phoneOverflow).toBeLessThanOrEqual(0);
    expect(observation.reducedMotionState).toBe("settled");
    expect(observation.reducedMotionTimelineCreated).toBe(false);
    expect(observation.reducedMotionLogoOpacity).toBe("1");
    expect(observation.pointerSkipState).toBe("settled");
    expect(observation.resizeSettleState).toBe("settled");
  });
  it("ends at the Star button after the lanes close below the final glass", async () => {
    const observations = await commands.verifyTopologyEnd(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );
    for (const observation of observations) {
      expect(observation.pathData.length, String(observation.width)).toBeGreaterThan(0);
      for (const path of observation.pathData) {
        expect(sharpCornerCount(path.d), `${observation.width}px ${path.kind}: ${path.d}`).toBe(0);
      }
      expect(observation.nodeRightX, String(observation.width)).toBeCloseTo(
        observation.pillLeft,
        0,
      );
      expect(observation.branchEndY, String(observation.width)).toBeCloseTo(
        observation.pillCenterY,
        0,
      );
      expect(observation.lowestRailY).toBeLessThanOrEqual(observation.pillCenterY + 0.01);
      expect(observation.terminalNodeCount).toBe(1);
      expect(observation.terminalRouteCount).toBe(1);
      expect(observation.branchViewportMaxFraction).toBeLessThan(0.75);
      expect(observation.branchColumnSpan, String(observation.width)).toBeLessThanOrEqual(2);
      expect(observation.minimumTitleClearance).toBeGreaterThanOrEqual(12);
      expect(observation.ringRadius).toBe(6);
      expect(observation.coreRadius).toBe(2.5);
      expect(observation.haloRadius).toBe(7);
      expect(observation.ringStroke).toBe("rgb(116, 199, 236)");
      expect(observation.coreFill).toBe("rgb(137, 180, 250)");
      expect(observation.branchStroke).toBe("rgb(116, 199, 236)");
      expect(observation.laneMergeYs).toHaveLength(observation.laneCount);
      for (const mergeY of observation.laneMergeYs) {
        expect(mergeY).toBeGreaterThan(observation.lastGlassBottomY);
        expect(mergeY).toBeLessThan(observation.branchStartY);
      }
    }
  });
});
