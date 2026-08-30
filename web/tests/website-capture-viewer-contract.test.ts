import { describe, expect, it } from "vitest";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest";

describe("website capture expanded-view contract", () => {
  it("provides full-resolution viewer masters only for active still stories", () => {
    const captureById = new Map(
      websiteCaptureSuite.captures.map((capture) => [capture.id, capture] as const),
    );
    const viewerCaptureIds = websiteCaptureSuite.captures
      .filter((capture) => "viewerAssetPath" in capture)
      .map((capture) => capture.id);

    expect(viewerCaptureIds).toEqual([
      "parallel-work",
      "watch-folder",
      "files",
      "quick-find",
      "review",
      "sidebar-navigation",
      "task-drawer-tools",
      "git-context-files",
    ]);

    for (const captureId of viewerCaptureIds) {
      expect(captureById.get(captureId)).toMatchObject({
        viewerPixelSize: [2560, 1600],
      });
      expect(captureById.get(captureId)).toHaveProperty("viewerAssetPath");
      expect(captureById.get(captureId)).toHaveProperty("viewerSourceSha256");
      expect(captureById.get(captureId)).toHaveProperty("viewerWebsiteAssetSha256");
    }

    expect(captureById.get("sidebar-navigation")).toHaveProperty(
      "viewerAssetPath",
      "../assets/captures/sidebar-navigation-master.png",
    );
    expect(captureById.get("task-drawer-tools")).toHaveProperty(
      "viewerAssetPath",
      "../assets/captures/task-drawer-tools-master.png",
    );
    expect(captureById.get("layout-saved")).not.toHaveProperty("viewerAssetPath");
    expect(captureById.get("layout-pane-zoom")).not.toHaveProperty("viewerAssetPath");
  });
});
