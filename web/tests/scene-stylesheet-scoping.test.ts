import { describe, expect, it } from "vitest";

import {
  scopeComplexSelector,
  selectorMatchProbe,
  splitSelectorList,
} from "../scripts/scene-bundles/scene-selector-scoping.ts";
import type {
  SelectorReach,
  SourceCssRule,
} from "../scripts/scene-bundles/scene-stylesheet-model.ts";
import {
  buildScopedSceneStylesheet,
  collectSelectorProbes,
  resolvePhoneBreakpoint,
  splitDeclarations,
} from "../scripts/scene-bundles/scene-stylesheet-scoping.ts";

const sceneId = "chapter-context-with-task";
const sceneRoot = `[data-scene-root="${sceneId}"]`;

function styleRule(
  selectorText: string,
  declarations: readonly (readonly [string, string])[],
): SourceCssRule {
  return {
    kind: "style",
    selectorText,
    declarationsText: declarations.map(([property, value]) => `${property}: ${value};`).join(" "),
    nestedRuleCount: 0,
  };
}

function buildStylesheet(
  rules: readonly SourceCssRule[],
  reachBySelector: Readonly<Record<string, SelectorReach>>,
  sceneMarkup = "",
): string {
  return buildScopedSceneStylesheet({
    sceneId,
    rules,
    reachBySelector: new Map(Object.entries(reachBySelector)),
    sceneMarkup,
  }).cssText;
}

describe("scene stylesheet selectors", () => {
  it("splits a selector list only at top-level commas", () => {
    // Arrange
    const selectorText = String.raw`*, ::after, :is(.a, .b) > .c, [data-x="a,b"], .\[a\,b\]`;

    // Act
    const complexSelectors = splitSelectorList(selectorText);

    // Assert
    expect(complexSelectors).toEqual([
      "*",
      "::after",
      ":is(.a, .b) > .c",
      '[data-x="a,b"]',
      String.raw`.\[a\,b\]`,
    ]);
  });

  it("probes the element a selector styles, without pseudo-elements or pointer state", () => {
    // Arrange / Act / Assert
    expect(selectorMatchProbe(".a:hover > .b::before")).toBe(".a > .b");
    expect(selectorMatchProbe("::before")).toBe("*");
    expect(selectorMatchProbe(".x:focus-visible")).toBe(".x");
    expect(selectorMatchProbe(".x:not(:hover)")).toBe(".x:not(:hover)");
    expect(selectorMatchProbe(".x::-webkit-scrollbar:hover")).toBe(".x");
  });

  it("scopes the scene root itself, its descendants, or both", () => {
    // Arrange / Act / Assert
    expect(scopeComplexSelector(".recreation-kit", sceneId, "root")).toEqual([
      `${sceneRoot}:is(.recreation-kit)`,
    ]);
    expect(
      scopeComplexSelector(
        '.recreation-kit [data-kit-presence="collapsed"]',
        sceneId,
        "descendants",
      ),
    ).toEqual([`${sceneRoot} :is(.recreation-kit [data-kit-presence="collapsed"])`]);
    expect(scopeComplexSelector("*::before", sceneId, "root-and-descendants")).toEqual([
      `${sceneRoot}:is(*)::before`,
      `${sceneRoot} :is(*)::before`,
    ]);
  });

  it("pairs each distinct element selector with its probe", () => {
    // Arrange
    const rules: readonly SourceCssRule[] = [
      styleRule(".a, .a:hover", [["color", "red"]]),
      {
        kind: "group",
        prelude: "@media (width >= 40rem)",
        layerName: null,
        rules: [styleRule(".b::before, html", [["color", "blue"]])],
      },
    ];

    // Act
    const selectorProbes = collectSelectorProbes(rules);

    // Assert
    expect(selectorProbes).toEqual([
      { selector: ".a", probe: ".a" },
      { selector: ".a:hover", probe: ".a" },
      { selector: ".b::before", probe: ".b" },
    ]);
  });
});

