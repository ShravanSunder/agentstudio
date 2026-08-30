import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { renderStaticMarketingAsset } from "./render-static-marketing-asset.ts";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectDirectory = resolve(scriptDirectory, "..");
const sourceLogo = await readFile(
  resolve(projectDirectory, "src/assets/brand/app-logo-transparent.svg"),
);

await renderStaticMarketingAsset({
  assetName: "social card",
  height: 630,
  outputPath: resolve(projectDirectory, "public/agent-studio-social-card.png"),
  replacements: [
    {
      token: "__APP_LOGO_DATA_URI__",
      value: `data:image/svg+xml;base64,${sourceLogo.toString("base64")}`,
    },
  ],
  templatePath: resolve(scriptDirectory, "social-card-template.html"),
  temporaryDirectoryPrefix: "agent-studio-social-card-",
  width: 1_200,
});

console.log("generated: public/agent-studio-social-card.png");
