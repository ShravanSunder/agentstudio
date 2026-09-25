import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const kitTokensCss = readFileSync(
  new URL("../src/recreation-kit/recreation-kit-tokens.css", import.meta.url),
  "utf8",
);

interface OpaqueColor {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
}

interface DeclaredColor extends OpaqueColor {
  readonly alpha: number;
}

function parseDeclaredColor(tokenName: string, value: string): DeclaredColor {
  const hex = /^#([0-9a-f]{6})$/i.exec(value);
  if (hex?.[1] !== undefined) {
    const channels = hex[1];
    return {
      red: Number.parseInt(channels.slice(0, 2), 16),
      green: Number.parseInt(channels.slice(2, 4), 16),
      blue: Number.parseInt(channels.slice(4, 6), 16),
      alpha: 1,
    };
  }
  const rgb = /^rgb\(\s*(\d+)\s+(\d+)\s+(\d+)\s*(?:\/\s*(\d+(?:\.\d+)?)%)?\s*\)$/.exec(value);
  if (rgb !== null) {
    return {
      red: Number(rgb[1]),
      green: Number(rgb[2]),
      blue: Number(rgb[3]),
      alpha: rgb[4] === undefined ? 1 : Number(rgb[4]) / 100,
    };
  }
  throw new Error(`--kit-${tokenName} is not a hex or rgb() color: ${value}`);
}

function readKitColorTokens(): ReadonlyMap<string, DeclaredColor> {
  const tokens = new Map<string, DeclaredColor>();
  for (const match of kitTokensCss.matchAll(/--kit-([a-z0-9-]+):\s*([^;]+);/g)) {
    const [, tokenName, rawValue] = match;
    const value = rawValue?.trim() ?? "";
    if (tokenName !== undefined && (value.startsWith("#") || value.startsWith("rgb("))) {
      tokens.set(tokenName, parseDeclaredColor(tokenName, value));
    }
  }
  return tokens;
}

const kitColors = readKitColorTokens();

function kitColor(tokenName: string): DeclaredColor {
  const color = kitColors.get(tokenName);
  if (color === undefined) {
    throw new Error(`recreation-kit-tokens.css declares no color --kit-${tokenName}`);
  }
  return color;
}

function compositeOver(top: DeclaredColor, base: OpaqueColor): OpaqueColor {
  return {
    red: top.red * top.alpha + base.red * (1 - top.alpha),
    green: top.green * top.alpha + base.green * (1 - top.alpha),
    blue: top.blue * top.alpha + base.blue * (1 - top.alpha),
  };
}

