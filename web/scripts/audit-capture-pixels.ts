import { readFile } from "node:fs/promises";

import sharp from "sharp";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest.ts";

interface RgbaPixel {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
  readonly alpha: number;
}

interface CapturePixelFailure {
  readonly captureId: string;
  readonly message: string;
}

const PNG_SIGNATURE_LENGTH = 8;

function pngChunkTypes(bytes: Buffer): ReadonlySet<string> {
  const chunkTypes = new Set<string>();
  let offset = PNG_SIGNATURE_LENGTH;

  while (offset + 12 <= bytes.length) {
    const chunkLength = bytes.readUInt32BE(offset);
    chunkTypes.add(bytes.toString("ascii", offset + 4, offset + 8));
    offset += 12 + chunkLength;
  }

  return chunkTypes;
}

function pixelAt(
  pixels: Buffer,
  width: number,
  xCoordinate: number,
  yCoordinate: number,
): RgbaPixel {
  const offset = (yCoordinate * width + xCoordinate) * 4;
  return {
    red: pixels[offset] ?? 0,
    green: pixels[offset + 1] ?? 0,
    blue: pixels[offset + 2] ?? 0,
    alpha: pixels[offset + 3] ?? 0,
  };
}

async function capturePixelFailures(props: {
  readonly captureId: string;
  readonly assetUrl: URL;
}): Promise<readonly CapturePixelFailure[]> {
  const bytes = await readFile(props.assetUrl);
  const chunkTypes = pngChunkTypes(bytes);
  const { data: pixels, info } = await sharp(bytes)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const failures: CapturePixelFailure[] = [];

  if (info.width !== websiteCaptureSuite.pixelSize[0]) {
    failures.push({ captureId: props.captureId, message: `width is ${info.width}` });
  }
  if (info.height !== websiteCaptureSuite.pixelSize[1]) {
    failures.push({ captureId: props.captureId, message: `height is ${info.height}` });
  }
  if (!chunkTypes.has("sRGB") || chunkTypes.has("iCCP")) {
    failures.push({
      captureId: props.captureId,
      message: "PNG is not normalized to the canonical sRGB chunk",
    });
  }

  const corners = [
    pixelAt(pixels, info.width, 0, 0),
    pixelAt(pixels, info.width, info.width - 1, 0),
    pixelAt(pixels, info.width, 0, info.height - 1),
    pixelAt(pixels, info.width, info.width - 1, info.height - 1),
  ] as const;

  for (const [cornerIndex, corner] of corners.entries()) {
    if (corner.alpha !== 0) {
      failures.push({
        captureId: props.captureId,
        message: `corner ${cornerIndex + 1} is opaque RGBA(${corner.red}, ${corner.green}, ${corner.blue}, ${corner.alpha})`,
      });
    }
  }

  return failures;
}

async function auditCapturePixels(): Promise<void> {
  const manifestUrl = new URL("../src/content/website-capture-manifest.ts", import.meta.url);
  const failures = (
    await Promise.all(
      websiteCaptureSuite.captures.map(async (capture) =>
        capturePixelFailures({
          captureId: capture.id,
          assetUrl: new URL(capture.assetPath, manifestUrl),
        }),
      ),
    )
  ).flat();

  if (failures.length > 0) {
    const failureLines = failures.map((failure) => `- ${failure.captureId}: ${failure.message}`);
    throw new Error(`Capture pixel audit failed:\n${failureLines.join("\n")}`);
  }

  console.log(
    `Audited ${websiteCaptureSuite.captures.length} capture assets for canonical sRGB and transparent native-window corners.`,
  );
}

await auditCapturePixels();
