import { describe, expect, inject, it } from "vitest";
import { commands } from "vitest/browser";

import type {
  ChapterStepRowObservation,
  ChapterTitleAnchorObservation,
} from "./chapter-surface-browser-command.ts";

declare module "vitest/browser" {
  interface BrowserCommands {
    verifyChapterTitleAnchors(
      pageUrl: string,
      widths: readonly number[],
    ): Promise<ChapterTitleAnchorObservation[]>;
    verifyChapterStepRow(request: {
      readonly pageUrl: string;
      readonly width: number;
      readonly chapterId: string;
    }): Promise<ChapterStepRowObservation>;
  }
}

const chapterWithSteps = "many-agents";

describe("chapter surfaces on the home page", () => {
  it("anchors each chapter on its title, with no eyebrow, and levels the rail node with the title's first line", async () => {
    // Act
    const observations = await commands.verifyChapterTitleAnchors(
      inject("siteHeaderBrowserTestUrl"),
      [390, 1280, 1920],
    );

    // Assert
    expect(observations.length).toBeGreaterThan(0);
    for (const observation of observations) {
      expect(observation.anchorTagName).toBe("H2");
      expect(observation.eyebrowCount).toBe(0);
      expect(
        Math.abs(observation.nodeCenterY - observation.titleFirstLineCenterY),
      ).toBeLessThanOrEqual(1);
    }
  });

  for (const width of [390, 800]) {
    it(`stacks title, stage, and a horizontal dot row of steps in one glass at ${width}px`, async () => {
      // Act
      const observation = await commands.verifyChapterStepRow({
        pageUrl: inject("siteHeaderBrowserTestUrl"),
        width,
        chapterId: chapterWithSteps,
      });

      // Assert: one glass holds the title, then the stage, then the steps.
      const layout = observation.glassLayout;
      expect(layout.titleInGlass).toBe(true);
      expect(layout.stageInGlass).toBe(true);
      expect(layout.stepListInGlass).toBe(true);
      expect(layout.title.top).toBeGreaterThan(layout.glass.top);
      expect(layout.stage.top).toBeGreaterThanOrEqual(layout.title.bottom);
      expect(layout.stepList.top).toBeGreaterThanOrEqual(layout.stage.bottom);
      expect(layout.stepList.bottom).toBeLessThanOrEqual(layout.glass.bottom);
      expect(layout.stepList.left).toBeGreaterThanOrEqual(layout.glass.left);
      // Autoplay still measures the stage alone.
      expect(layout.playbackStageCount).toBe(1);
      expect(layout.playbackStageIsStage).toBe(true);
      // The rail's branch ends on the glass's top edge, clear of its corner.
      expect(layout.portNodeCount).toBe(0);
      expect(Math.abs(layout.branchEndpoint.y - layout.glass.top)).toBeLessThanOrEqual(1);
      expect(layout.branchEndpoint.x - layout.glass.left).toBeGreaterThanOrEqual(16 + 8);

      // A horizontal tablist of dots on one line, each a real target.
      expect(observation.role).toBe("tablist");
      expect(observation.orientation).toBe("horizontal");
      const [first, second, third] = observation.tabs;
      if (first === undefined || second === undefined || third === undefined) {
        throw new Error("The chapter has fewer than three steps");
      }
      for (const tab of observation.tabs) {
        expect(Math.abs(tab.centerY - first.centerY)).toBeLessThanOrEqual(1);
        expect(tab.width).toBeGreaterThanOrEqual(24);
        expect(tab.height).toBeGreaterThanOrEqual(24);
        expect(tab.accessibleName).toBe(observation.labels[tab.stepId]);
        expect(tab.labelVisible).toBe(false);
      }
      expect(second.centerX).toBeGreaterThan(first.centerX + 24);
      expect(third.centerX).toBeGreaterThan(second.centerX + 24);

      // Only the current step's label and description show below the row.
      const labelOf = (stepId: string): string => observation.labels[stepId] ?? "";
      expect(observation.initial.visiblePanelIds).toEqual([first.stepId]);
      expect(observation.initial.visibleText).toContain(labelOf(first.stepId));
      expect(observation.initial.visibleText).not.toContain(labelOf(second.stepId));

      // The scene advancing and the arrow keys switch it; focus follows the keys.
      expect(observation.afterSceneAdvance.visiblePanelIds).toEqual([second.stepId]);
      expect(observation.afterSceneAdvance.visibleText).toContain(labelOf(second.stepId));
      expect(observation.afterArrowRight.visiblePanelIds).toEqual([third.stepId]);
      expect(observation.afterArrowRight.visibleText).toContain(labelOf(third.stepId));
      expect(observation.afterArrowRight.focusedStepId).toBe(third.stepId);
      expect(observation.afterHome.visiblePanelIds).toEqual([first.stepId]);
      expect(observation.afterHome.focusedStepId).toBe(first.stepId);
      const last = observation.tabs.at(-1);
      expect(observation.afterEnd.visiblePanelIds).toEqual([last?.stepId]);
      expect(observation.afterEnd.focusedStepId).toBe(last?.stepId);

      // Without JavaScript the first step shows.
      expect(observation.withoutScript.visiblePanelIds).toEqual([first.stepId]);
      expect(observation.withoutScript.visibleText).toContain(labelOf(first.stepId));
    });
  }

  it("keeps the vertical in-glass step list on wide screens", async () => {
    // Act
    const observation = await commands.verifyChapterStepRow({
      pageUrl: inject("siteHeaderBrowserTestUrl"),
      width: 1280,
      chapterId: chapterWithSteps,
    });

    // Assert
    expect(observation.orientation).toBe("vertical");
    const [first, second] = observation.tabs;
    if (first === undefined || second === undefined) {
      throw new Error("The chapter has fewer than two steps");
    }
    expect(Math.abs(second.centerX - first.centerX)).toBeLessThanOrEqual(1);
    expect(second.centerY).toBeGreaterThan(first.centerY);
    for (const tab of observation.tabs) {
      expect(tab.labelVisible).toBe(true);
      expect(tab.accessibleName).toBe(observation.labels[tab.stepId]);
    }
    // The panel carries only the description; the label lives in the list.
    expect(observation.initial.visiblePanelIds).toEqual([first.stepId]);
    expect(observation.initial.visibleText).not.toContain(observation.labels[first.stepId] ?? "");
    expect(observation.afterArrowRight.focusedStepId).toBe(observation.tabs[2]?.stepId);
  });
});
