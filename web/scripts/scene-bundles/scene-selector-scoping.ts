// Selector handling for scene CSS: split selector lists, find the element a
// selector styles, and scope that element under the scene root.

import type { SelectorReach } from "./scene-stylesheet-model.ts";

export function sceneRootSelector(sceneId: string): string {
  return `[data-scene-root="${sceneId}"]`;
}

// Selectors that style the document rather than an element in it. In the
// bundle they become the scene root, which stands in for the page around it.
const documentLevelSelectors: ReadonlySet<string> = new Set(["html", ":root", ":host", "body"]);

// Pointer and focus state never holds in a rendered frame, so probes ignore it
// and the scoped rule keeps it.
const interactionPseudoClasses: ReadonlySet<string> = new Set([
  "active",
  "focus",
  "focus-visible",
  "focus-within",
  "hover",
  "target",
  "visited",
]);

// CSS2 pseudo-elements that may still be spelled with one colon.
const legacyPseudoElements: ReadonlySet<string> = new Set([
  "after",
  "before",
  "first-letter",
  "first-line",
]);

const combinatorCharacters: ReadonlySet<string> = new Set([" ", ">", "+", "~"]);

export interface SelectorScanStep {
  readonly index: number;
  readonly character: string;
  readonly topLevel: boolean;
}

/** Walks selector or declaration text, skipping escapes and strings, tracking bracket depth. */
export function scanCssText(selector: string): readonly SelectorScanStep[] {
  const steps: SelectorScanStep[] = [];
  let depth = 0;
  let quote: string | null = null;
  for (let index = 0; index < selector.length; index += 1) {
    const character = selector.charAt(index);
    if (character === "\\") {
      steps.push({ index, character, topLevel: false });
      index += 1;
      continue;
    }
    if (quote !== null) {
      if (character === quote) {
        quote = null;
      }
      steps.push({ index, character, topLevel: false });
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      steps.push({ index, character, topLevel: false });
      continue;
    }
    if (character === "(" || character === "[") {
      steps.push({ index, character, topLevel: depth === 0 });
      depth += 1;
      continue;
    }
    if (character === ")" || character === "]") {
      depth -= 1;
      steps.push({ index, character, topLevel: depth === 0 });
      continue;
    }
    steps.push({ index, character, topLevel: depth === 0 });
  }
  return steps;
}

export function splitSelectorList(selectorText: string): readonly string[] {
  const complexSelectors: string[] = [];
  let start = 0;
  for (const step of scanCssText(selectorText)) {
    if (step.topLevel && step.character === ",") {
      complexSelectors.push(selectorText.slice(start, step.index).trim());
      start = step.index + 1;
    }
  }
  complexSelectors.push(selectorText.slice(start).trim());
  return complexSelectors.filter((complexSelector) => complexSelector !== "");
}

function readIdentifier(selector: string, start: number): string {
  const match = /^-?[a-zA-Z_][\w-]*/.exec(selector.slice(start));
  return match?.[0] ?? "";
}

interface SubjectParts {
  /** Everything before the pseudo-element, or the whole selector. */
  readonly element: string;
  /** The pseudo-element and anything after it, or an empty string. */
  readonly pseudoElement: string;
}

/** Separates a trailing pseudo-element, which cannot sit inside :is(). */
function splitPseudoElement(complexSelector: string): SubjectParts {
  for (const step of scanCssText(complexSelector)) {
    if (!step.topLevel || step.character !== ":") {
      continue;
    }
    const isDoubleColon = complexSelector.charAt(step.index + 1) === ":";
    const name = readIdentifier(complexSelector, step.index + (isDoubleColon ? 2 : 1));
    if (isDoubleColon || legacyPseudoElements.has(name.toLowerCase())) {
      const before = complexSelector.slice(0, step.index);
      const trimmed = before.trimEnd();
      // `::before`, `.a ::before` and `.a > ::before` style an implicit `*`.
      const subjectIsImplicit =
        trimmed === "" || before !== trimmed || combinatorCharacters.has(trimmed.slice(-1));
      return {
        element: subjectIsImplicit ? `${before}*` : before,
        pseudoElement: complexSelector.slice(step.index),
      };
    }
  }
  return { element: complexSelector, pseudoElement: "" };
}

interface CompoundStep {
  /** " ", ">", "+" or "~"; null for the first compound. */
  readonly combinator: string | null;
  readonly compound: string;
}

function splitCompounds(complexSelector: string): readonly CompoundStep[] {
  const compounds: CompoundStep[] = [];
  let combinator: string | null = null;
  let compound = "";
  let inCombinator = false;
  for (const step of scanCssText(complexSelector.trim())) {
    const text =
      step.character === "\\"
        ? complexSelector.trim().slice(step.index, step.index + 2)
        : step.character;
    if (step.topLevel && combinatorCharacters.has(step.character)) {
      if (!inCombinator) {
        compounds.push({ combinator, compound });
        combinator = " ";
        compound = "";
        inCombinator = true;
      }
      if (step.character !== " ") {
        combinator = step.character;
      }
      continue;
    }
    inCombinator = false;
    compound += text;
  }
  compounds.push({ combinator, compound });
  return compounds;
}

function joinCompounds(compounds: readonly CompoundStep[]): string {
  return compounds
    .map(({ combinator, compound }) => {
      if (combinator === null) {
        return compound;
      }
      return combinator === " " ? ` ${compound}` : ` ${combinator} ${compound}`;
    })
    .join("");
}

function removeInteractionPseudoClasses(selector: string): string {
  let result = "";
  let skipUntil = -1;
  for (const step of scanCssText(selector)) {
    if (step.index < skipUntil) {
      continue;
    }
    if (step.topLevel && step.character === ":" && selector.charAt(step.index + 1) !== ":") {
      const name = readIdentifier(selector, step.index + 1);
      const end = step.index + 1 + name.length;
      if (interactionPseudoClasses.has(name.toLowerCase()) && selector.charAt(end) !== "(") {
        skipUntil = end;
        continue;
      }
    }
    result += selector.slice(step.index, step.character === "\\" ? step.index + 2 : step.index + 1);
  }
  return result;
}

/**
 * The selector for the element a rule styles, testable with `matches()`:
 * no pseudo-element and no pointer or focus state.
 */
export function selectorMatchProbe(complexSelector: string): string {
  const { element } = splitPseudoElement(complexSelector);
  return joinCompounds(
    splitCompounds(element).map(({ combinator, compound }) => {
      const withoutInteraction = removeInteractionPseudoClasses(compound);
      return { combinator, compound: withoutInteraction === "" ? "*" : withoutInteraction };
    }),
  );
}

export function isDocumentLevelSelector(complexSelector: string): boolean {
  return documentLevelSelectors.has(complexSelector.trim().toLowerCase());
}

/**
 * `R:is(S)` styles the scene root; `R :is(S)` styles elements under it. S keeps
 * its own ancestors, so a rule like `.recreation-kit .x` still means what it
 * meant on the page, and nothing outside R can match.
 */
export function scopeComplexSelector(
  complexSelector: string,
  sceneId: string,
  reach: Exclude<SelectorReach, "none">,
): readonly string[] {
  const root = sceneRootSelector(sceneId);
  const { element, pseudoElement } = splitPseudoElement(complexSelector);
  const scopedSelectors: string[] = [];
  if (reach === "root" || reach === "root-and-descendants") {
    scopedSelectors.push(`${root}:is(${element})${pseudoElement}`);
  }
  if (reach === "descendants" || reach === "root-and-descendants") {
    scopedSelectors.push(`${root} :is(${element})${pseudoElement}`);
  }
  return scopedSelectors;
}
