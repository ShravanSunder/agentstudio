import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

import sharp, { type Sharp } from "sharp";
import { describe, expect, it } from "vitest";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest";

const manifestUrl = new URL("../src/content/website-capture-manifest.ts", import.meta.url);

function sha256(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

async function decodedRgba(image: Sharp): Promise<Buffer> {
  return image.ensureAlpha().raw().toBuffer();
}

describe("phone crops cut from approved masters", () => {
  it("shows exactly the master's pixels inside the recorded crop box", async () => {
    // Arrange
    const croppedRecords = websiteCaptureSuite.captures.filter(
      (capture) => "phoneProjection" in capture && "phoneAssetPath" in capture,
    );
    expect(croppedRecords.map((capture) => capture.id)).toEqual(["quick-find"]);

    for (const capture of croppedRecords) {
      if (!("phoneProjection" in capture) || !("phoneAssetPath" in capture)) {
        continue;
      }
      const { cropBox, decodedRgbaSha256, masterSha256 } = capture.phoneProjection;
      const masterBytes = await readFile(new URL(capture.assetPath, manifestUrl));
      const cropBytes = await readFile(new URL(capture.phoneAssetPath, manifestUrl));

      // Act
      const masterRegion = await decodedRgba(
        sharp(masterBytes).extract({
          left: cropBox.x,
          top: cropBox.y,
          width: cropBox.width,
          height: cropBox.height,
        }),
      );
      const cropPixels = await decodedRgba(sharp(cropBytes));

      // Assert
      expect(sha256(masterBytes), capture.id).toBe(masterSha256);
      expect(sha256(masterRegion), capture.id).toBe(decodedRgbaSha256);
      expect(sha256(cropPixels), capture.id).toBe(decodedRgbaSha256);
    }
  });
});
