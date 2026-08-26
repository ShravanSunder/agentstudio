import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { SiteFooterResponsiveLayoutResult } from "./site-footer-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifySiteFooterResponsiveLayout(pageUrl: string): Promise<SiteFooterResponsiveLayoutResult>;
  }
}

describe("responsive product credits footer", () => {
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
