import { describe, expect, it } from "vitest";

import { parseBuiltStylesheet } from "../scripts/scene-bundles/scene-stylesheet-parser.ts";

describe("built stylesheet parser", () => {
  it("keeps each rule's declaration text exactly as the build wrote it", () => {
    // Arrange
    const builtCss =
      ".kit-drawer[data-astro-cid-q]{border:1px solid var(--kit-drawer-edge);border-bottom:0}" +
      '.kit-quote::before{content:"{;}"}';

    // Act
    const rules = parseBuiltStylesheet(builtCss);

    // Assert
    expect(rules).toEqual([
      {
        kind: "style",
        selectorText: ".kit-drawer[data-astro-cid-q]",
        declarationsText: "border:1px solid var(--kit-drawer-edge);border-bottom:0",
        nestedRuleCount: 0,
      },
      {
        kind: "style",
        selectorText: ".kit-quote::before",
        declarationsText: 'content:"{;}"',
        nestedRuleCount: 0,
      },
    ]);
  });

  it("reads group, layer, and statement at-rules", () => {
    // Arrange
    const builtCss = [
      "@layer theme,base;",
      "@layer base{*{margin:0}}",
      "@container recreation-kit (width<=540px){.kit-window{font-size:14px}}",
      "@keyframes blink{0%{opacity:0}to{opacity:1}}",
      '@font-face{font-family:"Inter Display";src:url(inter.woff2)}',
      '@property --tw-shadow{syntax:"*";inherits:false;initial-value:0 0 #0000}',
      "@scope (.card){img{width:1px}}",
    ].join("");

    // Act
    const rules = parseBuiltStylesheet(builtCss);

    // Assert
    expect(rules).toEqual([
      { kind: "layer-statement", layerNames: ["theme", "base"] },
      {
        kind: "group",
        prelude: "@layer base",
        layerName: "base",
        rules: [
          { kind: "style", selectorText: "*", declarationsText: "margin:0", nestedRuleCount: 0 },
        ],
      },
      {
        kind: "group",
        prelude: "@container recreation-kit (width<=540px)",
        layerName: null,
        rules: [
          {
            kind: "style",
            selectorText: ".kit-window",
            declarationsText: "font-size:14px",
            nestedRuleCount: 0,
          },
        ],
      },
      { kind: "keyframes", name: "blink" },
      { kind: "font-face", fontFamily: '"Inter Display"' },
      { kind: "registered-property", name: "--tw-shadow" },
      { kind: "unsupported-group", cssText: "@scope (.card)" },
    ]);
  });

  it("counts nested rules inside a style rule", () => {
    // Arrange / Act
    const [rule] = parseBuiltStylesheet(".a{color:red;&:hover{color:blue}}");

    // Assert
    expect(rule).toMatchObject({ kind: "style", selectorText: ".a", nestedRuleCount: 1 });
  });
});
