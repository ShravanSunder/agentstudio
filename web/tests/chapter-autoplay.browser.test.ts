import { expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type {
  ChapterAutoplayObservation,
  ChapterClickObservation,
} from "./chapter-autoplay-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyChapterAutoplayAtNaturalFraming(
      pageUrl: string,
      width: number,
      height: number,
    ): Promise<ChapterAutoplayObservation>;
    verifyChapterSceneClicks(
      pageUrl: string,
      width: number,
      height: number,
    ): Promise<ChapterClickObservation[]>;
  }
}

for (const [width, height] of [
  [1600, 1000],
  [390, 844],
] as const) {
  it(`changes the visible scene for each clicked step and holds a manual choice at ${width}px`, async () => {
    const samples = await commands.verifyChapterSceneClicks(
      inject("siteHeaderBrowserTestUrl"),
      width,
      height,
    );
    expect(samples.map((sample) => sample.selectedStepId)).toEqual([
      "parallel-agents",
      "watch-folders",
      "navigation",
    ]);
    expect(samples.every((sample) => sample.sceneState === "paused")).toBe(true);
    expect(new Set(samples.map((sample) => sample.stageImageHash)).size).toBe(3);
  });
}

for (const [width, height] of [
  [1024, 768],
  [1280, 800],
  [1600, 1000],
] as const) {
  it(`advances chapter autoplay with the naturally framed title and glass at ${width}px`, async () => {
    const observation = await commands.verifyChapterAutoplayAtNaturalFraming(
      inject("siteHeaderBrowserTestUrl"),
      width,
      height,
    );
    expect(observation.stageVisibleFraction).toBeGreaterThanOrEqual(0.6);
    expect(observation.selectedStep).not.toBe("parallel-agents");
    expect(observation.sceneState).toBe("playing");
  });
}
