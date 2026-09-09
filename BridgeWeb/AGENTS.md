# BridgeWeb Agent Rules

BridgeWeb is the React app embedded by Agent Studio Bridge. Follow the root
`AGENTS.md` first for import, proof, and Performance Lane hops, then these
BridgeWeb-specific rules. The Vite command loop lives in
[Agent Resources — BridgeWeb Fast UI Loop](../docs/guides/agent_resources.md#bridgeweb-fast-ui-loop), not in root `AGENTS.md`.

## Architecture Sources

- Start with [Bridge Viewer Architecture — System Map](../docs/architecture/bridge/bridge_viewer_architecture.md#system-map)
  for the end-to-end ownership and data-flow map.
- [Bridge Web Runtime Architecture — Runtime Topology](../docs/architecture/bridge/bridge_web_runtime_architecture.md#runtime-topology)
  is the source of truth for BridgeWeb workers, stores, demand, rendering, and
  browser proof.
- Use [Bridge Native Runtime Architecture — Ownership Map](../docs/architecture/bridge/bridge_native_runtime_architecture.md#ownership-map)
  when changing the WebKit, scheme, session, or protocol boundary.

## UI Components

Read progressively: root AGENTS.md → this section →
[component language contract](../docs/architecture/bridge/bridgeweb_design_token_architecture.md#component-language-contract)
for hierarchy/composition → that document's token/state and enforcement sections
for recipe changes → the linked owning source and rendered tests.
The architecture contract owns current visual decisions; older trial specs are
not permission to restore superseded colors, sizes or panel layouts.
Audit all consumers of a changed shared recipe. Do not add a one-feature variant
to accommodate a screenshot without a distinct semantic role in the contract.

- Use owned shadcn-style primitives from `src/components/ui/` for React controls.
  If a needed primitive is missing, add or adapt the primitive there first.
- Do not hand-roll route-local buttons, toggles, segmented controls, inputs, or
  icon chrome when an owned primitive can express the interaction.
- Shared BridgeViewer chrome belongs in shared app/component modules, not in
  FileViewer-only or ReviewViewer-only visual language.
- FileViewer and ReviewViewer controls with the same interaction semantics must
  share scale, focus, hover, active, spacing, and icon sizing.
- [Design-token architecture](../docs/architecture/bridge/bridgeweb_design_token_architecture.md)
  owns the compact scale, semantic roles, annotation context, and effective Pierre bindings.
  CSS is canonical; the checked TypeScript mirror supplies static theme values.
- Primitives own all control/frame paint and geometry. Consumers select variants/sizes
  and arrange layout; do not append control styles, raw colors, or `--bridge-*` aliases.
  Use explicit neutral disabled paint at opacity 1 and unconditional dark recipes.
- Match native typography by role: list/tree titles `text-base`, metadata and input
  values `text-sm`, compact actions `text-xs`, auxiliary hints `text-2xs`. Compose
  descriptive rows with owned ItemContent/Label/Description/Metadata; do not style
  nested text locally. Features still own domain components and outer layout.
- Put element resets in `@layer base`, so utilities win without important overrides.
  The style-system checker runs in the normal check with zero migration allowances.

## BridgeViewer Proof

- React, DOM, and browser rendering tests use Vitest Browser, Playwright/dev-server,
  or native WKWebView proof. Pure logic tests stay Node-only and must not depend on
  browser globals.
- Browser proof for shared chrome must assert real geometry and screenshots:
  content header over the left content region only, right rail top-aligned,
  compact shared controls, and no standalone second app.
- A second agent/onlook should inspect screenshots and relevant source paths
  before a visible UX checkpoint is treated as ready.

## Rendering Ownership

- FileViewer and ReviewViewer must render through Pierre FileTree plus
  Pierre/Shiki CodeView/File paths with workers where the route enables workers.
- Do not replace Pierre/Shiki rendering with route-local file lists, `<pre>`
  renderers, or custom tree implementations for product proof.
- Large content bodies and render workers stay out of Zustand; Zustand stores
  navigation, selection, refs, and small facts only.

## Git Boundaries

Production Swift/native Git belongs to
[agentstudio-git](../docs/architecture/state/agentstudio_git.md#agentstudio-git).
TypeScript git helpers are allowed only in clearly marked Vite dev-server or
test fixture utilities.