describe("scoped scene stylesheet", () => {
  it("keeps only rules that reach the scene and scopes every selector", () => {
    // Arrange
    const rules: readonly SourceCssRule[] = [
      styleRule(".recreation-kit", [["position", "relative"]]),
      styleRule(".site-header", [["position", "sticky"]]),
      {
        kind: "group",
        prelude: "@container recreation-kit (width <= 540px)",
        layerName: null,
        rules: [styleRule(".kit-window", [["font-size", "14px"]])],
      },
      {
        kind: "group",
        prelude: "@media (width >= 64rem)",
        layerName: null,
        rules: [styleRule(".site-footer", [["display", "grid"]])],
      },
    ];

    // Act
    const cssText = buildStylesheet(rules, {
      ".recreation-kit": "root",
      ".site-header": "none",
      ".kit-window": "descendants",
      ".site-footer": "none",
    });

    // Assert
    expect(cssText).toContain(`${sceneRoot}:is(.recreation-kit) { position: relative; }`);
    expect(cssText).toContain("@container recreation-kit (width <= 540px) {");
    expect(cssText).toContain(`${sceneRoot} :is(.kit-window) { font-size: 14px; }`);
    expect(cssText).not.toContain("site-header");
    expect(cssText).not.toContain("@media");
  });

  it("moves inherited document typography and referenced variables onto the scene root", () => {
    // Arrange
    const rules: readonly SourceCssRule[] = [
      styleRule(":root, :host", [
        ["--font-product", "Inter"],
        ["--color-unused", "red"],
      ]),
      styleRule("html", [
        ["line-height", "1.5"],
        ["font-family", "var(--font-product)"],
        ["background-color", "black"],
      ]),
      styleRule(".kit-window", [["color", "white"]]),
    ];

    // Act
    const cssText = buildStylesheet(rules, { ".kit-window": "descendants" });

    // Assert
    expect(cssText).toContain(`${sceneRoot} { --font-product: Inter; }`);
    expect(cssText).toContain(
      `${sceneRoot} { line-height: 1.5; font-family: var(--font-product); }`,
    );
    expect(cssText).not.toContain("--color-unused");
    expect(cssText).not.toContain("background-color");
  });

  it("renames cascade layers so they cannot merge with the host's layers", () => {
    // Arrange
    const rules: readonly SourceCssRule[] = [
      { kind: "layer-statement", layerNames: ["theme", "base"] },
      {
        kind: "group",
        prelude: "@layer base",
        layerName: "base",
        rules: [styleRule("*", [["box-sizing", "border-box"]])],
      },
    ];

    // Act
    const cssText = buildStylesheet(rules, { "*": "root-and-descendants" });

    // Assert
    expect(cssText).toContain(`@layer ${sceneId}--theme, ${sceneId}--base;`);
    expect(cssText).toContain(`@layer ${sceneId}--base {`);
    expect(cssText).toContain(
      `${sceneRoot}:is(*), ${sceneRoot} :is(*) { box-sizing: border-box; }`,
    );
  });

  it("drops custom properties nothing reads, keeping those the markup reads", () => {
    // Arrange
    const rules: readonly SourceCssRule[] = [
      styleRule("*", [
        ["--tw-shadow", "0 0 #0000"],
        ["--kit-canvas", "#282c34"],
      ]),
    ];

    // Act
    const cssText = buildStylesheet(
      rules,
      { "*": "root-and-descendants" },
      '<div style="background: var(--kit-canvas)"></div>',
    );

    // Assert
    expect(cssText).toContain("--kit-canvas: #282c34;");
    expect(cssText).not.toContain("--tw-shadow");
  });

  it("keeps a custom property read only through a shorthand", () => {
    // Arrange
    const rules: readonly SourceCssRule[] = [
      styleRule(".recreation-kit", [["--kit-chrome", "#1f1f1f"]]),
      styleRule(".kit-window", [["background", "var(--kit-chrome)"]]),
    ];

    // Act
    const cssText = buildStylesheet(rules, {
      ".recreation-kit": "root",
      ".kit-window": "descendants",
    });

    // Assert
    expect(cssText).toContain("--kit-chrome: #1f1f1f;");
    expect(cssText).toContain("background: var(--kit-chrome);");
  });

  it("splits declarations without breaking values that hold semicolons or colons", () => {
    // Arrange / Act
    const declarations = splitDeclarations(
      'content: "a;b"; background: url(data:image/png;base64,AA) !important; --x: 1;',
    );

    // Assert
    expect(declarations).toEqual([
      { property: "content", value: '"a;b"', important: false },
      { property: "background", value: "url(data:image/png;base64,AA)", important: true },
      { property: "--x", value: "1", important: false },
    ]);
  });

  it("refuses scene CSS it cannot make self-contained", () => {
    // Arrange
    const withUrl = [styleRule(".kit-icon", [["background-image", 'url("/icon.svg")']])];
    const withFont: readonly SourceCssRule[] = [
      { kind: "font-face", fontFamily: "Inter Display" },
      styleRule(".kit-window", [["font-family", '"Inter Display", sans-serif']]),
    ];
    const withKeyframes: readonly SourceCssRule[] = [
      { kind: "keyframes", name: "blink" },
      styleRule(".kit-cursor", [["animation-name", "blink"]]),
    ];

    // Act / Assert
    expect(() => buildStylesheet(withUrl, { ".kit-icon": "descendants" })).toThrow(/url\(/);
    expect(() => buildStylesheet(withFont, { ".kit-window": "descendants" })).toThrow(
      /Inter Display/,
    );
    expect(() => buildStylesheet(withKeyframes, { ".kit-cursor": "descendants" })).toThrow(/blink/);
  });
});

describe("phone breakpoint", () => {
  it("reads the one max width the scene's container queries share", () => {
    // Arrange
    const preludes = [
      "@container recreation-kit (width <= 540px)",
      "@container recreation-kit (max-width: 540px)",
      "@media (width >= 64rem)",
    ];

    // Act
    const breakpoint = resolvePhoneBreakpoint(preludes, "recreation-kit");

    // Assert
    expect(breakpoint).toEqual({ containerName: "recreation-kit", maxWidthPx: 540 });
  });

  it("refuses scenes whose container queries disagree or are missing", () => {
    // Arrange / Act / Assert
    expect(() =>
      resolvePhoneBreakpoint(
        [
          "@container recreation-kit (width <= 540px)",
          "@container recreation-kit (width <= 600px)",
        ],
        "recreation-kit",
      ),
    ).toThrow(/540.*600|disagree/);
    expect(() => resolvePhoneBreakpoint([], "recreation-kit")).toThrow(/no phone/i);
  });
});
