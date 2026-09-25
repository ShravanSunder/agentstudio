// Bundles one scene module into a classic-script IIFE with Vite's library
// build. GSAP stays external: a scene only adds tweens to the host's timeline.

import path from "node:path";

import { build, type Rolldown } from "vite";

import type { SceneId } from "../../src/motion-scenes/scene-contract.ts";

/** The IIFE's name for the bundled module; scene.js keeps it function-scoped. */
export const sceneBundleGlobalName = "agentStudioSceneModule";

/** `chapter-context-with-task` → `chapterContextWithTaskScene`, the module's export name. */
export function sceneModuleExportName(sceneId: SceneId): string {
  const camelCase = sceneId.replace(/-([a-z])/g, (_match, letter: string) => letter.toUpperCase());
  return `${camelCase}Scene`;
}

/** Scene modules live at `scenes/<sceneId>/<sceneId>-scene.ts`. */
function sceneModulePath(webRoot: string, sceneId: SceneId): string {
  return path.join(webRoot, "src", "motion-scenes", "scenes", sceneId, `${sceneId}-scene.ts`);
}

function readSingleChunk(
  output: Awaited<ReturnType<typeof build>>,
  sceneId: SceneId,
): Rolldown.OutputChunk {
  const outputs = Array.isArray(output) ? output : [output];
  const chunks = outputs.flatMap((buildOutput) =>
    "output" in buildOutput
      ? buildOutput.output.filter((item): item is Rolldown.OutputChunk => item.type === "chunk")
      : [],
  );
  const [chunk, ...extraChunks] = chunks;
  if (chunk === undefined || extraChunks.length > 0) {
    throw new Error(`Bundling ${sceneId} produced ${String(chunks.length)} chunks; expected one.`);
  }
  return chunk;
}

export async function bundleSceneModule(webRoot: string, sceneId: SceneId): Promise<string> {
  const output = await build({
    configFile: false,
    envDir: false,
    logLevel: "warn",
    publicDir: false,
    root: webRoot,
    build: {
      write: false,
      minify: false,
      lib: {
        entry: sceneModulePath(webRoot, sceneId),
        formats: ["iife"],
        name: sceneBundleGlobalName,
        fileName: (): string => "scene.js",
      },
      rolldownOptions: {
        external: (id: string): boolean => id === "gsap" || id.startsWith("gsap/"),
      },
    },
  });
  const chunk = readSingleChunk(output, sceneId);
  if (chunk.imports.length > 0) {
    throw new Error(
      `${sceneId} imports ${chunk.imports.join(", ")} at run time; a scene may only use the host's timeline.`,
    );
  }
  const exportName = sceneModuleExportName(sceneId);
  if (!chunk.exports.includes(exportName)) {
    throw new Error(`The ${sceneId} module does not export ${exportName}.`);
  }
  return chunk.code;
}
