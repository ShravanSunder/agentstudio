// Emits one pinned folder per motion scene for the media team's HyperFrames
// projects: scene.js, scene.html, scene.css and manifest.json.
//
//   pnpm --dir web run build:scene-bundles [-- --output-directory <path>]
//
// Markup and CSS come from the production build of `/`, so they are what the
// real components render. Labels and duration come from running the bundled
// module against a paused GSAP timeline in headless Chrome.

import { execFile } from "node:child_process";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs, promisify } from "node:util";

import { websiteCaptureSuite } from "../src/content/website-capture-manifest.ts";
import { sceneIds } from "../src/motion-scenes/scene-contract.ts";
import { openHeadlessChromePage } from "./scene-bundles/headless-chrome-page.ts";
import { assembleSceneBundle, type SceneBundle } from "./scene-bundles/scene-bundle-assembly.ts";
import { serializeSceneBundleManifest } from "./scene-bundles/scene-bundle-manifest.ts";
import { runClassicScriptInPage } from "./scene-bundles/scene-bundle-page-functions.ts";
import { buildHomePageForSceneBundles } from "./scene-bundles/scene-source-site-build.ts";

const webRoot = path.resolve(import.meta.dirname, "..");
const defaultOutputDirectory = path.join(webRoot, "dist-scene-bundles");

// The recreation kit models the 1280×800-point app window the capture suite
// records ("one em is one app point"), so that window is the scene's native stage.
const [nativeStageWidth, nativeStageHeight] = websiteCaptureSuite.logicalSizePoints;
const nativeStage = { width: nativeStageWidth, height: nativeStageHeight } as const;

// The seed the website's ScenePlayback passes (web/src/home-page/scene-playback.ts).
const websiteSceneSeed = 1;

const runFile = promisify(execFile);

interface WebsiteRevision {
  readonly revision: string;
  readonly treeClean: boolean;
}

async function readWebsiteRevision(): Promise<WebsiteRevision> {
  const { stdout: revision } = await runFile("git", ["rev-parse", "HEAD"], { cwd: webRoot });
  const { stdout: changes } = await runFile("git", ["status", "--porcelain", "--", "."], {
    cwd: webRoot,
  });
  return { revision: revision.trim(), treeClean: changes.trim() === "" };
}

interface GsapRuntime {
  readonly version: string;
  readonly classicScript: string;
}

async function readGsapRuntime(): Promise<GsapRuntime> {
  const packageDirectory = path.dirname(fileURLToPath(import.meta.resolve("gsap")));
  const packageJson: unknown = JSON.parse(
    await readFile(path.join(packageDirectory, "package.json"), "utf8"),
  );
  if (
    typeof packageJson !== "object" ||
    packageJson === null ||
    !("version" in packageJson) ||
    typeof packageJson.version !== "string"
  ) {
    throw new Error("Could not read the installed GSAP version.");
  }
  const classicScript = await readFile(
    fileURLToPath(import.meta.resolve("gsap/dist/gsap.min.js")),
    "utf8",
  );
  return { version: packageJson.version, classicScript };
}

async function writeSceneBundle(outputDirectory: string, bundle: SceneBundle): Promise<void> {
  const sceneDirectory = path.join(outputDirectory, bundle.sceneId);
  await mkdir(sceneDirectory, { recursive: true });
  await Promise.all([
    ...Object.entries(bundle.files).map(
      async ([fileName, fileText]): Promise<void> =>
        await writeFile(path.join(sceneDirectory, fileName), fileText, "utf8"),
    ),
    writeFile(
      path.join(sceneDirectory, "manifest.json"),
      serializeSceneBundleManifest(bundle.manifest),
      "utf8",
    ),
  ]);
}

async function buildSceneBundles(outputDirectory: string): Promise<void> {
  const revision = await readWebsiteRevision();
  const gsapRuntime = await readGsapRuntime();
  const homePage = await buildHomePageForSceneBundles(webRoot);
  const page = await openHeadlessChromePage("Building scene bundles");
  let bundles: readonly SceneBundle[];
  try {
    await page.evaluate(runClassicScriptInPage, gsapRuntime.classicScript);
    // Each page call mounts, measures, and cleans up in one synchronous turn,
    // so scenes can share the page concurrently.
    bundles = await Promise.all(
      sceneIds.map(
        async (sceneId): Promise<SceneBundle> =>
          await assembleSceneBundle({
            sceneId,
            webRoot,
            page,
            homePage,
            websiteRevision: revision.revision,
            websiteTreeClean: revision.treeClean,
            gsapVersion: gsapRuntime.version,
            stage: nativeStage,
            seed: websiteSceneSeed,
          }),
      ),
    );
  } finally {
    await page.close();
  }

  // The output root holds only generated scene folders; stale scenes must not survive.
  await rm(outputDirectory, { force: true, recursive: true });
  await Promise.all(bundles.map(async (bundle) => await writeSceneBundle(outputDirectory, bundle)));
  for (const bundle of bundles) {
    console.log(
      `${bundle.sceneId}: ${String(bundle.manifest.durationSeconds)}s, labels ${Object.keys(bundle.manifest.labels).join(", ")}`,
    );
  }
  const treeNote = revision.treeClean ? "" : " (web/ has uncommitted changes)";
  console.log(
    `Wrote ${String(bundles.length)} scene bundles for ${revision.revision}${treeNote} to ${outputDirectory}`,
  );
}

const { values: argumentValues } = parseArgs({
  options: { "output-directory": { type: "string" } },
});
await buildSceneBundles(path.resolve(argumentValues["output-directory"] ?? defaultOutputDirectory));
