import { copyFile, lstat, symlink } from "node:fs/promises";
import { resolve } from "node:path";

const projectDirectory = process.cwd();
const sourceConfigPath = resolve(projectDirectory, "cloudflare.config.ts");
const stagedConfigPath = resolve(projectDirectory, "dist", "cloudflare.config.ts");
const buildOutputLinkPath = resolve(projectDirectory, ".cloudflare");

await copyFile(sourceConfigPath, stagedConfigPath);

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
