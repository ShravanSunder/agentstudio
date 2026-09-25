// Turns the built site's CSS into one scene's self-contained stylesheet: keep
// the rules whose subject reaches the scene, scope every selector under the
// scene root, and move inherited document typography onto that root.

import {
  isDocumentLevelSelector,
  scanCssText,
  sceneRootSelector,
  scopeComplexSelector,
  selectorMatchProbe,
  splitSelectorList,
} from "./scene-selector-scoping.ts";
import type {
  PhoneBreakpoint,
  SelectorProbe,
  SelectorReach,
  SourceCssDeclaration,
  SourceCssRule,
} from "./scene-stylesheet-model.ts";

// Only inherited properties reach the scene from the document; a page
// background or margin on <html>/<body> is not part of the scene.
const inheritedProperties: ReadonlySet<string> = new Set([
  "border-collapse",
  "border-spacing",
  "caption-side",
  "caret-color",
  "color",
  "color-scheme",
  "cursor",
  "direction",
  "empty-cells",
  "font",
  "font-family",
  "font-feature-settings",
  "font-kerning",
  "font-optical-sizing",
  "font-size",
  "font-size-adjust",
  "font-stretch",
  "font-style",
  "font-synthesis",
  "font-synthesis-small-caps",
  "font-synthesis-style",
  "font-synthesis-weight",
  "font-variant",
  "font-variant-alternates",
  "font-variant-caps",
  "font-variant-east-asian",
  "font-variant-ligatures",
  "font-variant-numeric",
  "font-variant-position",
  "font-variation-settings",
  "font-weight",
  "hyphens",
  "letter-spacing",
  "line-break",
  "line-height",
  "list-style",
  "list-style-image",
  "list-style-position",
  "list-style-type",
  "orphans",
  "overflow-wrap",
  "paint-order",
  "quotes",
  "tab-size",
  "text-align",
  "text-align-last",
  "text-decoration-skip-ink",
  "text-indent",
  "text-rendering",
  "text-shadow",
  "text-size-adjust",
  "text-transform",
  "text-underline-offset",
  "text-underline-position",
  "text-wrap",
  "text-wrap-mode",
  "text-wrap-style",
  "visibility",
  "white-space",
  "white-space-collapse",
  "widows",
  "word-break",
  "word-spacing",
  "writing-mode",
  "-webkit-font-smoothing",
  "-webkit-tap-highlight-color",
  "-webkit-text-size-adjust",
]);

/** Splits a declaration block's text at top-level semicolons. */
export function splitDeclarations(declarationsText: string): readonly SourceCssDeclaration[] {
  const segments: string[] = [];
  let start = 0;
  for (const step of scanCssText(declarationsText)) {
    if (step.topLevel && step.character === ";") {
      segments.push(declarationsText.slice(start, step.index));
      start = step.index + 1;
    }
  }
  segments.push(declarationsText.slice(start));
  return segments
    .map((segment) => segment.trim())
    .filter((segment) => segment !== "")
    .map((segment): SourceCssDeclaration => {
      const colon = scanCssText(segment).find((step) => step.topLevel && step.character === ":");
      if (colon === undefined) {
        throw new Error(`Malformed CSS declaration: ${segment}`);
      }
      const rawValue = segment.slice(colon.index + 1).trim();
      const important = /\s*!important$/i.test(rawValue);
      return {
        property: segment.slice(0, colon.index).trim(),
        value: important ? rawValue.replace(/\s*!important$/i, "") : rawValue,
        important,
      };
    });
}

function forEachStyleRule(
  rules: readonly SourceCssRule[],
  visit: (rule: Extract<SourceCssRule, { kind: "style" }>) => void,
): void {
  for (const rule of rules) {
    if (rule.kind === "style") {
      visit(rule);
    } else if (rule.kind === "group") {
      forEachStyleRule(rule.rules, visit);
    }
  }
}

/** Every distinct element selector in the rules, with its match probe. */
export function collectSelectorProbes(rules: readonly SourceCssRule[]): readonly SelectorProbe[] {
  const probeBySelector = new Map<string, string>();
  forEachStyleRule(rules, (rule) => {
    for (const complexSelector of splitSelectorList(rule.selectorText)) {
      if (!isDocumentLevelSelector(complexSelector)) {
        probeBySelector.set(complexSelector, selectorMatchProbe(complexSelector));
      }
    }
  });
  return Array.from(probeBySelector, ([selector, probe]) => ({ selector, probe }));
}

