import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { ChapterActivitySample } from "./chapter-activity-browser-command";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyChapterActivity(
      pageUrl: string,
      width: number,
      height: number,
    ): Promise<ChapterActivitySample[]>;
  }
}

describe("chapter activity follows the title reading line", () => {
  it.each([
    [1600, 1000],
    [390, 844],
  ])("hands off one playing scene at %ix%i", async (width, height) => {
    const samples = await commands.verifyChapterActivity(
      inject("siteHeaderBrowserTestUrl"),
      width,
      height,
    );
    expect(samples.map((sample) => sample.chapterId)).toEqual([
      "many-agents",
      "context-with-task",
      "many-agents",
      "review",
      "come-back",
    ]);
    for (const sample of samples) {
      expect(sample.playingChapters, `${width}px ${sample.chapterId}`).toEqual([sample.chapterId]);
      expect(sample.sceneState, `${width}px ${sample.chapterId}`).toBe("playing");
    }
    if (width >= 1024)
      expect(samples[1]?.stageVisibleFraction, `${width}px old dead zone`).toBeLessThan(0.6);
    expect(samples[1]?.selectedStep).toBe("task-drawers");
    expect(samples[2]?.selectedStep).toBe("parallel-agents");
  });
});
