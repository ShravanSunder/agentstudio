// The built site's stylesheets as rules with their source text, so the scoping
// rules run in Node and stay unit-testable.

export interface SourceCssDeclaration {
  readonly property: string;
  readonly value: string;
  readonly important: boolean;
}

export type SourceCssRule =
  | {
      readonly kind: "style";
      readonly selectorText: string;
      /** The declaration block exactly as the build wrote it, shorthands intact. */
      readonly declarationsText: string;
      readonly nestedRuleCount: number;
    }
  | {
      /** @media, @container, @supports, @layer blocks and @starting-style. */
      readonly kind: "group";
      readonly prelude: string;
      /** Set for `@layer` blocks; an empty string is an anonymous layer. */
      readonly layerName: string | null;
      readonly rules: readonly SourceCssRule[];
    }
  | { readonly kind: "layer-statement"; readonly layerNames: readonly string[] }
  | { readonly kind: "keyframes"; readonly name: string }
  | { readonly kind: "font-face"; readonly fontFamily: string }
  | { readonly kind: "registered-property"; readonly name: string }
  /** A grouping rule the scoper does not understand, such as @scope. */
  | { readonly kind: "unsupported-group"; readonly cssText: string }
  /** A statement rule that carries no element selectors, such as @page. */
  | { readonly kind: "ignored-statement"; readonly cssText: string };

/**
 * Which elements of the isolated scene a selector's subject matches: the scene
 * root, elements under it, both, or none (the rule belongs to the page).
 */
export type SelectorReach = "root" | "descendants" | "root-and-descendants" | "none";

/** One complex selector and the selector for the element it styles. */
export interface SelectorProbe {
  readonly selector: string;
  readonly probe: string;
}

export interface PhoneBreakpoint {
  readonly containerName: string;
  readonly maxWidthPx: number;
}
