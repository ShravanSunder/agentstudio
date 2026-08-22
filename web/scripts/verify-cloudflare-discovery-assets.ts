import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";

import sharp from "sharp";

const projectDirectory = process.cwd();
const cloudflareAssetsDirectory = resolve(
  projectDirectory,
  ".cloudflare/output/v0/workers/default/assets",
);
const expectedFiles = ["agent-studio-social-card.png", "robots.txt", "sitemap.xml"];

await Promise.all(
  expectedFiles.map(async (assetName): Promise<void> => {
    const assetStats = await stat(resolve(cloudflareAssetsDirectory, assetName));
    if (!assetStats.isFile() || assetStats.size === 0) {
      throw new Error(`Cloudflare output has no usable root discovery asset: ${assetName}`);
    }
  }),
);

const socialCardMetadata = await sharp(
  resolve(cloudflareAssetsDirectory, "agent-studio-social-card.png"),
).metadata();
if (socialCardMetadata.width !== 1200 || socialCardMetadata.height !== 630) {
  throw new Error(
    `Cloudflare social card must be 1200x630; received ${socialCardMetadata.width ?? "unknown"}x${socialCardMetadata.height ?? "unknown"}`,
  );
}

const sitemap = await readFile(resolve(cloudflareAssetsDirectory, "sitemap.xml"), "utf8");
if (!sitemap.includes("<loc>https://getagentstudio.dev/</loc>")) {
  throw new Error("Cloudflare sitemap does not contain the canonical home page");
}
if (sitemap.includes("topology-full-page-lab")) {
  throw new Error("Cloudflare sitemap exposes the topology lab");
}

const robots = await readFile(resolve(cloudflareAssetsDirectory, "robots.txt"), "utf8");
if (!robots.includes("Sitemap: https://getagentstudio.dev/sitemap.xml")) {
  throw new Error("Cloudflare robots file does not advertise the canonical sitemap");
}

console.log("Verified Cloudflare social card, sitemap, and origin robots assets.");
