import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";

import sharp from "sharp";

const projectDirectory = process.cwd();
const sourceScreenshotPath = resolve(projectDirectory, "src/assets/captures/parallel-agents.png");
const sourceLogoPath = resolve(projectDirectory, "src/assets/brand/app-logo-transparent.svg");
const outputPath = resolve(projectDirectory, "public/agent-studio-social-card.png");

const screenshotWidth = 724;
const screenshotHeight = 452;
const screenshotRadius = 18;

const roundedScreenshotMask = Buffer.from(`
  <svg width="${screenshotWidth}" height="${screenshotHeight}" xmlns="http://www.w3.org/2000/svg">
    <rect width="${screenshotWidth}" height="${screenshotHeight}" rx="${screenshotRadius}" fill="white" />
  </svg>
`);

const screenshot = await sharp(sourceScreenshotPath)
  .extract({
    left: 0,
    top: 300,
    width: 1920,
    height: 1200,
  })
  .resize(screenshotWidth, screenshotHeight, {
    fit: "cover",
  })
  .composite([{ input: roundedScreenshotMask, blend: "dest-in" }])
  .png()
  .toBuffer();

const logo = await sharp(sourceLogoPath).resize(82, 82).png().toBuffer();

const typography = Buffer.from(`
  <svg width="1200" height="630" xmlns="http://www.w3.org/2000/svg">
    <style>
      .product { fill: #ffffff; font: 800 64px -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; letter-spacing: -2px; }
      .description { fill: #eaeaea; font: 650 31px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
      .eyebrow { fill: #9ba1ad; font: 600 15px ui-monospace, "SF Mono", monospace; letter-spacing: 2px; }
    </style>
    <text class="eyebrow" x="72" y="194">AGENT-AGNOSTIC · REPO-AWARE</text>
    <text class="product" x="72" y="276">Agent Studio</text>
    <text class="description" x="72" y="342">Native macOS workspace</text>
    <text class="description" x="72" y="382">for coding agents</text>
    <rect x="72" y="440" width="134" height="6" rx="3" fill="#89b4fa" />
    <rect x="216" y="440" width="74" height="6" rx="3" fill="#ef9f76" />
  </svg>
`);

await mkdir(dirname(outputPath), { recursive: true });
await sharp({
  create: {
    width: 1200,
    height: 630,
    channels: 4,
    background: "#2e3036",
  },
})
  .composite([
    {
      input: Buffer.from(`
        <svg width="1200" height="630" xmlns="http://www.w3.org/2000/svg">
          <rect x="548" y="64" width="724" height="502" rx="24" fill="#1e1e2e" stroke="#89b4fa" stroke-opacity="0.34" stroke-width="2" />
          <rect x="516" y="88" width="724" height="478" rx="22" fill="#151520" stroke="#ef9f76" stroke-opacity="0.42" stroke-width="2" />
        </svg>
      `),
    },
    { input: screenshot, left: 500, top: 98 },
    { input: logo, left: 72, top: 66 },
    { input: typography },
  ])
  .withMetadata({ icc: "srgb" })
  .png({ compressionLevel: 9 })
  .toFile(outputPath);

console.log(`generated: ${outputPath}`);
