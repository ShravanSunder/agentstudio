import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type {
  HeroLayoutObservation,
  HeroPlaybackObservation,
  HeroShiftObservation,
} from "./hero-intro-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyHeroIntroLayout(
      pageUrl: string,
      viewports: readonly { readonly width: number; readonly height: number }[],
    ): Promise<HeroLayoutObservation[]>;
    verifyHeroIntroPlayback(pageUrl: string): Promise<HeroPlaybackObservation>;
    verifyHeroIntroShift(
      pageUrl: string,
      width: number,
      height: number,
    ): Promise<HeroShiftObservation[]>;
  }
}

const viewports = [
  { width: 390, height: 844 },
  { width: 820, height: 1180 },
  { width: 1024, height: 768 },
  { width: 1280, height: 800 },
  { width: 1366, height: 768 },
  { width: 1440, height: 900 },
  { width: 1512, height: 982 },
  { width: 1600, height: 1000 },
  { width: 1728, height: 1117 },
  { width: 1920, height: 1080 },
  { width: 2560, height: 1440 },
] as const;

describe("hero intro", () => {
  it("keeps the settled terminal, install box and canvas correct at every approved size", async () => {
    const observations = await commands.verifyHeroIntroLayout(
      inject("siteHeaderBrowserTestUrl"),
      viewports,
    );
    for (const observation of observations) {
      expect(observation.rowsInsideWindow, observation.viewport).toBe(true);
      expect(
        observation.installBottom,
        `${observation.viewport}: headline ${observation.headlineBottom}, column ${observation.columnTop}, root ${observation.rootTop}, window ${observation.windowTop}-${observation.windowBottom}`,
      ).toBeLessThanOrEqual(Number(observation.viewport.split("x")[1]));
      expect(
        Math.abs(observation.windowLeft - observation.appLeft),
        observation.viewport,
      ).toBeLessThanOrEqual(1);
      expect(
        Math.abs(observation.windowRight - observation.appRight),
        observation.viewport,
      ).toBeLessThanOrEqual(1);
      expect(observation.cursorCount, observation.viewport).toBe(1);
      expect(
        observation.documentWidth,
        `${observation.viewport}: ${observation.overflowElements.join(", ")}`,
      ).toBe(observation.viewportWidth);
      expect(observation.codexVisible, observation.viewport).toBe(
        Number(observation.viewport.split("x")[0]) >= 1024,
      );
      expect(observation.canvasColor, observation.viewport).toBe("rgb(25, 27, 31)");
      expect(observation.installCenterOffset, observation.viewport).toBeLessThanOrEqual(1);
      expect(observation.captionTop - observation.appBottom, observation.viewport).toBeCloseTo(
        12,
        0,
      );
      expect(
        Math.abs(observation.captionLeft - observation.appLeft),
        observation.viewport,
      ).toBeLessThanOrEqual(1);
      expect(
        Math.abs(observation.captionRight - observation.appRight),
        observation.viewport,
      ).toBeLessThanOrEqual(1);
      expect(observation.captionRadius, observation.viewport).toBe("20px");
      expect(observation.descriptionTop).toBeGreaterThan(observation.captionTop);
      expect(
        observation.paintedStackTop - observation.headlineBottom,
        observation.viewport,
      ).toBeGreaterThanOrEqual(observation.viewportWidth < 620 ? 32 : 48);
      expect(observation.visibleBashRows, observation.viewport).toBe(1);
      if (observation.viewport === "1600x1000" || observation.viewport === "390x844") {
        for (const [index, expectedAngle] of [-7, -14, -21].entries()) {
          expect(observation.stackAngles[index], observation.viewport).toBeCloseTo(
            expectedAngle,
            1,
          );
        }
        const phone = observation.viewport === "390x844";
        expect(observation.stackPeekLeft, observation.viewport).toBeGreaterThanOrEqual(
          phone ? 12 : 30,
        );
        expect(observation.stackPeekLeft, observation.viewport).toBeLessThanOrEqual(
          phone ? 16 : 40,
        );
        expect(observation.stackPeekTop, observation.viewport).toBeGreaterThanOrEqual(
          phone ? 12 : 30,
        );
        expect(observation.stackPeekTop, observation.viewport).toBeLessThanOrEqual(phone ? 16 : 40);
      }
      if (observation.viewport === "820x1180") {
        expect(observation.earlierExchangeVisible).toBe(true);
      }
    }
  });

  it.each([
    [1600, 1000],
    [390, 844],
  ])(
    "keeps the window, image and rail fixed throughout playback at %ix%i",
    async (width, height) => {
      const samples = await commands.verifyHeroIntroShift(
        inject("siteHeaderBrowserTestUrl"),
        width,
        height,
      );
      expect(samples.map((sample) => sample.time)).toEqual([0, 3.5, 4.2, 4.6, "settled"]);
      const baseline = samples[0];
      if (baseline === undefined) throw new Error("Missing intro baseline");
      for (const sample of samples) {
        expect(
          Math.abs(sample.appTop - baseline.appTop),
          `${width}: app at ${sample.time}`,
        ).toBeLessThanOrEqual(0.5);
        expect(
          Math.abs(sample.windowHeight - baseline.windowHeight),
          `${width}: window at ${sample.time}`,
        ).toBeLessThanOrEqual(0.5);
        expect(
          Math.abs(sample.chapterNodeY - baseline.chapterNodeY),
          `${width}: rail at ${sample.time}`,
        ).toBeLessThanOrEqual(0.5);
      }
    },
  );

  it("settles once on resize or keydown and leaves CSS in charge of the final layout", async () => {
    const observation = await commands.verifyHeroIntroPlayback(inject("siteHeaderBrowserTestUrl"));
    expect(observation.midIntroWasPlaying).toBe(true);
    for (const [index, expectedAngle] of [-7, -14, -21].entries()) {
      expect(observation.fanAnglesAtEnd[index]).toBeCloseTo(expectedAngle, 1);
    }
    expect(observation.fourthAngleAtEnd).toBeCloseTo(0, 1);
    expect(observation.midIntroHorizontalOverflow).toBeLessThanOrEqual(0);
    expect(observation.resizeSettledEvents).toBe(1);
    expect(observation.resizeProgress).toBe(1);
    expect(observation.resizeInlineStyles, observation.resizeInlineStyleElements.join("\n")).toBe(
      0,
    );
    expect(observation.resizeFourthPlanes).toBe(0);
    expect(observation.reducedMotionCreatedTimeline).toBe(false);
    expect(observation.keydownSettledEvents).toBe(1);
    expect(observation.afterSecondResizeInlineStyles).toBe(0);
    for (const [actual, expected] of [
      [observation.resizedWindow, observation.freshNarrowWindow],
      [observation.afterSecondResizeWindow, observation.freshWideWindow],
    ] as const) {
      expect(Math.abs(actual.left - expected.left)).toBeLessThanOrEqual(1);
      expect(Math.abs(actual.top - expected.top)).toBeLessThanOrEqual(1);
      expect(Math.abs(actual.width - expected.width)).toBeLessThanOrEqual(1);
      expect(Math.abs(actual.height - expected.height)).toBeLessThanOrEqual(1);
    }
  });
});
