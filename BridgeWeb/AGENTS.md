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

Read the [component language contract](../docs/architecture/bridge/bridgeweb_design_token_architecture.md#component-language-contract)
and the affected composition before editing. Choose the task entry:

- Composition/content: identify the user task, visible choices and states; read
  the [matching pattern](../docs/architecture/bridge/bridgeweb_design_token_architecture.md#composition-patterns)
  and its current consumer before choosing controls.
- Shared recipe: also read the role/state contract, owning primitive, every
  affected consumer and its rendered tests.
- Portal, annotation or Pierre boundary: also read the relevant rendering section
  and inspect effective styling across that boundary.

Reuse existing owned shadcn slots unchanged when they fit. Keep domain behavior
and outer placement with the feature; change shared recipes only for a named
reusable meaning. Shared wrappers need shared composition or behavior, not merely
styling parity. Never append feature-local control paint or geometry.

Resolve contradictions between the contract and current source explicitly. Use
its [change-and-proof discipline](../docs/architecture/bridge/bridgeweb_design_token_architecture.md#change-and-proof-discipline).
WIP receipts and old screenshots are historical evidence, not acceptance of the
current candidate. Values and recipes have one authority; do not duplicate their
tables here or in another design.md.

## BridgeViewer Proof

- React, DOM, and browser rendering tests use Vitest Browser, Playwright/dev-server,
  or native WKWebView proof. Pure logic tests stay Node-only and must not depend on
  browser globals.
- Browser proof for shared chrome must assert real geometry and screenshots:
  content header over the left content region only, right rail top-aligned,
  compact shared controls, and no standalone second app.
- A second agent/onlook should inspect screenshots and relevant source paths
  before a visible UX checkpoint is treated as ready.

## Test Waits

- A wait completes because an application event or a DOM condition occurred,
  never because time passed.
- `testTimeout` is a hang bound, declared once in shared configuration. Never
  rely on an undeclared library default, and never tune it per test to obtain a
  pass — a wait that needs a longer bound is telling you what it waits on has no
  signal.
- An awaited animation is driven to completion by the test, or its cancellation
  is handled. Never await one unbounded or uncaught.
- Dependency-optimizer cold start stays outside a journey's bounded steps, and a
  retry must not repeat the cost that made the first attempt fail. Each live Vite
  server owns its own cache directory.

The standard is
[Testing Architecture — BridgeWeb](../docs/architecture/testing/testing_architecture.md#bridgeweb).

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
