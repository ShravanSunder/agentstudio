import { copyFile, lstat, mkdir, symlink } from "node:fs/promises";
import { resolve } from "node:path";

const projectDirectory = process.cwd();
const sourceConfigPath = resolve(projectDirectory, "cloudflare.config.ts");
const stagedConfigPath = resolve(projectDirectory, "dist", "cloudflare.config.ts");
const stagedPublicDirectory = resolve(projectDirectory, "dist", "public");
const buildOutputLinkPath = resolve(projectDirectory, ".cloudflare");
const rootDiscoveryAssets = ["agent-studio-social-card.png", "robots.txt", "sitemap.xml"];

await copyFile(sourceConfigPath, stagedConfigPath);
await mkdir(stagedPublicDirectory, { recursive: true });
await Promise.all(
  rootDiscoveryAssets.map((assetName): Promise<void> =>
    copyFile(
      resolve(projectDirectory, "dist", assetName),
      resolve(stagedPublicDirectory, assetName),
    ),
  ),
);

try {
  const buildOutputLinkStats = await lstat(buildOutputLinkPath);
  if (!buildOutputLinkStats.isSymbolicLink()) {
    throw new Error(`${buildOutputLinkPath} exists but is not the generated build-output link`);
  }
} catch (error: unknown) {
  if (error instanceof Error && "code" in error && error.code === "ENOENT") {
    await symlink("dist/.cloudflare", buildOutputLinkPath, "dir");
  } else {
    throw error;
  }
}
