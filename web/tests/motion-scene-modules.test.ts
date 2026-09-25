import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { chapterCatalog } from "../src/chapters/chapter-catalog";
import { sceneIds } from "../src/motion-scenes/scene-contract";
import { resolveSceneModule } from "../src/motion-scenes/scene-registry";

const motionScenesDirectory = fileURLToPath(new URL("../src/motion-scenes/", import.meta.url));

// A scene must be a pure function of timeline time: HyperFrames seeks renders
// out of order, so clocks, frame callbacks, and unseeded randomness are banned.
const bannedSceneApis: readonly { readonly name: string; readonly pattern: RegExp }[] = [
  { name: "requestAnimationFrame", pattern: /\brequestAnimationFrame\b/ },
  { name: "Math.random", pattern: /\bMath\s*\.\s*random\b/ },
  { name: "Date.now", pattern: /\bDate\s*\.\s*now\b/ },
  { name: "performance.now", pattern: /\bperformance\s*\.\s*now\b/ },
  { name: "gsap.utils.random", pattern: /\butils\s*\.\s*random\b/ },
];

function listSceneSourceFiles(directory: string): readonly string[] {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return listSceneSourceFiles(entryPath);
    }
    return /\.(?:ts|astro)$/.test(entry.name) ? [entryPath] : [];
  });
}

// The contract documents the banned names in comments; only code may not use them.
function stripComments(source: string): string {
  return source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
}

describe("motion scene modules", () => {
  it("registers a module for every scene id", () => {
    // Arrange / Act
    const registeredSceneIds = sceneIds.filter(
      (sceneId) => resolveSceneModule(sceneId)?.sceneId === sceneId,
    );

    // Assert
    expect(registeredSceneIds).toEqual([...sceneIds]);
  });

  it("declares exactly its chapter's steps, in catalog order, with one label each", () => {
    for (const chapter of chapterCatalog) {
      if (chapter.stage.kind !== "scene") {
        continue;
      }
      // Arrange
      const sceneModule = resolveSceneModule(chapter.stage.sceneId);

      // Act
      const declaredStepIds = sceneModule?.steps.map((step) => step.stepId);
      const timelineLabels = sceneModule?.steps.map((step) => step.timelineLabel) ?? [];

      // Assert
      expect(declaredStepIds).toEqual(chapter.steps.map((step) => step.id));
      expect(new Set(timelineLabels).size).toBe(timelineLabels.length);
      expect(timelineLabels.every((timelineLabel) => timelineLabel.trim() !== "")).toBe(true);
    }
  });

  it("keeps clocks, frame callbacks, and unseeded randomness out of scene code", () => {
    // Arrange
    const sourceFiles = listSceneSourceFiles(motionScenesDirectory);

    // Act
    const violations = sourceFiles.flatMap((sourceFile) => {
      const code = stripComments(readFileSync(sourceFile, "utf8"));
      return bannedSceneApis
        .filter((bannedApi) => bannedApi.pattern.test(code))
        .map(
          (bannedApi) => `${path.relative(motionScenesDirectory, sourceFile)}: ${bannedApi.name}`,
        );
    });

    // Assert
    expect(sourceFiles.length).toBeGreaterThan(3);
    expect(violations).toEqual([]);
  });
});
