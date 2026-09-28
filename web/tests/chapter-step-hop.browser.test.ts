import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { StepHopObservation } from "./chapter-step-hop-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyChapterStepHop(pageUrl: string, width: number): Promise<StepHopObservation>;
    verifyReducedMotionStepLine(
      pageUrl: string,
      width: number,
    ): Promise<{ readonly ringHidden: boolean; readonly animationCount: number }>;
  }
}

for (const width of [390, 1600]) {
  it(`keeps the step line still and hides its ring under reduced motion at ${width}px`, async () => {
    const result = await commands.verifyReducedMotionStepLine(
      inject("siteHeaderBrowserTestUrl"),
      width,
    );
    expect(result.ringHidden).toBe(true);
    expect(result.animationCount).toBe(0);
  });
}

for (const width of [390, 1600]) {
  it(`shows a seekable countdown and a 250ms commit hop at ${width}px`, async () => {
    const result = await commands.verifyChapterStepHop(inject("siteHeaderBrowserTestUrl"), width);
    expect(result.ringFraction).toBeCloseTo(0.5, 1);
    expect(result.pausedState).toBe("paused");
    expect(result.pauseGlyphVisible).toBe(true);
    expect(result.previewCount).toBe(1);
    expect(result.previewCountAfterFinish).toBe(0);
    expect(result.travelDuration).toBe(160);
    expect(result.branchDrawEnd).toBe(220);
    expect(result.labelUnfoldEnd).toBe(250);
    expect(result.newLabelOpacityAtStart).toBe("0");
    expect(result.travelDelta).toBeLessThan(0);
    expect(result.wrapDelta).toBeGreaterThan(0);
    expect(result.layoutShift).toBeLessThanOrEqual(0.5);
    expect(result.resumedState).toBe("playing");
  });
}