export interface BuildScopedSceneStylesheetProps {
  readonly sceneId: string;
  readonly rules: readonly SourceCssRule[];
  /** Reach of each complex selector; unsupported selectors reach nothing. */
  readonly reachBySelector: ReadonlyMap<string, SelectorReach>;
  /** The settled markup; its inline styles read custom properties too. */
  readonly sceneMarkup: string;
}

export interface ScopedSceneStylesheet {
  readonly cssText: string;
  /** Preludes of every emitted group rule, for reading the phone breakpoint. */
  readonly groupPreludes: readonly string[];
}

/** A kept rule before custom properties nothing reads are dropped. */
type ScopedRule =
  | {
      readonly kind: "style";
      readonly selectors: readonly string[];
      readonly source: Extract<SourceCssRule, { kind: "style" }>;
      /** Document-level rules keep only their inherited declarations. */
      readonly declarations: readonly SourceCssDeclaration[];
    }
  | { readonly kind: "group"; readonly prelude: string; readonly rules: readonly ScopedRule[] }
  | { readonly kind: "layer-statement"; readonly layerNames: readonly string[] };

function renameLayer(sceneId: string, layerName: string): string {
  return layerName === "" ? "" : `${sceneId}--${layerName}`;
}

function reachOfSelector(
  complexSelector: string,
  reachBySelector: ReadonlyMap<string, SelectorReach>,
): SelectorReach {
  const reach = reachBySelector.get(complexSelector);
  if (reach === undefined) {
    throw new Error(`No match result for selector "${complexSelector}".`);
  }
  return reach;
}

function scopeStyleRule(
  rule: Extract<SourceCssRule, { kind: "style" }>,
  props: BuildScopedSceneStylesheetProps,
): readonly ScopedRule[] {
  const complexSelectors = splitSelectorList(rule.selectorText);
  const declarations = splitDeclarations(rule.declarationsText);
  const documentLevel = complexSelectors.filter(isDocumentLevelSelector);
  const scopedSelectors = complexSelectors
    .filter((complexSelector) => !isDocumentLevelSelector(complexSelector))
    .flatMap((complexSelector) => {
      const reach = reachOfSelector(complexSelector, props.reachBySelector);
      return reach === "none" ? [] : scopeComplexSelector(complexSelector, props.sceneId, reach);
    });
  const scopedRules: ScopedRule[] = [];
  if (documentLevel.length > 0) {
    scopedRules.push({
      kind: "style",
      selectors: [sceneRootSelector(props.sceneId)],
      source: rule,
      declarations: declarations.filter(
        (declaration) =>
          declaration.property.startsWith("--") || inheritedProperties.has(declaration.property),
      ),
    });
  }
  if (scopedSelectors.length > 0) {
    scopedRules.push({ kind: "style", selectors: scopedSelectors, source: rule, declarations });
  }
  if (scopedRules.length > 0 && rule.nestedRuleCount > 0) {
    throw new Error(`Nested CSS rules are not supported in scene CSS: "${rule.selectorText}".`);
  }
  return scopedRules;
}

function scopeRules(
  rules: readonly SourceCssRule[],
  props: BuildScopedSceneStylesheetProps,
): readonly ScopedRule[] {
  return rules.flatMap((rule): readonly ScopedRule[] => {
    switch (rule.kind) {
      case "style":
        return scopeStyleRule(rule, props);
      case "group": {
        const children = scopeRules(rule.rules, props);
        if (children.length === 0) {
          return [];
        }
        const prelude =
          rule.layerName === null
            ? rule.prelude
            : `@layer ${renameLayer(props.sceneId, rule.layerName)}`.trimEnd();
        return [{ kind: "group", prelude, rules: children }];
      }
      case "layer-statement":
        return [
          {
            kind: "layer-statement",
            layerNames: rule.layerNames.map((layerName) => renameLayer(props.sceneId, layerName)),
          },
        ];
      case "unsupported-group":
        throw new Error(`Scene CSS scoping does not support this rule: ${rule.cssText}`);
      case "keyframes":
      case "font-face":
      case "registered-property":
      case "ignored-statement":
        return [];
      default: {
        const unhandledRule: never = rule;
        throw new Error(`Unhandled CSS rule: ${JSON.stringify(unhandledRule)}`);
      }
    }
  });
}

