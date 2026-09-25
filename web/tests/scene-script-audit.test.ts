import { describe, expect, it } from "vitest";

import { findForbiddenSceneScriptSyntax } from "../scripts/scene-bundles/scene-script-audit.ts";

describe("scene script audit", () => {
  it("accepts a classic script whose data merely mentions import or fetch", () => {
    // Arrange
    const sceneScript = [
      "(function () {",
      '  var sourceLine = ["keyword", "import type "];',
      "  // fetch nothing; the comment is not code",
      "  window.AgentStudioScenes = { labels: { fetch: 1 } };",
      "})();",
    ].join("\n");

    // Act
    const findings = findForbiddenSceneScriptSyntax(sceneScript);

    // Assert
    expect(findings).toEqual([]);
  });

  it("reports module syntax, network access, and asynchronous setup", () => {
    // Arrange
    const sceneScript = [
      'import { gsap } from "gsap";',
      'const lazyModule = import("./lazy.js");',
      'fetch("/fonts.css");',
      "new XMLHttpRequest();",
      "requestAnimationFrame(() => undefined);",
      "console.log(import.meta.url);",
      "export const sceneModule = {};",
    ].join("\n");

    // Act
    const findings = findForbiddenSceneScriptSyntax(sceneScript);

    // Assert
    expect(findings).toEqual([
      "ImportDeclaration",
      "ImportExpression",
      "fetch",
      "XMLHttpRequest",
      "requestAnimationFrame",
      "import.meta",
      "ExportNamedDeclaration",
    ]);
  });
});
