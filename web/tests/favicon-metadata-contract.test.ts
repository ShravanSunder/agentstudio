import { spawn, spawnSync, type ChildProcess } from "node:child_process";

import sharp from "sharp";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import {
  campaignAttributionRegistry,
  campaignChannels,
} from "../src/campaign-attribution/campaign-attribution-registry";

const canonicalHomeUrl = "https://getagentstudio.dev/";
const canonicalSitemapUrl = "https://getagentstudio.dev/sitemap.xml";
const expectedMetadataTitle = "Agent Studio: Native macOS IDE for parallel coding agents";
const previewPort = 20_000 + (process.pid % 10_000);
const previewOrigin = `http://127.0.0.1:${previewPort}`;
let previewProcess: ChildProcess | undefined;

const parseAttributes = (tag: string): ReadonlyMap<string, string> => {
  const attributes = new Map<string, string>();
  for (const match of tag.matchAll(/([:\w-]+)=["']([^"']*)["']/g)) {
    const [, name, value] = match;
    if (name !== undefined && value !== undefined) {
      attributes.set(name, value);
    }
  }
  return attributes;
};

const findTagAttributes = (
  html: string,
  tagName: "link" | "meta",
  selectorName: string,
  selectorValue: string,
): ReadonlyMap<string, string> | undefined => {
  const tags = html.match(new RegExp(`<${tagName}\\b[^>]*>`, "gi")) ?? [];
  return tags
    .map(parseAttributes)
    .find((attributes) => attributes.get(selectorName) === selectorValue);
};

const waitForPreview = async (deadline = Date.now() + 10_000): Promise<void> => {
  try {
    const response = await fetch(previewOrigin);
    if (response.ok) {
      return;
    }
  } catch {
    // The preview server is still starting.
  }

  if (Date.now() >= deadline) {
    throw new Error("Production artifact server did not become ready within 10 seconds");
  }

  await new Promise<void>((resolve) => {
    setTimeout(resolve, 25);
  });
  await waitForPreview(deadline);
};

