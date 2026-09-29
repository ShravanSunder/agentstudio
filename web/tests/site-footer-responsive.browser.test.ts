import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type {
  FooterEndRoomObservation,
  SiteFooterResponsiveLayoutResult,
} from "./site-footer-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifySiteFooterResponsiveLayout(pageUrl: string): Promise<SiteFooterResponsiveLayoutResult>;
    verifyFooterEndRoom(
      pageUrl: string,
      widths: readonly number[],
    ): Promise<FooterEndRoomObservation[]>;
  }
}

describe("responsive product credits footer", () => {
  it("reaches the finale with at most a normal footer gap below the credits", async () => {
    const observations = await commands.verifyFooterEndRoom(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );
    for (const observation of observations) {
      expect(observation.endReached, `${observation.width}px`).toBe(true);
      expect(observation.finaleState, `${observation.width}px`).not.toBe("ready");
      expect(observation.bottomPadding, `${observation.width}px`).toBeLessThanOrEqual(87);
      expect(observation.blankBelowCredits, `${observation.width}px`).toBeLessThanOrEqual(104);
    }
  });
  it("uses one end-aligned desktop row and two centered narrow rows", async () => {
    const result = await commands.verifySiteFooterResponsiveLayout(
      inject("siteHeaderBrowserTestUrl"),
    );

    expect(result.desktop.links[0]?.top).toBeCloseTo(result.desktop.links[1]?.top ?? 0, 1);
    expect(result.desktop.links[1]?.right).toBeCloseTo(result.desktop.footerRight, 1);
    expect(result.desktop.horizontalOverflow).toBe(0);

    expect(result.narrow.links[0]?.top).toBeLessThan(result.narrow.links[1]?.top ?? 0);
    for (const link of result.narrow.links) {
      expect(link.centerX).toBeCloseTo(result.narrow.footerCenterX, 1);
    }
    expect(result.narrow.horizontalOverflow).toBe(0);
  });
});
