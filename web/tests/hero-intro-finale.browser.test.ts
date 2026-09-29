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
  it(`seeks the sequential hero finale at ${width}px`, async () => {
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
    expect(at(4.5).claudeProgressOpacities[0]).toBeGreaterThan(0);
    expect(at(5.5).claudeSpinnerVisible).toBe(true);
    expect(observation.directSeekSpinnerVisible).toBe(true);
    expect(at(5.5).codexHeaderVisible).toBe(true);
    expect(at(6.8).readyOpacity).toBe(0);
    expect(at(7.2).readyOpacity).toBe(1);
    expect(at(7.2).installOpacity).toBe(0);
    expect(at(7.22).tokenCount).toBeGreaterThan(0);
    expect(at(7.22).tokenTextOverlaps).toBe(0);
    expect(at(7.5).tokenCount).toBeGreaterThan(0);
    expect(at(7.56).tokenCount).toBeGreaterThan(0);
    expect(at(7.96).tokenCount).toBe(0);
    expect(at(7.5).installOpacity).toBeGreaterThan(0);
    expect(at(7.8).visibleDecodeLines).toBeGreaterThan(0);
    expect(at(8.3).visibleDecodeLines).toBe(0);
    expect(at(8.3).copyOpacity).toBe(1);
    if (width >= 1024) {
      expect(at(8.0).codexTypedText).toBe("");
      expect(at(9.22).codexTypedText).toBe("");
      expect(at(8.82).tokenCount).toBeGreaterThan(0);
      expect(at(8.82).tokenTextOverlaps).toBe(0);
      expect(at(9.72).codexTypedText.length).toBeGreaterThan(0);
      expect(at(9.72).codexTypedText.length).toBeLessThan("map the worktrees".length);
      expect(at(10.3).codexWorkingOpacity).toBeGreaterThan(0);
      expect(at(11.4).worktreeRowOpacities[0]).toBeGreaterThan(0);
      expect(at(11.0).worktreeResultOpacity).toBe(0);
      expect(at("settled").codexWorkingOpacity).toBe(0);
    }
    expect(at(11.3).worktreeRowOpacities.some((opacity) => opacity > 0)).toBe(true);
    expect(at(11.3).worktreeResultOpacity).toBe(0);
    expect(at(12.3).worktreeResultOpacity).toBe(0);
    expect(at(12.8).worktreeResultOpacity).toBeGreaterThan(0.9);
    expect(at(13.1).tokenCount).toBeGreaterThan(0);
    expect(at(13.1).tokenTextOverlaps).toBe(0);
    expect(at(13.1).railBurstTargetDistance).toBeLessThanOrEqual(2);
    expect(at(12.3).railClip).toContain("100%");
    expect(at(13.65).railClip).not.toContain("100%");
    expect(at(12.3).firstPayoff).toBe(0);
    const { staircase } = observation;
    expect(staircase.start).toBeGreaterThanOrEqual(13.55);
    expect(staircase.start - 13.55).toBeLessThanOrEqual(0.05);
    for (const fraction of [0.25, 0.5, 0.75]) {
      const offsets = [7.05, ...(width >= 1024 ? [8.57] : []), 12.65];
      for (const start of offsets) {
        const sample = at(Number((start + fraction * 0.9).toFixed(3)));
        expect(sample.tokenCount, `${width}px burst ${start} at ${fraction}`).toBeGreaterThan(0);
        expect(sample.tokenTextOverlaps, `${width}px burst ${start} at ${fraction}`).toBe(0);
        if (fraction === 0.5)
          expect(
            Math.max(...sample.tokenVisuals.map((token) => token.opacity)),
            `${width}px burst ${start} peak opacity`,
          ).toBeGreaterThanOrEqual(0.85);
        expect(
          sample.tokenVisuals.every(
            (token) => token.fontSize >= 12 && token.fontSize <= 14 && token.weight === "600",
          ),
        ).toBe(true);
        expect(
          sample.tokenVisuals.every((token) =>
            ["#b4c6e4", "#d4bcad", "#bccfb9", "#c9bfd9", "#b5cdd8", "#d6cdb4"].includes(token.fill),
          ),
        ).toBe(true);
      }
    }
    expect(staircase.end - staircase.start).toBeLessThanOrEqual(1.600001);
    const finalHop = staircase.hops.at(-1);
    if (finalHop === undefined) throw new Error("Rail final hop missing");
    expect(at(finalHop.start).heroBranchDashOffset).toBeGreaterThan(0);
    expect(at(staircase.end).heroBranchDashOffset).toBeCloseTo(0, 1);
    expect(at(staircase.end + 0.1).firstPayoff).toBeGreaterThan(0);
    expect(at(staircase.end + 0.1).secondPayoff).toBeGreaterThan(0);
    expect(at("settled").firstPayoff).toBe(1);
    expect(at("settled").payoffOverflow).toBeLessThanOrEqual(0);
    expect(at("settled").worktreeResultOpacity).toBe(1);
    expect(at("settled").resultVisibleInPane).toBe(true);
    expect(at("settled").offscreenRowPaintLeaks).toBe(0);
    expect(observation.scrollProbe.overflow).toBeGreaterThan(0);
    expect(observation.scrollProbe.scrollTop).toBeGreaterThan(0);
    expect(observation.scrollProbe.resultVisible).toBe(true);
    expect(at("settled").railClip).toBe("none");
    expect(at("settled").introDotOpacities.every((opacity) => opacity > 0.9)).toBe(true);
    expect(at("settled").rowOpacity.every((opacity) => opacity === 1)).toBe(true);
    for (const time of [5.5, 10.7, "settled"] as const) {
      expect(
        at(time).transcriptClearances.every((clearance) => clearance >= 20),
        `${time}: pinned clearance`,
      ).toBe(true);
    }
    for (const sample of observation.samples) {
      expect(
        sample.firstVisibleRowTopGaps.every((gap) => gap >= -0.5),
        `${sample.time}: complete first row ${sample.firstVisibleRowTopGaps.join(",")} ${sample.firstVisibleRowDebug.join(" | ")}`,
      ).toBe(true);
      expect(sample.installTransform, `${sample.time}: install transform`).toBe("none");
      expect(sample.realCommandLines, `${sample.time}: command text`).toEqual([
        "$ brew tap ShravanSunder/agentstudio",
        "$ brew install --cask agent-studio",
      ]);
      expect(Math.abs(sample.appTop - at(0).appTop), `${sample.time}: app`).toBeLessThanOrEqual(
        0.5,
      );
      expect(
        Math.abs(sample.windowHeight - at(0).windowHeight),
        `${sample.time}: window`,
      ).toBeLessThanOrEqual(0.5);
      expect(
        Math.abs(sample.chapterNodeY - at(0).chapterNodeY),
        `${sample.time}: rail`,
      ).toBeLessThanOrEqual(0.5);
    }
    expect(observation.resizeRailClip).toBe("none");
    expect(observation.resizeRailStyle).not.toContain("clip-path");
    expect(observation.resizeSceneInlineStyles).toBe(0);
    expect(observation.resizeRailIntroMarkers).toBe(0);
    expect(observation.skipRailClip).toBe("none");
    expect(observation.skipSceneInlineStyles).toBe(0);
    expect(observation.skipRailIntroMarkers).toBe(0);
    expect(observation.skipFinaleOpacity.every((opacity) => opacity === 1)).toBe(true);
    expect(observation.reducedRailClip).toBe("none");
    expect(observation.reducedRailIntroMarkers).toBe(0);
    expect(observation.reducedFinaleOpacity.every((opacity) => opacity === 1)).toBe(true);
  });
}

