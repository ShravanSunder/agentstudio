import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";

import sharp from "sharp";

import {
  campaignAttributionRegistry,
  campaignChannels,
} from "../src/campaign-attribution/campaign-attribution-registry.ts";
import { canonicalHomeUrl, siteMetadata } from "../src/site-metadata.ts";

const projectDirectory = process.cwd();
const cloudflareAssetsDirectory = resolve(
  projectDirectory,
  ".cloudflare/output/v0/workers/default/assets",
);
const cloudflareWorkerConfigPath = resolve(
  projectDirectory,
  ".cloudflare/output/v0/workers/default/config.json",
);
const expectedFiles = [
  "agent-studio-social-card.png",
  "agent-studio-x-profile-banner.png",
  "agent-studio-youtube-channel-banner.png",
  "robots.txt",
  "sitemap.xml",
];

await Promise.all(
  expectedFiles.map(async (assetName): Promise<void> => {
    const assetStats = await stat(resolve(cloudflareAssetsDirectory, assetName));
    if (!assetStats.isFile() || assetStats.size === 0) {
      throw new Error(`Cloudflare output has no usable root discovery asset: ${assetName}`);
    }
  }),
);

const isRecord = (value: unknown): value is Readonly<Record<string, unknown>> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const cloudflareWorkerConfig = JSON.parse(
  await readFile(cloudflareWorkerConfigPath, "utf8"),
) as unknown;
if (!isRecord(cloudflareWorkerConfig) || !isRecord(cloudflareWorkerConfig["assets"])) {
  throw new Error("Cloudflare output has no readable static-assets configuration");
}

const cloudflareAssetsConfig = cloudflareWorkerConfig["assets"];
if (
  cloudflareAssetsConfig["htmlHandling"] !== "drop-trailing-slash" ||
  cloudflareAssetsConfig["notFoundHandling"] !== "none"
) {
  throw new Error("Cloudflare output does not enforce the campaign route HTML contract");
}

const forbiddenRuntimeConfigKeys = ["main", "bindings", "analyticsEngineDatasets"];
for (const forbiddenRuntimeConfigKey of forbiddenRuntimeConfigKeys) {
  if (cloudflareWorkerConfig[forbiddenRuntimeConfigKey] !== undefined) {
    throw new Error(
      `Cloudflare campaign release must remain assets-only; found ${forbiddenRuntimeConfigKey}`,
    );
  }
}

const expectedCampaignHtmlPaths = [
  ...campaignChannels.map((channel) => `${channel}/index.html`),
  ...campaignAttributionRegistry.routes.map((route) => `${route.path.slice(1)}/index.html`),
];

await Promise.all(
  expectedCampaignHtmlPaths.map(async (campaignHtmlPath): Promise<void> => {
    const campaignHtmlFile = resolve(cloudflareAssetsDirectory, campaignHtmlPath);
    const campaignHtmlStats = await stat(campaignHtmlFile);
    if (!campaignHtmlStats.isFile() || campaignHtmlStats.size === 0) {
      throw new Error(`Cloudflare output has no campaign page: ${campaignHtmlPath}`);
    }

    const campaignHtml = await readFile(campaignHtmlFile, "utf8");
    const requiredMetadata = [
      `<title>${siteMetadata.homeTitle}</title>`,
      `<link rel="canonical" href="${canonicalHomeUrl}">`,
      `<meta property="og:url" content="${canonicalHomeUrl}">`,
      `<meta property="og:image" content="${new URL(siteMetadata.socialCard.path, siteMetadata.canonicalOrigin).href}">`,
    ];
    for (const metadata of requiredMetadata) {
      if (!campaignHtml.includes(metadata)) {
        throw new Error(`Cloudflare campaign page ${campaignHtmlPath} is missing ${metadata}`);
      }
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

const youtubeBannerMetadata = await sharp(
  resolve(cloudflareAssetsDirectory, "agent-studio-youtube-channel-banner.png"),
).metadata();
if (youtubeBannerMetadata.width !== 2560 || youtubeBannerMetadata.height !== 1440) {
  throw new Error(
    `Cloudflare YouTube banner must be 2560x1440; received ${youtubeBannerMetadata.width ?? "unknown"}x${youtubeBannerMetadata.height ?? "unknown"}`,
  );
}

const xProfileBannerMetadata = await sharp(
  resolve(cloudflareAssetsDirectory, "agent-studio-x-profile-banner.png"),
).metadata();
if (xProfileBannerMetadata.width !== 1500 || xProfileBannerMetadata.height !== 500) {
  throw new Error(
    `Cloudflare X profile banner must be 1500x500; received ${xProfileBannerMetadata.width ?? "unknown"}x${xProfileBannerMetadata.height ?? "unknown"}`,
  );
}

const sitemap = await readFile(resolve(cloudflareAssetsDirectory, "sitemap.xml"), "utf8");
if (!sitemap.includes("<loc>https://getagentstudio.dev/</loc>")) {
  throw new Error("Cloudflare sitemap does not contain the canonical home page");
}
if (sitemap.includes("topology-full-page-lab")) {
  throw new Error("Cloudflare sitemap exposes the topology lab");
}
for (const campaignChannel of campaignChannels) {
  if (sitemap.includes(`/${campaignChannel}`)) {
    throw new Error(`Cloudflare sitemap exposes campaign channel ${campaignChannel}`);
  }
}

const robots = await readFile(resolve(cloudflareAssetsDirectory, "robots.txt"), "utf8");
if (!robots.includes("Sitemap: https://getagentstudio.dev/sitemap.xml")) {
  throw new Error("Cloudflare robots file does not advertise the canonical sitemap");
}

console.log(
  `Verified Cloudflare campaign images, ${expectedCampaignHtmlPaths.length} campaign pages, sitemap, and origin robots assets.`,
);