function forEachScopedStyleRule(
  rules: readonly ScopedRule[],
  visit: (rule: Extract<ScopedRule, { kind: "style" }>) => void,
): void {
  for (const rule of rules) {
    if (rule.kind === "style") {
      visit(rule);
    } else if (rule.kind === "group") {
      forEachScopedStyleRule(rule.rules, visit);
    }
  }
}

const customPropertyReferencePattern = /var\(\s*(--[\w-]+)/g;

function readCustomPropertyReferences(text: string): readonly string[] {
  return Array.from(text.matchAll(customPropertyReferencePattern), (match) => match[1] ?? "");
}

/** Custom properties some kept declaration or the markup reads, transitively. */
function collectReferencedCustomProperties(
  rules: readonly ScopedRule[],
  sceneMarkup: string,
): ReadonlySet<string> {
  const valuesByCustomProperty = new Map<string, string[]>();
  const referenced = new Set<string>(readCustomPropertyReferences(sceneMarkup));
  forEachScopedStyleRule(rules, (rule) => {
    for (const declaration of rule.declarations) {
      if (declaration.property.startsWith("--")) {
        const values = valuesByCustomProperty.get(declaration.property) ?? [];
        values.push(declaration.value);
        valuesByCustomProperty.set(declaration.property, values);
      } else {
        readCustomPropertyReferences(declaration.value).forEach((name) => referenced.add(name));
      }
    }
  });
  const pending = Array.from(referenced);
  while (pending.length > 0) {
    const name = pending.pop() ?? "";
    for (const value of valuesByCustomProperty.get(name) ?? []) {
      for (const reference of readCustomPropertyReferences(value)) {
        if (!referenced.has(reference)) {
          referenced.add(reference);
          pending.push(reference);
        }
      }
    }
  }
  return referenced;
}

interface SelfContainmentSources {
  readonly keyframesNames: ReadonlySet<string>;
  readonly fontFaceFamilies: ReadonlySet<string>;
  readonly registeredProperties: ReadonlySet<string>;
}

function collectSelfContainmentSources(rules: readonly SourceCssRule[]): SelfContainmentSources {
  const keyframesNames = new Set<string>();
  const fontFaceFamilies = new Set<string>();
  const registeredProperties = new Set<string>();
  const visit = (visitedRules: readonly SourceCssRule[]): void => {
    for (const rule of visitedRules) {
      if (rule.kind === "keyframes") {
        keyframesNames.add(rule.name);
      } else if (rule.kind === "font-face") {
        fontFaceFamilies.add(rule.fontFamily.replace(/^["']|["']$/g, ""));
      } else if (rule.kind === "registered-property") {
        registeredProperties.add(rule.name);
      } else if (rule.kind === "group") {
        visit(rule.rules);
      }
    }
  };
  visit(rules);
  return { keyframesNames, fontFaceFamilies, registeredProperties };
}

/**
 * The bundle ships no fonts, images, keyframes, or property registrations. A
 * kept rule that needs one fails the build instead of rendering differently.
 */
function assertSelfContained(
  rules: readonly ScopedRule[],
  sources: SelfContainmentSources,
  referencedCustomProperties: ReadonlySet<string>,
): void {
  forEachScopedStyleRule(rules, (rule) => {
    for (const declaration of rule.declarations) {
      const where = `"${rule.source.selectorText}" ${declaration.property}`;
      if (/url\(/i.test(declaration.value)) {
        throw new Error(`Scene CSS would load a url() asset: ${where}: ${declaration.value}`);
      }
      if (declaration.property === "animation" || declaration.property === "animation-name") {
        const missing = declaration.value
          .split(/[\s,]+/)
          .find((name) => sources.keyframesNames.has(name));
        if (missing !== undefined) {
          throw new Error(`Scene CSS needs @keyframes ${missing}, which bundles cannot scope yet.`);
        }
      }
      if (declaration.property === "font" || declaration.property === "font-family") {
        const family = Array.from(sources.fontFaceFamilies).find((fontFamily) =>
          declaration.value.includes(fontFamily),
        );
        if (family !== undefined) {
          throw new Error(
            `Scene CSS needs the web font "${family}"; bundles ship system fonts only.`,
          );
        }
      }
    }
  });
  const registered = Array.from(sources.registeredProperties).find((name) =>
    referencedCustomProperties.has(name),
  );
  if (registered !== undefined) {
    throw new Error(`Scene CSS reads @property ${registered}, which bundles cannot register.`);
  }
}

function serializeDeclarations(declarations: readonly SourceCssDeclaration[]): string {
  return declarations
    .map(
      (declaration) =>
        `${declaration.property}: ${declaration.value}${declaration.important ? " !important" : ""};`,
    )
    .join(" ");
}

function serializeRules(
  rules: readonly ScopedRule[],
  referencedCustomProperties: ReadonlySet<string>,
  indent: string,
): readonly string[] {
  return rules.flatMap((rule): readonly string[] => {
    switch (rule.kind) {
      case "layer-statement":
        return [`${indent}@layer ${rule.layerNames.join(", ")};`];
      case "group": {
        const children = serializeRules(rule.rules, referencedCustomProperties, `${indent}  `);
        return children.length === 0
          ? []
          : [`${indent}${rule.prelude} {`, ...children, `${indent}}`];
      }
      case "style": {
        const kept = rule.declarations.filter(
          (declaration) =>
            !declaration.property.startsWith("--") ||
            referencedCustomProperties.has(declaration.property),
        );
        if (kept.length === 0) {
          return [];
        }
        return [`${indent}${rule.selectors.join(", ")} { ${serializeDeclarations(kept)} }`];
      }
      default: {
        const unhandledRule: never = rule;
        throw new Error(`Unhandled scoped rule: ${JSON.stringify(unhandledRule)}`);
      }
    }
  });
}

function collectGroupPreludes(rules: readonly ScopedRule[]): readonly string[] {
  return rules.flatMap((rule): readonly string[] =>
    rule.kind === "group" ? [rule.prelude, ...collectGroupPreludes(rule.rules)] : [],
  );
}

export function buildScopedSceneStylesheet(
  props: BuildScopedSceneStylesheetProps,
): ScopedSceneStylesheet {
  const scopedRules = scopeRules(props.rules, props);
  const referencedCustomProperties = collectReferencedCustomProperties(
    scopedRules,
    props.sceneMarkup,
  );
  assertSelfContained(
    scopedRules,
    collectSelfContainmentSources(props.rules),
    referencedCustomProperties,
  );
  return {
    cssText: `${serializeRules(scopedRules, referencedCustomProperties, "").join("\n")}\n`,
    groupPreludes: collectGroupPreludes(scopedRules),
  };
}

const containerMaxWidthPattern = /\(\s*(?:max-width\s*:\s*|width\s*<=\s*)(\d+(?:\.\d+)?)px\s*\)/;

/**
 * The stage width at and below which the scene shows its phone crop: the one
 * max width every `@container <kit>` query in the scene CSS agrees on.
 */
export function resolvePhoneBreakpoint(
  groupPreludes: readonly string[],
  containerName: string,
): PhoneBreakpoint {
  const containerPrefix = `@container ${containerName} `;
  const maxWidths = new Set<number>();
  for (const prelude of groupPreludes) {
    if (!prelude.startsWith(containerPrefix)) {
      continue;
    }
    const match = containerMaxWidthPattern.exec(prelude);
    if (match?.[1] === undefined) {
      throw new Error(`Unrecognized phone container query: ${prelude}`);
    }
    maxWidths.add(Number(match[1]));
  }
  if (maxWidths.size === 0) {
    throw new Error(`Scene CSS has no phone container query on "${containerName}".`);
  }
  if (maxWidths.size > 1) {
    throw new Error(
      `Scene container queries disagree on the phone breakpoint: ${Array.from(maxWidths).join(", ")}px.`,
    );
  }
  return { containerName, maxWidthPx: Array.from(maxWidths)[0] ?? 0 };
}
