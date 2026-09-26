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

  for (const width of [390, 820, 1280, 1600]) {
    it(`puts the horizontal step pill above the glass at ${width}px`, async () => {
      // Act
      const observation = await commands.verifyChapterStepRow({
        pageUrl: inject("siteHeaderBrowserTestUrl"),
        width,
        chapterId: chapterWithSteps,
      });

      // The pill carries the selector; the glass retains title, stage and panels.
      const layout = observation.glassLayout;
      expect(layout.titleInGlass).toBe(true);
      expect(layout.stageInGlass).toBe(true);
      expect(layout.stepListInPill).toBe(true);
      expect(layout.stepPanelsInGlass).toBe(true);
      expect(layout.pillMaterialMatchesHeader).toBe(true);
      expect(layout.pill.bottom + 16).toBeCloseTo(layout.glass.top, 0);
      expect(layout.title.top).toBeGreaterThan(layout.glass.top);
      if (width < 1024) expect(layout.stage.top).toBeGreaterThanOrEqual(layout.title.bottom);
      expect(layout.stepList.top).toBeGreaterThanOrEqual(layout.pill.top);
      expect(layout.stepList.bottom).toBeLessThanOrEqual(layout.pill.bottom);
      // Autoplay still measures the stage alone.
      expect(layout.playbackStageCount).toBe(1);
      expect(layout.playbackStageIsStage).toBe(true);
      // The rail's branch ends at the pill's left-center with no port dot.
      expect(layout.portNodeCount).toBe(0);
      expect(
        Math.abs(layout.branchEndpoint.y - (layout.pill.top + layout.pill.bottom) / 2),
      ).toBeLessThanOrEqual(1);
      expect(Math.abs(layout.branchEndpoint.x - layout.pill.left)).toBeLessThanOrEqual(1);

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
        expect(tab.labelVisible).toBe(width >= 620 || tab.stepId === first.stepId);
      }
      expect(second.centerX).toBeGreaterThan(first.centerX + 24);
      expect(third.centerX).toBeGreaterThan(second.centerX + 24);

      // Only the current panel's description shows in the glass.
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
      for (const [index, snapshot] of observation.afterClicks.entries()) {
        const clicked = observation.tabs[index];
        expect(snapshot.visiblePanelIds).toEqual([clicked?.stepId]);
        expect(snapshot.selectedStepId).toBe(clicked?.stepId);
        expect(snapshot.highlightCenterOffset).toBeLessThanOrEqual(1);
      }

      // Without JavaScript the first step shows.
      expect(observation.withoutScript.visiblePanelIds).toEqual([first.stepId]);
      expect(observation.withoutScript.visibleText).toContain(labelOf(first.stepId));
    });
  }

  it("keeps the wide pill horizontal and the panel in the glass", async () => {
    // Act
    const observation = await commands.verifyChapterStepRow({
      pageUrl: inject("siteHeaderBrowserTestUrl"),
      width: 1280,
      chapterId: chapterWithSteps,
    });

    // Assert
    expect(observation.orientation).toBe("horizontal");
    const [first, second] = observation.tabs;
    if (first === undefined || second === undefined) {
      throw new Error("The chapter has fewer than two steps");
    }
    expect(second.centerX).toBeGreaterThan(first.centerX);
    expect(Math.abs(second.centerY - first.centerY)).toBeLessThanOrEqual(1);
    for (const tab of observation.tabs) {
      expect(tab.labelVisible).toBe(true);
      expect(tab.accessibleName).toBe(observation.labels[tab.stepId]);
    }
    // The panel keeps the current step's label and description under the title.
    expect(observation.initial.visiblePanelIds).toEqual([first.stepId]);
    expect(observation.initial.visibleText).toContain(observation.labels[first.stepId] ?? "");
    expect(observation.afterArrowRight.focusedStepId).toBe(observation.tabs[2]?.stepId);
  });
});
