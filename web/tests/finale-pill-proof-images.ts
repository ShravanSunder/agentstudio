import { mkdir, writeFile } from "node:fs/promises";

import sharp from "sharp";

interface FinalePillProofImages {
  readonly width: number;
  readonly frame: Uint8Array;
  readonly finalePill: Uint8Array;
  readonly stepPill: Uint8Array;
}

/** Keep the requested full frame and three-times pixel comparison beside the gate logs. */
export async function saveFinalePillProofImages(images: FinalePillProofImages): Promise<void> {
  const outputDirectory = new URL("../../tmp/proof/", import.meta.url);
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(new URL(`finale-pill-${images.width}.png`, outputDirectory), images.frame);
  const enlargeCrop = async (bytes: Uint8Array): Promise<Buffer> => {
    const metadata = await sharp(bytes).metadata();
    if (metadata.width === undefined) throw new Error("Pill crop width missing");
    return await sharp(bytes)
      .resize(metadata.width * 3)
      .png()
      .toBuffer();
  };
  const [finaleCrop, stepCrop] = await Promise.all([
    enlargeCrop(images.finalePill),
    enlargeCrop(images.stepPill),
  ]);
  const [finaleSize, stepSize] = await Promise.all([
    sharp(finaleCrop).metadata(),
    sharp(stepCrop).metadata(),
  ]);
  if (
    finaleSize.width === undefined ||
    finaleSize.height === undefined ||
    stepSize.width === undefined ||
    stepSize.height === undefined
  )
    throw new Error("Enlarged pill dimensions missing");
  await sharp({
    create: {
      width: finaleSize.width + stepSize.width + 36,
      height: Math.max(finaleSize.height, stepSize.height) + 24,
      channels: 4,
      background: "#191b1f",
    },
  })
    .composite([
      { input: finaleCrop, left: 12, top: 12 },
      { input: stepCrop, left: finaleSize.width + 24, top: 12 },
    ])
    .png()
    .toFile(new URL(`finale-step-pills-3x-${images.width}.png`, outputDirectory).pathname);
}
