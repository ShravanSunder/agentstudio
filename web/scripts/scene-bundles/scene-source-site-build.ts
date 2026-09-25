// Builds the production site into a private directory and reads back the home
// page and its stylesheets: the real components' rendered markup and CSS.

import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { build as buildAstroSite } from "astro";

export interface BuiltHomePage {
  readonly homePageHtml: string;
  /** Every emitted stylesheet, keyed by the root-relative href pages link it with. */
  readonly stylesheetTextByHref: Readonly<Record<string, string>>;
}

async function readEmittedStylesheets(
  outputDirectory: string,
): Promise<Readonly<Record<string, string>>> {
  const entries = await readdir(outputDirectory, { recursive: true, withFileTypes: true });
  const stylesheets = entries.filter((entry) => entry.isFile() && entry.name.endsWith(".css"));
  return Object.fromEntries(
    await Promise.all(
      stylesheets.map(async (stylesheet): Promise<[string, string]> => {
        const filePath = path.join(stylesheet.parentPath, stylesheet.name);
        const href = `/${path.relative(outputDirectory, filePath).split(path.sep).join("/")}`;
        return [href, await readFile(filePath, "utf8")];
      }),
    ),
  );
}

export async function buildHomePageForSceneBundles(webRoot: string): Promise<BuiltHomePage> {
  const outputDirectory = await mkdtemp(path.join(tmpdir(), "agent-studio-scene-bundle-site-"));
  try {
    await buildAstroSite({ root: webRoot, outDir: outputDirectory, logLevel: "warn" });
    return {
      homePageHtml: await readFile(path.join(outputDirectory, "index.html"), "utf8"),
      stylesheetTextByHref: await readEmittedStylesheets(outputDirectory),
    };
  } finally {
    await rm(outputDirectory, { force: true, recursive: true });
  }
}
