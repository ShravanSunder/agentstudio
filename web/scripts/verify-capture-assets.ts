import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

import sharp from "sharp";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest.ts";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const CANONICAL_SRGB_ICC_SHA256 =
  "c56e1685d888f5edb92fe07f2750f387f8fe8e91b32ff8fb0b56bfbbb9458353";

function sha256(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function assertCapture(condition: boolean, message: string): asserts condition {
  if (!condition) {
    throw new Error(message);
  }
}

function hasPngChunk(bytes: Buffer, expectedChunkType: string): boolean {
  let offset = PNG_SIGNATURE.length;

  while (offset + 12 <= bytes.length) {
    const chunkLength = bytes.readUInt32BE(offset);
    const chunkType = bytes.toString("ascii", offset + 4, offset + 8);

    if (chunkType === expectedChunkType) {
      return true;
    }

    offset += 12 + chunkLength;
  }

  return false;
}

async function verifyCaptureAssets(): Promise<void> {
  const manifestUrl = new URL("../src/content/website-capture-manifest.ts", import.meta.url);
  let responsiveAssetCount = 0;
  let viewerAssetCount = 0;

  await Promise.all(
    websiteCaptureSuite.captures.map(async (capture): Promise<void> => {
      const assetUrl = new URL(capture.assetPath, manifestUrl);
      const bytes = await readFile(assetUrl);
      const metadata = await sharp(bytes).metadata();
      const desktopPixelSize =
        "desktopPixelSize" in capture ? capture.desktopPixelSize : websiteCaptureSuite.pixelSize;
      const hasCanonicalSrgbChunk = hasPngChunk(bytes, "sRGB") && !hasPngChunk(bytes, "iCCP");
      const hasCanonicalSrgbIcc =
        hasPngChunk(bytes, "iCCP") &&
        metadata.icc !== undefined &&
        sha256(metadata.icc) === CANONICAL_SRGB_ICC_SHA256;

      assertCapture(
        bytes.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE),
        `${capture.id}: asset is not a PNG`,
      );
      assertCapture(
        bytes.readUInt32BE(16) === desktopPixelSize[0],
        `${capture.id}: width does not match the capture suite`,
      );
      assertCapture(
        bytes.readUInt32BE(20) === desktopPixelSize[1],
        `${capture.id}: height does not match the capture suite`,
      );
      assertCapture(
        hasCanonicalSrgbChunk || hasCanonicalSrgbIcc,
        `${capture.id}: canonical sRGB profile identity is missing`,
      );
      assertCapture(
        sha256(bytes) === capture.websiteAssetSha256,
        `${capture.id}: SHA-256 does not match the checked-in projection`,
      );

      if ("phoneAssetPath" in capture && "phoneWebsiteAssetSha256" in capture) {
        const phoneBytes = await readFile(new URL(capture.phoneAssetPath, manifestUrl));
        const phoneMetadata = await sharp(phoneBytes).metadata();
        const phonePixelSize =
          "phonePixelSize" in capture ? capture.phonePixelSize : ([1280, 1600] as const);
        const phoneHasCanonicalSrgbChunk =
          hasPngChunk(phoneBytes, "sRGB") && !hasPngChunk(phoneBytes, "iCCP");
        const phoneHasCanonicalSrgbIcc =
          hasPngChunk(phoneBytes, "iCCP") &&
          phoneMetadata.icc !== undefined &&
          sha256(phoneMetadata.icc) === CANONICAL_SRGB_ICC_SHA256;

        assertCapture(
          phoneBytes.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE),
          `${capture.id} phone: asset is not a PNG`,
        );
        assertCapture(
          phoneBytes.readUInt32BE(16) === phonePixelSize[0] &&
            phoneBytes.readUInt32BE(20) === phonePixelSize[1],
          `${capture.id} phone: dimensions must be ${phonePixelSize[0]}×${phonePixelSize[1]}`,
        );
        assertCapture(
          phoneHasCanonicalSrgbChunk || phoneHasCanonicalSrgbIcc,
          `${capture.id} phone: canonical sRGB profile identity is missing`,
        );
        assertCapture(
          sha256(phoneBytes) === capture.phoneWebsiteAssetSha256,
          `${capture.id} phone: SHA-256 does not match the checked-in projection`,
        );
        responsiveAssetCount += 1;
      }

      if ("viewerAssetPath" in capture && "viewerWebsiteAssetSha256" in capture) {
        const viewerBytes = await readFile(new URL(capture.viewerAssetPath, manifestUrl));
        const viewerMetadata = await sharp(viewerBytes).metadata();
        const viewerPixelSize =
          "viewerPixelSize" in capture ? capture.viewerPixelSize : websiteCaptureSuite.pixelSize;
        const viewerHasCanonicalSrgbChunk =
          hasPngChunk(viewerBytes, "sRGB") && !hasPngChunk(viewerBytes, "iCCP");
        const viewerHasCanonicalSrgbIcc =
          hasPngChunk(viewerBytes, "iCCP") &&
          viewerMetadata.icc !== undefined &&
          sha256(viewerMetadata.icc) === CANONICAL_SRGB_ICC_SHA256;

        assertCapture(
          viewerBytes.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE),
          `${capture.id} viewer: asset is not a PNG`,
        );
        assertCapture(
          viewerBytes.readUInt32BE(16) === viewerPixelSize[0] &&
            viewerBytes.readUInt32BE(20) === viewerPixelSize[1],
          `${capture.id} viewer: dimensions must be ${viewerPixelSize[0]}×${viewerPixelSize[1]}`,
        );
        assertCapture(
          viewerHasCanonicalSrgbChunk || viewerHasCanonicalSrgbIcc,
          `${capture.id} viewer: canonical sRGB profile identity is missing`,
        );
        assertCapture(
          sha256(viewerBytes) === capture.viewerWebsiteAssetSha256,
          `${capture.id} viewer: SHA-256 does not match the checked-in projection`,
        );
        viewerAssetCount += 1;
      }
    }),
  );

  console.log(
    `Verified ${websiteCaptureSuite.captures.length} website capture masters, ${responsiveAssetCount} responsive crops, and ${viewerAssetCount} expanded-view masters.`,
  );
}

await verifyCaptureAssets();