it("keeps phone worktree rows on one line at approved narrow widths", async () => {
  for (const width of [360, 390, 414]) {
    const observation = await commands.verifyHeroIntroFinale(
      inject("siteHeaderBrowserTestUrl"),
      width,
      844,
    );
    const settled = observation.samples.find((sample) => sample.time === "settled");
    if (settled === undefined) throw new Error("Settled hero sample missing");
    expect(settled.worktreeRowLineCounts).toEqual([1, 1, 1]);
    expect(
      settled.claudeRowLineCounts.every((count) => count <= 1),
      `${width}px wrapped Claude rows: ${settled.wrappedClaudeRows.join(" | ")}`,
    ).toBe(true);
  }
});

it("keeps the hero Codex session in the Agent Studio workspace", async () => {
  const observation = await commands.verifyHeroIntroFinale(
    inject("siteHeaderBrowserTestUrl"),
    1600,
    1000,
  );
  const settled = observation.samples.find((sample) => sample.time === "settled");
  if (settled === undefined) throw new Error("Settled hero sample missing");
  expect(settled.heroText).not.toMatch(/tool-portal|fix\/lease-client/u);
  expect(settled.codexHeaderText).toContain("directory: ~/agent-studio");
  expect(settled.codexFooterText).toContain("main");
  expect(settled.worktreeTexts).toEqual([
    "└ ~/agent-studio  main",
    "└ ~/agent-studio.drawer  drawer-improvements",
    "└ ~/agent-studio.review  review-comments",
  ]);
});

it("clips scrolled transcript rows inside their panes", async () => {
  for (const [width, height] of [
    [1600, 1000],
    [390, 844],
  ] as const) {
    const observation = await commands.verifyHeroIntroFinale(
      inject("siteHeaderBrowserTestUrl"),
      width,
      height,
    );
    const settled = observation.samples.find((sample) => sample.time === "settled");
    if (settled === undefined) throw new Error("Settled hero sample missing");
    expect(settled.offscreenRowPaintLeaks, `${width}px`).toBe(0);
    expect(settled.resultVisibleInPane, `${width}px`).toBe(true);
  }
});

it("reaches stillness by the owner-adjusted 16.5s ceiling", async () => {
  const observation = await commands.verifyHeroIntroFinale(
    inject("siteHeaderBrowserTestUrl"),
    1600,
    1000,
  );
  expect(observation.staircase.end + 0.2).toBeLessThanOrEqual(16.5);
});
