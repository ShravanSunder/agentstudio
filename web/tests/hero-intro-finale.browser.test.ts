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
  it(`seeks the calm hero and in-pane git-tree finale at ${width}px`, async () => {
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
    expect(at(0).firstLine).toBe(0);
    expect(at(0.3).firstLine).toBeGreaterThan(0);
    expect(at(0.8).firstLine).toBe(1);
    expect(at(0.2).secondLine).toBe(0);
    expect(at(0.45).secondLine).toBeGreaterThan(0);
    expect(at(0.9).secondLine).toBe(1);
    expect(at(5.8).firstPayoff).toBe(0);
    expect(at(5.8).secondPayoff).toBe(0);
    expect(at(6.5).firstPayoff).toBeGreaterThan(0);
    expect(at(6.5).secondPayoff).toBeGreaterThan(0);
    expect(at(6.8).firstPayoff).toBe(1);
    expect(at(6.8).secondPayoff).toBe(1);
    expect(at("settled").payoffOverflow).toBeLessThanOrEqual(0);
    for (const sample of observation.samples) {
      expect(sample.installTransform, `${sample.time}: install transform`).toBe("none");
      expect(sample.realCommandLines, `${sample.time}: real command text`).toEqual([
        "$ brew tap ShravanSunder/agentstudio",
        "$ brew install --cask agent-studio",
      ]);
    }
    expect(at(4.3).installOpacity).toBe(0);
    expect(at(4.9).installOpacity).toBe(1);
    expect(at(4.9).visibleDecodeLines).toBe(2);
    expect(at(5.4).visibleDecodeLines).toBe(0);
    expect(at(5.5).copyOpacity).toBe(1);
    expect(at(5.5).railClip).toContain("100%");
    expect(at(5.5).introDotOpacities.length).toBeGreaterThan(1);
    expect(at(5.5).introDotOpacities.every((opacity) => opacity === 0)).toBe(true);
    expect(Math.abs(at(5.85).railRevealY - at(5.85).heroNodeY)).toBeLessThanOrEqual(2);
    const midDots = at(6.25).introDotOpacities;
    expect(midDots[0]).toBeGreaterThan(0.9);
    expect(midDots.at(-1)).toBe(0);
    expect(midDots.findIndex((opacity) => opacity < 0.01)).toBeGreaterThan(0);
    for (const time of [6.1, 6.25, 6.4, 6.63] as const) {
      const dots = at(time).introDotOpacities;
      const firstHidden = dots.findIndex((opacity) => opacity < 0.01);
      if (firstHidden >= 0)
        expect(dots.slice(firstHidden).every((opacity) => opacity < 0.01)).toBe(true);
    }
    if (width >= 1024) {
      expect(at(6.25).forkDashOffsets.length).toBeGreaterThan(0);
      expect(at(6.4).forkDashOffsets[0]).toBeLessThan(at(6.25).forkDashOffsets[0] ?? 0);
      expect(at(6.63).forkDashOffsets[0]).toBeCloseTo(0, 1);
    }
    expect(at(6.63).heroBranchDashOffset).toBeGreaterThan(0);
    expect(at(6.75).heroBranchDashOffset).toBeCloseTo(0, 1);
    expect(at("settled").heroBranchDashOffset).toBeCloseTo(0, 1);
    expect(at(6.75).introDotOpacities.every((opacity) => opacity > 0.9)).toBe(true);
    expect(at(6.4).railClip).not.toBe(at(5.5).railClip);
    expect(at("settled").railClip).toBe("none");
    expect(at(5.5).rowOpacity).toEqual(Array.from({ length: width < 1024 ? 4 : 5 }, () => 0));
    expect(at(5.8).rowOpacity[0]).toBeCloseTo(1, 1);
    expect(at(6.4).rowOpacity.slice(1)).toEqual(width < 1024 ? [0, 1, 0] : [0, 0, 0, 0]);
    expect(at("settled").rowOpacity).toEqual(Array.from({ length: width < 1024 ? 4 : 5 }, () => 1));
    const baseline = at(0);
    for (const time of [3.5, 5.5, 6.5, 6.8, 7.0, "settled"] as const) {
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
    expect(observation.resizeRailIntroMarkers).toBe(0);
    expect(observation.skipRailClip).toBe("none");
    expect(observation.skipSceneInlineStyles).toBe(0);
    expect(observation.skipRailIntroMarkers).toBe(0);
    expect(observation.skipFinaleOpacity).toEqual(
      Array.from({ length: width < 1024 ? 4 : 5 }, () => 1),
    );
    expect(observation.reducedRailClip).toBe("none");
    expect(observation.reducedRailIntroMarkers).toBe(0);
    expect(observation.reducedFinaleOpacity).toEqual(
      Array.from({ length: width < 1024 ? 4 : 5 }, () => 1),
    );
  });
}
