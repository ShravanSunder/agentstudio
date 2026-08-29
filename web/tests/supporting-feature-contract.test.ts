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
      "Close the app without stopping your persistent sessions",
      "Find your way around",
      "Give your tools a home",
      "Keep your Git close",
      "Go big on one pane",
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

    expect(captureById.get("sidebar-navigation")).toMatchObject({
      desktopPixelSize: [1740, 1088],
      phonePixelSize: [707, 560],
      projectionPolicy: "purpose-crop",
      focusRegion: null,
    });
    expect(captureById.get("task-drawer-tools")).toMatchObject({
      desktopPixelSize: [2560, 1400],
      phonePixelSize: [2300, 1450],
      projectionPolicy: "purpose-crop",
      focusRegion: null,
    });
    expect(captureById.get("git-context-files")).toHaveProperty("phonePixelSize", [810, 570]);
    expect(captureById.get("layout-saved")).toHaveProperty("phonePixelSize", [640, 400]);
    expect(captureById.get("layout-pane-zoom")).toHaveProperty("phonePixelSize", [640, 400]);
    expect(captureById.get("layout-saved")).toHaveProperty(
      "alternativeText",
      "Agent Studio with the named Layout 1 active.",
    );
    expect(marketingCopy.featureDetails.items.at(-1)).toHaveProperty(
      "savedArrangementImageDescription",
      "Agent Studio with the named Layout 1 active.",
    );
  });
});
