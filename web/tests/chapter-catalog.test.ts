import { describe, expect, it } from "vitest";

import {
  chapterCatalog,
  chapterIds,
  chapterStepIds,
  isChapterStepId,
} from "../src/chapters/chapter-catalog";
import { websiteCaptureSuite } from "../src/content/website-capture-manifest";
import { sceneIds } from "../src/motion-scenes/scene-contract";
import { resolveSceneModule } from "../src/motion-scenes/scene-registry";

describe("chapter catalog", () => {
  it("tells the five chapters in narrative order with unique ids", () => {
    // Arrange / Act
    const catalogChapterIds = chapterCatalog.map((chapter) => chapter.id);

    // Assert
    expect(catalogChapterIds).toEqual([...chapterIds]);
    expect(new Set(catalogChapterIds).size).toBe(catalogChapterIds.length);
  });

  it("places every workflow step exactly once", () => {
    // Arrange / Act
    const catalogStepIds = chapterCatalog.flatMap((chapter) =>
      chapter.steps.map((step) => step.id),
    );

    // Assert
    expect(catalogStepIds).toEqual([...chapterStepIds]);
    expect(new Set(catalogStepIds).size).toBe(catalogStepIds.length);
    expect(isChapterStepId("review-diff")).toBe(true);
    expect(isChapterStepId("product-plate")).toBe(false);
  });

  it("gives every chapter and step readable copy", () => {
    for (const chapter of chapterCatalog) {
      expect(chapter.title.accent.trim()).not.toBe("");
      expect(chapter.steps.length).toBeGreaterThan(0);
      for (const step of chapter.steps) {
        expect(step.label.trim()).not.toBe("");
        expect(step.description.trim()).not.toBe("");
        expect(step.phoneDescription.trim()).not.toBe("");
      }
    }
  });

  it("keeps the copy-passed chapter titles", () => {
    expect(
      chapterCatalog.map(
        (chapter) =>
          `${chapter.title.beforeAccent}${chapter.title.accent}${chapter.title.afterAccent}`,
      ),
    ).toEqual([
      "Many agents, one map.",
      "Context stays with the task.",
      "Find it, focus it.",
      "Review without leaving the workspace.",
      "Close the app. Agents keep running.",
    ]);
  });

  it("stages chapters one to three as scenes, review as a still, and restore as a video", () => {
    // Arrange / Act
    const stageKinds = chapterCatalog.map((chapter) => chapter.stage.kind);
    const stagedSceneIds = chapterCatalog.flatMap((chapter) =>
      chapter.stage.kind === "scene" ? [chapter.stage.sceneId] : [],
    );

    // Assert
    expect(stageKinds).toEqual(["scene", "scene", "scene", "still", "video"]);
    expect(stagedSceneIds).toEqual([...sceneIds]);
  });

  it("proves the task-drawer chapter with the approved capture's own description", () => {
    // Arrange
    const approvedCapture = websiteCaptureSuite.captures.find(
      (capture) => capture.id === "task-drawer-tools",
    );
    const contextChapter = chapterCatalog.find((chapter) => chapter.id === "context-with-task");

    // Act / Assert
    expect(contextChapter?.stage).toMatchObject({
      kind: "scene",
      proofAlt: approvedCapture?.alternativeText,
    });
    expect(approvedCapture?.alternativeText).toBeTruthy();
  });

  it("keeps each registered scene's steps in the catalog's step order", () => {
    for (const chapter of chapterCatalog) {
      if (chapter.stage.kind !== "scene") {
        continue;
      }
      const sceneModule = resolveSceneModule(chapter.stage.sceneId);
      if (sceneModule === undefined) {
        continue;
      }
      expect(sceneModule.sceneId).toBe(chapter.stage.sceneId);
      expect(sceneModule.steps.map((step) => step.stepId)).toEqual(
        chapter.steps.map((step) => step.id),
      );
    }
  });
});
