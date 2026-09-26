import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type { ChapterScrollGeometrySample } from "./chapter-scroll-geometry-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyChapterScrollGeometry(request: {
      readonly pageUrl: string;
      readonly width: number;
      readonly height: number;
    }): Promise<ChapterScrollGeometrySample[]>;
  }
}

describe("chapter scroll geometry", () => {
  for (const [width, height] of [
    [1600, 1000],
    [390, 844],
  ] as const) {
    it(`moves every chapter as one unit and keeps the rail attached at ${width}px`, async () => {
      const samples = await commands.verifyChapterScrollGeometry({
        pageUrl: inject("siteHeaderBrowserTestUrl"),
        width,
        height,
      });
      expect(samples).toHaveLength(15);
      for (let chapterIndex = 0; chapterIndex < 5; chapterIndex += 1) {
        const chapterSamples = samples.slice(chapterIndex * 3, chapterIndex * 3 + 3);
        const baseline = chapterSamples[0];
        if (baseline === undefined) throw new Error("Chapter has no scroll baseline");
        for (const sample of chapterSamples) {
          expect(sample.chapterId).toBe(baseline.chapterId);
          expect(sample.glassTransform).toBe("none");
          expect(sample.glassLiftValue).toBeCloseTo(sample.groupLiftValue, 2);
          expect(
            sample.branchEdgeError,
            `${width} ${sample.chapterId} at ${sample.scrollY}`,
          ).toBeLessThanOrEqual(1);
          expect(sample.branchWithinTarget).toBe(true);
          expect(
            sample.minimumTextClearance,
            `${width} ${sample.chapterId} at ${sample.scrollY}`,
          ).toBeGreaterThanOrEqual(12);
          for (const [gapIndex, gap] of sample.gaps.entries()) {
            expect(
              Math.abs(gap - (baseline.gaps[gapIndex] ?? Number.NaN)),
              `${width} ${sample.chapterId} gap ${gapIndex} at ${sample.scrollY}`,
            ).toBeLessThanOrEqual(0.5);
          }
        }
      }
    });
  }
  for (const [width, height] of [
    [820, 1180],
    [1024, 768],
  ] as const) {
    it(`keeps branch paths at least 12px from chapter text at ${width}px`, async () => {
      const samples = await commands.verifyChapterScrollGeometry({
        pageUrl: inject("siteHeaderBrowserTestUrl"),
        width,
        height,
      });
      for (const sample of samples) {
        expect(
          sample.minimumTextClearance,
          `${width} ${sample.chapterId} at ${sample.scrollY}`,
        ).toBeGreaterThanOrEqual(12);
      }
    });
  }
});
