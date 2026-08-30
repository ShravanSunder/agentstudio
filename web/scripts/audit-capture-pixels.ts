import { createHash } from "node:crypto";
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
const CORNER_SAMPLE_SIZE_PIXELS = 32;
const BRIGHT_FRINGE_CHANNEL_THRESHOLD = 220;
const CANONICAL_SRGB_ICC_SHA256 =
  "c56e1685d888f5edb92fe07f2750f387f8fe8e91b32ff8fb0b56bfbbb9458353";

function sha256(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

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
  readonly expectedPixelSize: readonly [width: number, height: number];
  readonly projectionPolicy: "full-native-window" | "purpose-crop";
}): Promise<readonly CapturePixelFailure[]> {
  const bytes = await readFile(props.assetUrl);
  const chunkTypes = pngChunkTypes(bytes);
  const metadata = await sharp(bytes).metadata();
  const { data: pixels, info } = await sharp(bytes)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const failures: CapturePixelFailure[] = [];

  if (info.width !== props.expectedPixelSize[0]) {
    failures.push({ captureId: props.captureId, message: `width is ${info.width}` });
  }
  if (info.height !== props.expectedPixelSize[1]) {
    failures.push({ captureId: props.captureId, message: `height is ${info.height}` });
  }
  const hasCanonicalSrgbChunk = chunkTypes.has("sRGB") && !chunkTypes.has("iCCP");
  const hasCanonicalSrgbIcc =
    chunkTypes.has("iCCP") &&
    metadata.icc !== undefined &&
    sha256(metadata.icc) === CANONICAL_SRGB_ICC_SHA256;
  if (!hasCanonicalSrgbChunk && !hasCanonicalSrgbIcc) {
    failures.push({
      captureId: props.captureId,
      message: "PNG does not contain the canonical sRGB chunk or reviewed sRGB ICC payload",
    });
  }

  const corners = [
    pixelAt(pixels, info.width, 0, 0),
    pixelAt(pixels, info.width, info.width - 1, 0),
    pixelAt(pixels, info.width, 0, info.height - 1),
    pixelAt(pixels, info.width, info.width - 1, info.height - 1),
  ] as const;

  for (const [cornerIndex, corner] of corners.entries()) {
    if (props.projectionPolicy === "purpose-crop") {
      break;
    }
    if (corner.alpha !== 0) {
      failures.push({
        captureId: props.captureId,
        message: `corner ${cornerIndex + 1} is opaque RGBA(${corner.red}, ${corner.green}, ${corner.blue}, ${corner.alpha})`,
      });
    }
  }

  const cornerSampleOrigins = [
    { xCoordinate: 0, yCoordinate: 0 },
    { xCoordinate: info.width - CORNER_SAMPLE_SIZE_PIXELS, yCoordinate: 0 },
    { xCoordinate: 0, yCoordinate: info.height - CORNER_SAMPLE_SIZE_PIXELS },
    {
      xCoordinate: info.width - CORNER_SAMPLE_SIZE_PIXELS,
      yCoordinate: info.height - CORNER_SAMPLE_SIZE_PIXELS,
    },
  ] as const;

  for (const [cornerIndex, origin] of cornerSampleOrigins.entries()) {
    if (props.projectionPolicy === "purpose-crop") {
      break;
    }
    let transparentPixelCount = 0;
    let brightAntialiasingPixelCount = 0;

    for (
      let yCoordinate = origin.yCoordinate;
      yCoordinate < origin.yCoordinate + CORNER_SAMPLE_SIZE_PIXELS;
      yCoordinate += 1
    ) {
      for (
        let xCoordinate = origin.xCoordinate;
        xCoordinate < origin.xCoordinate + CORNER_SAMPLE_SIZE_PIXELS;
        xCoordinate += 1
      ) {
        const pixel = pixelAt(pixels, info.width, xCoordinate, yCoordinate);
        if (pixel.alpha === 0) {
          transparentPixelCount += 1;
        }
        if (
          pixel.alpha > 0 &&
          pixel.alpha < 255 &&
          Math.max(pixel.red, pixel.green, pixel.blue) > BRIGHT_FRINGE_CHANNEL_THRESHOLD
        ) {
          brightAntialiasingPixelCount += 1;
        }
      }
    }

    if (transparentPixelCount === 0) {
      failures.push({
        captureId: props.captureId,
        message: `corner sample ${cornerIndex + 1} contains no transparent outside-window pixels`,
      });
    }
    if (brightAntialiasingPixelCount > 0) {
      failures.push({
        captureId: props.captureId,
        message: `corner sample ${cornerIndex + 1} contains ${brightAntialiasingPixelCount} bright partially transparent fringe pixels`,
      });
    }
  }

  return failures;
}

async function auditCapturePixels(): Promise<void> {
  const manifestUrl = new URL("../src/content/website-capture-manifest.ts", import.meta.url);
  const failures = (
    await Promise.all(
      websiteCaptureSuite.captures.map(async (capture) => {
        const desktopFailures = await capturePixelFailures({
          captureId: capture.id,
          assetUrl: new URL(capture.assetPath, manifestUrl),
          expectedPixelSize:
            "desktopPixelSize" in capture
              ? capture.desktopPixelSize
              : websiteCaptureSuite.pixelSize,
          projectionPolicy:
            "projectionPolicy" in capture ? capture.projectionPolicy : "full-native-window",
        });
        const viewerFailures =
          "viewerAssetPath" in capture
            ? await capturePixelFailures({
                captureId: `${capture.id} viewer`,
                assetUrl: new URL(capture.viewerAssetPath, manifestUrl),
                expectedPixelSize:
                  "viewerPixelSize" in capture
                    ? capture.viewerPixelSize
                    : websiteCaptureSuite.pixelSize,
                projectionPolicy: "full-native-window",
              })
            : [];

        return [...desktopFailures, ...viewerFailures];
      }),
    )
  ).flat();

  if (failures.length > 0) {
    const failureLines = failures.map((failure) => `- ${failure.captureId}: ${failure.message}`);
    throw new Error(`Capture pixel audit failed:\n${failureLines.join("\n")}`);
  }

  console.log(
    `Audited ${websiteCaptureSuite.captures.length} capture records and their expanded-view masters for canonical sRGB and declared projection policy.`,
  );
}

await auditCapturePixels();
