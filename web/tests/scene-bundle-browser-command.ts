import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { defineBrowserCommand } from "@vitest/browser-playwright";

import { findForbiddenSceneScriptSyntax } from "../scripts/scene-bundles/scene-script-audit.ts";

export interface BuiltSceneBundleFiles {
  readonly sceneId: string;
  readonly files: Readonly<Record<string, string>>;
  /** Module syntax, network, or deferred-setup constructs found in scene.js. */
  readonly sceneScriptFindings: readonly string[];
}

const websiteRoot = path.resolve(import.meta.dirname, "..");

/**
 * Runs the real `build:scene-bundles` entry point into a private directory and
 * returns every emitted file, so the browser test checks what media receives.
 */
export const buildSceneBundlesForBrowserTest = defineBrowserCommand(
  async (): Promise<readonly BuiltSceneBundleFiles[]> => {
    const outputDirectory = await mkdtemp(path.join(tmpdir(), "agent-studio-scene-bundle-test-"));
    try {
      const environment: NodeJS.ProcessEnv = { ...process.env, ASTRO_TELEMETRY_DISABLED: "1" };
      for (const variableName of ["VITEST", "VITEST_MODE", "VITEST_POOL_ID", "VITEST_WORKER_ID"]) {
        delete environment[variableName];
      }
      const buildProcess = spawn(
        process.execPath,
        [
          "--experimental-strip-types",
          path.join(websiteRoot, "scripts", "build-scene-bundles.ts"),
          "--output-directory",
          outputDirectory,
        ],
        { cwd: websiteRoot, env: environment, stdio: ["ignore", "ignore", "pipe"] },
      );
      let stderr = "";
      buildProcess.stderr.on("data", (chunk: Buffer): void => {
        stderr += chunk.toString("utf8");
      });
      const [exitCode]: unknown[] = await once(buildProcess, "exit");
      if (exitCode !== 0) {
        throw new Error(`build-scene-bundles exited with ${String(exitCode)}:\n${stderr}`);
      }

      const sceneDirectories = await readdir(outputDirectory, { withFileTypes: true });
      return await Promise.all(
        sceneDirectories
          .filter((entry) => entry.isDirectory())
          .map(async (entry): Promise<BuiltSceneBundleFiles> => {
            const sceneDirectory = path.join(outputDirectory, entry.name);
            const fileNames = await readdir(sceneDirectory);
            const files = Object.fromEntries(
              await Promise.all(
                fileNames.map(async (fileName): Promise<[string, string]> => [
                  fileName,
                  await readFile(path.join(sceneDirectory, fileName), "utf8"),
                ]),
              ),
            );
            return {
              sceneId: entry.name,
              files,
              sceneScriptFindings: findForbiddenSceneScriptSyntax(files["scene.js"] ?? ""),
            };
          }),
      );
    } finally {
      await rm(outputDirectory, { force: true, recursive: true });
    }
  },
);
