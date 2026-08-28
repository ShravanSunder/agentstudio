import { readFile, rename, unlink } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest.ts";

const PNG_SIGNATURE_LENGTH = 8;

function hasPngChunk(bytes: Buffer, expectedChunkType: string): boolean {
  let offset = PNG_SIGNATURE_LENGTH;

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

async function rawPixels(assetPath: string): Promise<Buffer> {
  return sharp(assetPath).ensureAlpha().raw().toBuffer();
}

async function stampSrgbProfile(assetPath: string): Promise<"already-stamped" | "stamped"> {
  const sourceBytes = await readFile(assetPath);

  if (hasPngChunk(sourceBytes, "iCCP") || hasPngChunk(sourceBytes, "sRGB")) {
    return "already-stamped";
  }

  const sourcePixels = await rawPixels(assetPath);
  const temporaryPath = `${assetPath}.srgb-${process.pid}.png`;

  try {
    await sharp(assetPath).withMetadata({ icc: "srgb" }).png().toFile(temporaryPath);

    const stampedPixels = await rawPixels(temporaryPath);
    if (!sourcePixels.equals(stampedPixels)) {
      throw new Error(`${assetPath}: sRGB profile stamping changed product pixels`);
    }

    await rename(temporaryPath, assetPath);
    return "stamped";
  } catch (error: unknown) {
    await unlink(temporaryPath).catch((): undefined => undefined);
    throw error;
  }
}

const manifestUrl = new URL("../src/content/website-capture-manifest.ts", import.meta.url);
const requestedAssetPaths = process.argv.slice(2);
const assetPaths =
  requestedAssetPaths.length > 0
    ? requestedAssetPaths
    : websiteCaptureSuite.captures.map((capture): string =>
        fileURLToPath(new URL(capture.assetPath, manifestUrl)),
      );

const profileResults = await Promise.all(
  assetPaths.map(
    async (assetPath): Promise<{ readonly assetPath: string; readonly result: string }> => ({
      assetPath,
      result: await stampSrgbProfile(assetPath),
    }),
  ),
);

for (const { assetPath, result } of profileResults) {
  console.log(`${result}: ${assetPath}`);
}