describe("site discovery metadata", () => {
  beforeAll(async (): Promise<void> => {
    const buildResult = spawnSync("pnpm", ["run", "build"], {
      cwd: process.cwd(),
      encoding: "utf8",
    });

    if (buildResult.status !== 0) {
      throw new Error(`Website build failed:\n${buildResult.stdout}\n${buildResult.stderr}`);
    }

    previewProcess = spawn(
      "python3",
      ["-m", "http.server", String(previewPort), "--bind", "127.0.0.1", "--directory", "dist"],
      {
        cwd: process.cwd(),
        stdio: "ignore",
      },
    );
    await waitForPreview();
  }, 30_000);

  afterAll((): void => {
    if (previewProcess?.pid !== undefined) {
      previewProcess.kill("SIGTERM");
    }
  });

  it("advertises a fetchable image favicon from the home page", async (): Promise<void> => {
    const homePageResponse = await fetch(previewOrigin);
    expect(homePageResponse.status).toBe(200);

    const homePageHtml = await homePageResponse.text();
    const faviconHref = homePageHtml.match(
      /<link\b[^>]*\brel=["'](?:shortcut )?icon["'][^>]*\bhref=["']([^"']+)["'][^>]*>/i,
    )?.[1];
    expect(faviconHref).toBeDefined();
    if (faviconHref === undefined) {
      throw new Error("The built home page did not advertise a favicon");
    }

    const faviconResponse = await fetch(new URL(faviconHref, previewOrigin));
    expect(faviconResponse.status).toBe(200);
    expect(faviconResponse.headers.get("content-type")).toMatch(/^image\//);
  });

  it("publishes canonical search and social metadata with a usable social card", async (): Promise<void> => {
    const homePageResponse = await fetch(previewOrigin);
    expect(homePageResponse.status).toBe(200);

    const homePageHtml = await homePageResponse.text();
    expect(homePageHtml).toContain(`<title>${expectedMetadataTitle}</title>`);

    const canonicalLink = findTagAttributes(homePageHtml, "link", "rel", "canonical");
    expect(canonicalLink?.get("href")).toBe(canonicalHomeUrl);

    const pageDescription = findTagAttributes(homePageHtml, "meta", "name", "description")?.get(
      "content",
    );
    expect(pageDescription).toBeTruthy();

    const expectedMetadata = new Map<string, string>([
      ["og:type", "website"],
      ["og:site_name", "Agent Studio"],
      ["og:title", expectedMetadataTitle],
      ["og:description", pageDescription ?? ""],
      ["og:url", canonicalHomeUrl],
      ["og:image:type", "image/png"],
      ["og:image:width", "1200"],
      ["og:image:height", "630"],
      ["twitter:card", "summary_large_image"],
      ["twitter:title", expectedMetadataTitle],
      ["twitter:description", pageDescription ?? ""],
    ]);

    for (const [metadataName, expectedValue] of expectedMetadata) {
      const selectorName = metadataName.startsWith("og:") ? "property" : "name";
      const metadataTag = findTagAttributes(homePageHtml, "meta", selectorName, metadataName);
      expect(metadataTag?.get("content"), metadataName).toBe(expectedValue);
    }

    const openGraphImage = findTagAttributes(homePageHtml, "meta", "property", "og:image");
    const xImage = findTagAttributes(homePageHtml, "meta", "name", "twitter:image");
    const openGraphImageAlt = findTagAttributes(
      homePageHtml,
      "meta",
      "property",
      "og:image:alt",
    )?.get("content");
    const xImageAlt = findTagAttributes(homePageHtml, "meta", "name", "twitter:image:alt")?.get(
      "content",
    );
    const socialImageUrl = openGraphImage?.get("content");
    expect(socialImageUrl).toBe("https://getagentstudio.dev/agent-studio-social-card.png");
    expect(xImage?.get("content")).toBe(socialImageUrl);
    expect(openGraphImageAlt).toBeTruthy();
    expect(xImageAlt).toBe(openGraphImageAlt);

    if (socialImageUrl === undefined) {
      throw new Error("The built home page did not advertise a social-card image");
    }

    const socialImageResponse = await fetch(
      new URL(new URL(socialImageUrl).pathname, previewOrigin),
    );
    expect(socialImageResponse.status).toBe(200);
    expect(socialImageResponse.headers.get("content-type")).toBe("image/png");

    const socialImageMetadata = await sharp(
      Buffer.from(await socialImageResponse.arrayBuffer()),
    ).metadata();
    expect(socialImageMetadata.width).toBe(1200);
    expect(socialImageMetadata.height).toBe(630);
  });

  it("publishes aggregate and registered campaign pages with canonical homepage metadata", async (): Promise<void> => {
    const campaignPaths = [
      ...campaignChannels.map((channel) => `/${channel}/`),
      ...campaignAttributionRegistry.routes.map((route) => `${route.path}/`),
    ];

    await Promise.all(
      campaignPaths.map(async (campaignPath): Promise<void> => {
        const campaignResponse = await fetch(new URL(campaignPath, previewOrigin));
        expect(campaignResponse.status, campaignPath).toBe(200);

        const campaignHtml = await campaignResponse.text();
        expect(campaignHtml, campaignPath).toContain(`<title>${expectedMetadataTitle}</title>`);
        expect(
          findTagAttributes(campaignHtml, "link", "rel", "canonical")?.get("href"),
          campaignPath,
        ).toBe(canonicalHomeUrl);
        expect(
          findTagAttributes(campaignHtml, "meta", "property", "og:url")?.get("content"),
          campaignPath,
        ).toBe(canonicalHomeUrl);
        expect(
          findTagAttributes(campaignHtml, "meta", "name", "twitter:title")?.get("content"),
          campaignPath,
        ).toBe(expectedMetadataTitle);
        expect(
          findTagAttributes(campaignHtml, "meta", "property", "og:image")?.get("content"),
          campaignPath,
        ).toBe("https://getagentstudio.dev/agent-studio-social-card.png");
      }),
    );

    const unknownCampaignResponse = await fetch(new URL("/x/zzzz/", previewOrigin));
    expect(unknownCampaignResponse.status).toBe(404);
  });

  it("publishes only the canonical home page in the sitemap and advertises it in robots", async (): Promise<void> => {
    const sitemapResponse = await fetch(new URL("/sitemap.xml", previewOrigin));
    expect(sitemapResponse.status).toBe(200);
    expect(sitemapResponse.headers.get("content-type")).toMatch(/^application\/xml/);

    const sitemapXml = await sitemapResponse.text();
    expect(sitemapXml).toContain(`<loc>${canonicalHomeUrl}</loc>`);
    expect(sitemapXml).not.toContain("topology-full-page-lab");
    for (const campaignChannel of campaignChannels) {
      expect(sitemapXml).not.toContain(`/${campaignChannel}`);
    }

    const robotsResponse = await fetch(new URL("/robots.txt", previewOrigin));
    expect(robotsResponse.status).toBe(200);
    const robotsText = await robotsResponse.text();
    expect(robotsText).toContain("User-agent: *");
    expect(robotsText).toContain("Allow: /");
    expect(robotsText).toContain(`Sitemap: ${canonicalSitemapUrl}`);
  });
});
