// A scene.js must load as one synchronous classic script: no module syntax,
// no network, no deferred setup. Reading the syntax tree keeps fixture text
// such as the "import type " a recreated code view shows from counting.

import { parseSync } from "vite";

const forbiddenNodeTypes: ReadonlySet<string> = new Set([
  "ImportDeclaration",
  "ImportExpression",
  "ExportNamedDeclaration",
  "ExportDefaultDeclaration",
  "ExportAllDeclaration",
  "AwaitExpression",
]);

const forbiddenGlobals: ReadonlySet<string> = new Set([
  "fetch",
  "XMLHttpRequest",
  "WebSocket",
  "EventSource",
  "importScripts",
  "setTimeout",
  "setInterval",
  "requestAnimationFrame",
  "requestIdleCallback",
  "queueMicrotask",
]);

const globalObjectNames: ReadonlySet<string> = new Set(["window", "globalThis", "self"]);

interface SyntaxNode {
  readonly type: string;
  readonly [key: string]: unknown;
}

function isSyntaxNode(value: unknown): value is SyntaxNode {
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { readonly type?: unknown }).type === "string"
  );
}

function identifierName(value: unknown): string | undefined {
  if (!isSyntaxNode(value) || value.type !== "Identifier") {
    return undefined;
  }
  return typeof value["name"] === "string" ? value["name"] : undefined;
}

/** Child nodes in source order, minus names that are not references. */
function childNodes(node: SyntaxNode): readonly SyntaxNode[] {
  const skippedKeys = new Set<string>(["type", "start", "end", "range", "loc"]);
  // `labels.fetch` and `{ fetch: 1 }` name a property, not the global.
  if ((node.type === "MemberExpression" || node.type === "Property") && node["computed"] !== true) {
    skippedKeys.add(node.type === "MemberExpression" ? "property" : "key");
  }
  return Object.entries(node)
    .filter(([key]) => !skippedKeys.has(key))
    .flatMap(([, value]) => (Array.isArray(value) ? value : [value]))
    .filter(isSyntaxNode);
}

function describeForbiddenNode(node: SyntaxNode): string | undefined {
  if (forbiddenNodeTypes.has(node.type)) {
    return node.type;
  }
  if (node.type === "MetaProperty" && identifierName(node["meta"]) === "import") {
    return "import.meta";
  }
  const referencedName = identifierName(node);
  if (referencedName !== undefined && forbiddenGlobals.has(referencedName)) {
    return referencedName;
  }
  if (
    node.type === "MemberExpression" &&
    node["computed"] !== true &&
    globalObjectNames.has(identifierName(node["object"]) ?? "")
  ) {
    const propertyName = identifierName(node["property"]);
    if (propertyName !== undefined && forbiddenGlobals.has(propertyName)) {
      return propertyName;
    }
  }
  return undefined;
}

/** Forbidden constructs in source order; empty when the script is self-contained. */
export function findForbiddenSceneScriptSyntax(scriptText: string): readonly string[] {
  const findings: string[] = [];
  const visit = (node: SyntaxNode): void => {
    const finding = describeForbiddenNode(node);
    if (finding !== undefined) {
      findings.push(finding);
    }
    childNodes(node).forEach(visit);
  };
  const parsed = parseSync("scene.js", scriptText);
  const [parseError] = parsed.errors;
  if (parseError !== undefined) {
    throw new Error(`The scene script does not parse: ${parseError.message}`);
  }
  const program: unknown = parsed.program;
  if (!isSyntaxNode(program)) {
    throw new Error("The scene script did not parse to a syntax tree.");
  }
  visit(program);
  return findings;
}
