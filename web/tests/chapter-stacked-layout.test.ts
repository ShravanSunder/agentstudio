import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { chapterStackedLayoutMediaQuery } from "../src/chapters/chapter-step-controller";
import { topologyStackedLayoutBreakpointWidth } from "../src/topology-lab/full-page-topology-composition";

function readSource(relativePath: string): string {
  return readFileSync(fileURLToPath(new URL(relativePath, import.meta.url)), "utf8");
}

/** The `--breakpoint-lg` the site's Tailwind `max-lg:` variant compiles to. */
function tailwindLargeBreakpoint(): string {
  const declaration = /--breakpoint-lg:\s*([^;]+);/u;
  const siteOverride = declaration.exec(readSource("../src/styles/global.css"))?.[1];
  const tailwindDefault = declaration.exec(
    readSource("../node_modules/tailwindcss/theme.css"),
  )?.[1];
  const breakpoint = siteOverride ?? tailwindDefault;
  if (breakpoint === undefined) {
    throw new Error("No --breakpoint-lg declaration found");
  }
  return breakpoint.trim();
}

describe("the stacked chapter layout boundary", () => {
  it("is the same boundary everywhere the chapter glass stacks", () => {
    // Arrange
    const breakpoint = tailwindLargeBreakpoint();
    const chapterSurface = readSource("../src/chapters/ChapterSurface.astro");

    // Assert: the controller, the step row styles, and the rail share
    // Tailwind's lg boundary, where the chapter surface's max-lg: layout stacks.
    expect(chapterStackedLayoutMediaQuery).toBe(`(width < ${breakpoint})`);
    expect(chapterSurface).toContain(`@media ${chapterStackedLayoutMediaQuery} {`);
    expect(chapterSurface).not.toContain("38.75rem");
    expect(topologyStackedLayoutBreakpointWidth).toBe(Number.parseFloat(breakpoint) * 16);
  });
});
