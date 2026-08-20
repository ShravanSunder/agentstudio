import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest.ts";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

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

  await Promise.all(
    websiteCaptureSuite.captures.map(async (capture): Promise<void> => {
      const assetUrl = new URL(capture.assetPath, manifestUrl);
      const bytes = await readFile(assetUrl);

      assertCapture(
        bytes.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE),
        `${capture.id}: asset is not a PNG`,
      );
      assertCapture(
        bytes.readUInt32BE(16) === websiteCaptureSuite.pixelSize[0],
        `${capture.id}: width does not match the capture suite`,
      );
      assertCapture(
        bytes.readUInt32BE(20) === websiteCaptureSuite.pixelSize[1],
        `${capture.id}: height does not match the capture suite`,
      );
      assertCapture(
        hasPngChunk(bytes, "iCCP") || hasPngChunk(bytes, "sRGB"),
        `${capture.id}: canonical color-profile marker is missing`,
      );
      assertCapture(
        sha256(bytes) === capture.websiteAssetSha256,
        `${capture.id}: SHA-256 does not match the checked-in projection`,
      );
    }),
  );

  console.log(
    `Verified ${websiteCaptureSuite.captures.length} website capture assets at ${websiteCaptureSuite.pixelSize[0]}×${websiteCaptureSuite.pixelSize[1]}.`,
  );
}

await verifyCaptureAssets();
