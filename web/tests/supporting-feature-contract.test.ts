import { describe, expect, it } from "vitest";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest";
import { marketingCopy } from "../src/marketing-copy";

describe("supporting feature campaign", () => {
  it("keeps five distinct stories in the accepted order", () => {
    expect(marketingCopy.featureDetails.items.map((item) => item.id)).toEqual([
      "persistence",
      "navigation",
      "task-tools",
      "git-context",
      "arrangements",
    ]);
    expect(
      marketingCopy.featureDetails.items.map(
        (item) => `${item.title.beforeAccent}${item.title.accent}${item.title.afterAccent}`,
      ),
    ).toEqual([
      "Close the app, not your sessions.",
      "Find your way around.",
      "Give your tools a home.",
      "Keep your Git close.",
      "Go big on one pane.",
    ]);
  });

  it("provides purpose-made phone evidence for every supporting still", () => {
    const captureById = new Map(
      websiteCaptureSuite.captures.map((capture) => [capture.id, capture] as const),
    );

    for (const captureId of [
      "sidebar-navigation",
      "task-drawer-tools",
      "git-context-files",
      "layout-saved",
      "layout-pane-zoom",
    ] as const) {
      const capture = captureById.get(captureId);
      expect(capture).toBeDefined();
      expect(capture).toHaveProperty("phoneAssetPath");
      expect(capture).toHaveProperty("phoneWebsiteAssetSha256");
    }

    expect(captureById.get("sidebar-navigation")).toHaveProperty("phonePixelSize", [610, 800]);
    expect(captureById.get("task-drawer-tools")).toHaveProperty("phonePixelSize", [1300, 1520]);
    expect(captureById.get("git-context-files")).toHaveProperty("phonePixelSize", [810, 570]);
    expect(captureById.get("layout-saved")).toHaveProperty("phonePixelSize", [640, 400]);
    expect(captureById.get("layout-pane-zoom")).toHaveProperty("phonePixelSize", [640, 400]);
  });
});
