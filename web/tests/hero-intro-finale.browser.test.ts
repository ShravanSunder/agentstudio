import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { FinaleObservation } from "./hero-intro-finale-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyHeroIntroFinale(
      pageUrl: string,
      width: number,
      height: number,
    ): Promise<FinaleObservation>;
  }
}

for (const [width, height] of [
  [1600, 1000],
  [390, 844],
] as const) {
  it(`seeks the typed hero and in-pane git-tree finale at ${width}px`, async () => {
    const observation = await commands.verifyHeroIntroFinale(
      inject("siteHeaderBrowserTestUrl"),
      width,
      height,
    );
    const at = (time: number | "settled"): FinaleObservation["samples"][number] => {
      const sample = observation.samples.find((item) => item.time === time);
      if (sample === undefined) throw new Error(`Missing ${time}s sample`);
      return sample;
    };
    expect(at(0.2).typedLength).toBeGreaterThan(0);
    expect(at(0.2).typedLength).toBeLessThan(at(0.45).typedLength);
    expect(at(0.45).typedLength).toBe(at(0.45).eyebrowLength);
    expect(at(0.2).cursorOpacity).toBe(1);
    expect(at(0.45).cursorOpacity).toBe(0);
    expect(at(0).firstLine).toBe(0);
    expect(at(0.8).firstLine).toBe(1);
    expect(at(0.45).secondLine).toBe(0);
    expect(at(0.8).secondLine).toBeGreaterThan(0);
    expect(at(3.3).firstPayoff).toBe(0);
    expect(at(3.7).firstPayoff).toBe(1);
    expect(at(7.2).secondPayoff).toBe(0);
    expect(at("settled").secondPayoff).toBe(1);
    expect(at(6.4).railClip).toContain("100%");
    expect(at(7.2).railClip).not.toBe(at(6.4).railClip);
    expect(at(7.2).railRevealY).toBeLessThan(at(7.2).appTop);
    expect(at("settled").railClip).toBe("none");
    expect(at(5.5).rowOpacity).toEqual(Array.from({ length: width < 1024 ? 4 : 5 }, () => 0));
    expect(at(6.1).rowOpacity[0]).toBe(1);
    expect(at(6.4).rowOpacity[1]).toBe(1);
    expect(at(6.8).rowOpacity[width < 1024 ? 2 : 3]).toBe(1);
    expect(at("settled").rowOpacity).toEqual(Array.from({ length: width < 1024 ? 4 : 5 }, () => 1));
    const baseline = at(0);
    for (const time of [3.5, 5.5, 6.5, 7.2, 8.1, "settled"] as const) {
      const sample = at(time);
      expect(Math.abs(sample.appTop - baseline.appTop), `${time}: app`).toBeLessThanOrEqual(0.5);
      expect(
        Math.abs(sample.windowHeight - baseline.windowHeight),
        `${time}: window`,
      ).toBeLessThanOrEqual(0.5);
      expect(
        Math.abs(sample.chapterNodeY - baseline.chapterNodeY),
        `${time}: rail`,
      ).toBeLessThanOrEqual(0.5);
    }
    expect(observation.resizeRailClip).toBe("none");
    expect(observation.resizeRailStyle).not.toContain("clip-path");
    expect(observation.resizeSceneInlineStyles).toBe(0);
    expect(observation.skipRailClip).toBe("none");
    expect(observation.skipSceneInlineStyles).toBe(0);
    expect(observation.skipFinaleOpacity).toEqual(
      Array.from({ length: width < 1024 ? 4 : 5 }, () => 1),
    );
    expect(observation.reducedRailClip).toBe("none");
    expect(observation.reducedFinaleOpacity).toEqual(
      Array.from({ length: width < 1024 ? 4 : 5 }, () => 1),
    );
  });
}
