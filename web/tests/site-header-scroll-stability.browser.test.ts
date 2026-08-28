import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { SiteHeaderScrollStabilityResult } from "./site-header-browser-contract.ts";

declare module "vitest" {
  export interface ProvidedContext {
    siteHeaderBrowserTestUrl: string;
  }
}

declare module "vitest/browser" {
  interface BrowserCommands {
    verifySiteHeaderScrollStability(pageUrl: string): Promise<SiteHeaderScrollStabilityResult>;
  }
}

describe("responsive site header", () => {
  it("settles once in each state without changing its sticky flow height", async () => {
    const result = await commands.verifySiteHeaderScrollStability(
      inject("siteHeaderBrowserTestUrl"),
    );

    expect(result.viewport).toEqual({ height: 844, width: 390 });
    expect(result.floating.visualState).toBe("floating");
    expect(result.floating.scrollY).toBe(33);
    expect(result.resting.visualState).toBe("resting");
    expect(result.resting.scrollY).toBe(0);
    expect(result.floating.anchorHeight).toBeGreaterThan(0);
    expect(result.floating.anchorHeight).toBeCloseTo(result.resting.anchorHeight, 1);
    expect(result.floating.headerWidth).toBeLessThan(result.resting.headerWidth);
    expect(result.floating.headerTop).toBeGreaterThan(result.resting.headerTop);
    expect(result.stateChangeCount).toBe(2);
    expect(result.headerZIndex).toBeGreaterThan(result.frostZIndex);
  });
});
