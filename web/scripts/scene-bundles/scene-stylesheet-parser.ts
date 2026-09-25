// Reads the build's CSS into rules while keeping every declaration's source
// text. CSSOM cannot be the source here: it serializes a shorthand written with
// var() and later partly overridden (`border: 1px solid var(--x); border-bottom: 0`)
// as empty longhands, which silently drops the border.

import type { SourceCssRule } from "./scene-stylesheet-model.ts";

const groupAtRules: ReadonlySet<string> = new Set([
  "media",
  "container",
  "supports",
  "starting-style",
]);

// Blocks that carry no element selectors and so never style a scene.
const ignoredBlockAtRules: ReadonlySet<string> = new Set([
  "page",
  "counter-style",
  "font-palette-values",
  "font-feature-values",
  "view-transition",
  "position-try",
]);

/** Index just past the construct that starts at `index`: a string, comment, or escape. */
function skipOpaque(cssText: string, index: number): number {
  const character = cssText.charAt(index);
  if (character === "\\") {
    return index + 2;
  }
  if (character === '"' || character === "'") {
    let cursor = index + 1;
    while (cursor < cssText.length && cssText.charAt(cursor) !== character) {
      cursor += cssText.charAt(cursor) === "\\" ? 2 : 1;
    }
    return cursor + 1;
  }
  if (character === "/" && cssText.charAt(index + 1) === "*") {
    const end = cssText.indexOf("*/", index + 2);
    return end === -1 ? cssText.length : end + 2;
  }
  return index;
}

/** The first of `targets` at bracket depth zero, or -1. */
function findTopLevel(cssText: string, start: number, end: number, targets: string): number {
  let depth = 0;
  let index = start;
  while (index < end) {
    const skipped = skipOpaque(cssText, index);
    if (skipped !== index) {
      index = skipped;
      continue;
    }
    const character = cssText.charAt(index);
    if (depth === 0 && targets.includes(character)) {
      return index;
    }
    if (character === "(" || character === "[") {
      depth += 1;
    } else if (character === ")" || character === "]") {
      depth -= 1;
    }
    index += 1;
  }
  return -1;
}

function findMatchingBrace(cssText: string, openIndex: number): number {
  let depth = 0;
  let index = openIndex;
  while (index < cssText.length) {
    const skipped = skipOpaque(cssText, index);
    if (skipped !== index) {
      index = skipped;
      continue;
    }
    const character = cssText.charAt(index);
    if (character === "{") {
      depth += 1;
    } else if (character === "}") {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
    index += 1;
  }
  throw new Error(
    `Unbalanced braces in built CSS near: ${cssText.slice(openIndex, openIndex + 80)}`,
  );
}

function countTopLevelBlocks(cssText: string): number {
  let count = 0;
  let index = 0;
  while (index < cssText.length) {
    const open = findTopLevel(cssText, index, cssText.length, "{");
    if (open === -1) {
      return count;
    }
    count += 1;
    index = findMatchingBrace(cssText, open) + 1;
  }
  return count;
}

function readFontFaceFamily(declarationsText: string): string {
  const match = /(?:^|;)\s*font-family\s*:\s*([^;]+)/.exec(declarationsText);
  return match?.[1]?.trim() ?? "";
}

function readAtRule(name: string, prelude: string, body: string): SourceCssRule {
  const fullPrelude = `@${name}${prelude === "" ? "" : ` ${prelude}`}`;
  if (groupAtRules.has(name)) {
    return {
      kind: "group",
      prelude: fullPrelude,
      layerName: null,
      rules: parseBuiltStylesheet(body),
    };
  }
  if (name === "layer") {
    return {
      kind: "group",
      prelude: fullPrelude,
      layerName: prelude,
      rules: parseBuiltStylesheet(body),
    };
  }
  if (name === "keyframes" || name === "-webkit-keyframes") {
    return { kind: "keyframes", name: prelude };
  }
  if (name === "font-face") {
    return { kind: "font-face", fontFamily: readFontFaceFamily(body) };
  }
  if (name === "property") {
    return { kind: "registered-property", name: prelude };
  }
  if (ignoredBlockAtRules.has(name)) {
    return { kind: "ignored-statement", cssText: fullPrelude };
  }
  return { kind: "unsupported-group", cssText: fullPrelude };
}

export function parseBuiltStylesheet(cssText: string): readonly SourceCssRule[] {
  const rules: SourceCssRule[] = [];
  let index = 0;
  while (index < cssText.length) {
    const skipped = skipOpaque(cssText, index);
    if (skipped !== index || /\s/.test(cssText.charAt(index))) {
      index = skipped !== index ? skipped : index + 1;
      continue;
    }
    const blockOrEnd = findTopLevel(cssText, index, cssText.length, "{;");
    if (blockOrEnd === -1) {
      throw new Error(`Unterminated rule in built CSS: ${cssText.slice(index, index + 80)}`);
    }
    const head = cssText.slice(index, blockOrEnd).trim();
    if (cssText.charAt(blockOrEnd) === ";") {
      const statement = /^@([\w-]+)\s*(.*)$/s.exec(head);
      if (statement?.[1] === "layer") {
        rules.push({
          kind: "layer-statement",
          layerNames: (statement[2] ?? "").split(",").map((layerName) => layerName.trim()),
        });
      } else {
        rules.push({ kind: "ignored-statement", cssText: head });
      }
      index = blockOrEnd + 1;
      continue;
    }
    const close = findMatchingBrace(cssText, blockOrEnd);
    const body = cssText.slice(blockOrEnd + 1, close);
    const atRule = /^@([\w-]+)\s*(.*)$/s.exec(head);
    if (atRule?.[1] === undefined) {
      rules.push({
        kind: "style",
        selectorText: head,
        declarationsText: body.trim(),
        nestedRuleCount: countTopLevelBlocks(body),
      });
    } else {
      rules.push(readAtRule(atRule[1].toLowerCase(), (atRule[2] ?? "").trim(), body));
    }
    index = close + 1;
  }
  return rules;
}