// WCAG 2.x relative luminance and contrast ratio.
function linearChannel(channel: number): number {
  const scaled = channel / 255;
  return scaled <= 0.040_45 ? scaled / 12.92 : ((scaled + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance(color: OpaqueColor): number {
  return (
    0.2126 * linearChannel(color.red) +
    0.7152 * linearChannel(color.green) +
    0.0722 * linearChannel(color.blue)
  );
}

function contrastRatio(first: OpaqueColor, second: OpaqueColor): number {
  const [lighter, darker] = [relativeLuminance(first), relativeLuminance(second)].toSorted(
    (a, b) => b - a,
  );
  return ((lighter ?? 0) + 0.05) / ((darker ?? 0) + 0.05);
}

interface TextOnSurface {
  readonly text: string;
  readonly surface: string;
  /** The opaque surface a translucent `surface` token is painted over. */
  readonly over?: string;
  readonly renders: string;
}

// Every text-on-surface pair the three chapter scenes render. All kit text is
// under 18.66px bold and 24px regular, so every pair needs the 4.5:1 AA ratio.
const renderedTextPairs: readonly TextOnSurface[] = [
  { text: "text-supporting", surface: "chrome", renders: "toolbar tabs, sidebar controls" },
  { text: "text-faint", surface: "chrome", renders: "unselected tab shortcut, branch names" },
  { text: "text", surface: "tab-selected", renders: "selected tab title" },
  { text: "text-faint", surface: "tab-selected", renders: "selected tab shortcut" },
  { text: "text", surface: "toolbar-control", renders: "arrangement chip" },
  { text: "text-faint", surface: "sidebar-field", renders: "sidebar filter placeholder" },
  { text: "text", surface: "sidebar-field", renders: "sidebar filter query" },
  { text: "primary", surface: "chrome", renders: "sidebar section title" },
  { text: "primary", surface: "primary-tint", over: "chrome", renders: "By Repo grouping" },
  { text: "text", surface: "chrome", renders: "worktree names" },
  { text: "added", surface: "chrome", renders: "sidebar diff badge" },
  { text: "removed", surface: "chrome", renders: "sidebar diff badge" },
  { text: "primary-text", surface: "chrome", renders: "sync and recency badges" },
  { text: "ansi-hash", surface: "chrome", renders: "pull request badge" },
  { text: "text", surface: "canvas", renders: "terminal and code text" },
  { text: "text-faint", surface: "canvas", renders: "agent activity, line numbers" },
  { text: "text-supporting", surface: "canvas", renders: "code punctuation" },
  { text: "ansi-path", surface: "canvas", renders: "prompt worktree" },
  { text: "ansi-branch", surface: "canvas", renders: "prompt branch" },
  { text: "ansi-command", surface: "canvas", renders: "typed command" },
  { text: "ansi-remote", surface: "canvas", renders: "remote-tracking branch" },
  { text: "ansi-arrow", surface: "canvas", renders: "prompt arrow" },
  { text: "ansi-hash", surface: "canvas", renders: "commit hashes, status codes" },
  { text: "primary-text", surface: "canvas", renders: "pull request reference" },
  { text: "added", surface: "canvas", renders: "added counts" },
  { text: "removed", surface: "canvas", renders: "removed counts" },
  { text: "syntax-keyword", surface: "canvas", renders: "code keywords" },
  { text: "syntax-type", surface: "canvas", renders: "code types" },
  { text: "syntax-function", surface: "canvas", renders: "code functions" },
  { text: "syntax-string", surface: "canvas", renders: "code strings" },
  { text: "syntax-comment", surface: "canvas", renders: "code comments" },
  { text: "text", surface: "card", renders: "user request" },
  { text: "text-faint", surface: "card", renders: "user request marker" },
  { text: "added", surface: "pane-footer", renders: "pane footer diff badge" },
  { text: "removed", surface: "pane-footer", renders: "pane footer diff badge" },
  { text: "primary-text", surface: "pane-footer", renders: "pane footer sync badge" },
  { text: "primary", surface: "primary-tint", over: "pane-footer", renders: "Zoomed chip" },
  { text: "text-supporting", surface: "floating", renders: "command bar context, hints" },
  { text: "text-faint", surface: "floating", renders: "command bar placeholder, scopes" },
  { text: "text", surface: "floating", renders: "command bar query and rows" },
  { text: "primary", surface: "floating", renders: "command bar section titles" },
  {
    text: "text",
    surface: "command-selected",
    over: "floating",
    renders: "selected command bar row",
  },
  {
    text: "text-supporting",
    surface: "command-selected",
    over: "floating",
    renders: "selected row detail",
  },
  { text: "text-supporting", surface: "tree", renders: "file header, folders" },
  { text: "text", surface: "tree", renders: "file tree rows" },
  { text: "primary-text", surface: "primary-tint", over: "tree", renders: "current Files view" },
  { text: "text", surface: "row-selected", over: "tree", renders: "selected file row" },
];

const minimumTextContrast = 4.5;

describe("recreation kit contrast", () => {
  it("meets WCAG AA for every text-on-surface pair the scenes render", () => {
    // Arrange / Act
    const failingPairs = renderedTextPairs.flatMap((pair) => {
      const surface = kitColor(pair.surface);
      const opaqueSurface =
        pair.over === undefined ? surface : compositeOver(surface, kitColor(pair.over));
      const ratio = contrastRatio(kitColor(pair.text), opaqueSurface);
      return ratio < minimumTextContrast
        ? [`${pair.text} on ${pair.surface} (${pair.renders}): ${ratio.toFixed(2)}:1`]
        : [];
    });

    // Assert
    expect(failingPairs).toEqual([]);
  });

  it("measures contrast the way WCAG defines it", () => {
    // Arrange
    const white = { red: 255, green: 255, blue: 255 };
    const black = { red: 0, green: 0, blue: 0 };

    // Act / Assert
    expect(contrastRatio(white, black)).toBeCloseTo(21, 5);
    expect(contrastRatio(white, white)).toBeCloseTo(1, 5);
  });
});
