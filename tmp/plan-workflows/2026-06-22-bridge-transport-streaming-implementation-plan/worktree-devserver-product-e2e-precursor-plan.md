# Worktree Dev-Server Product E2E Precursor Plan

Date: 2026-06-24
Status: draft, pending spec-review-swarm and plan-review-swarm
Ticket: 06P Worktree Dev-Server Product E2E Precursor

## Problem

The current worktree dev URL boots a Worktree/File protocol route, but it is not
yet the intended product surface. The exact URL is:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

Current red evidence captured on 2026-06-24:

- HTTP bootstrap returns 200.
- `/__bridge-worktree/surface?scenario=current-worktree` returns 432 frames and
  431 visible file rows.
- `document.documentElement[data-bridge-app-protocol]` is `worktree-file`.
- Tree/content panes render after data load.
- Required product controls are absent:
  - search input: 0 matches
  - regex toggle: 0 matches
  - filter/status controls: 0 matches
- Screenshot artifact:
  `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- JSON artifact:
  `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`

Fresh contrast proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree` passed on 2026-06-24 and
  wrote `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`.
- That green result proves the existing narrow route/data/scroll contract only.
  It does not satisfy this precursor because it does not require search, regex,
  filter/status controls, product-shell provenance, or negative-substitute
  assertions.

This means prior proof only establishes a narrow route/data-loading regression.
It does not prove Worktree/File product readiness.

## Blocking Outcome

Before downstream Bridge transport, scheduler, renderer, telemetry, or Ticket 02
closure claims continue, the exact URL must render and operate the intended
Worktree/File product surface with browser proof.

The precursor is complete only when Playwright evidence proves all required
behaviors and fails if the route regresses to a mock/raw/minimal substitute.

This precursor is the fast-loop Vite/dev-server product proof. It does not
replace Agent Studio Bridge/WKWebView runtime proof for the full PR-ready epic.
The later implementation plan must add native app-hosted Bridge proof with
marker-correlated evidence that the same protocol/source/resource behavior works
through Swift, WKWebView, the Bridge host wiring, and packaged app assets.

## Scope

In scope:

- `BridgeWeb/src/worktree-file-surface/`
- `BridgeWeb/src/features/worktree-file/`
- `BridgeWeb/src/app/bridge-app-dev-worktree.ts`
- `BridgeWeb/src/app/bridge-app-protocol-router.tsx`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- focused unit/component/browser tests needed for this route
- proof artifacts under `tmp/bridge-viewer-worktree-dev-server/` or a named
  precursor proof directory

Out of scope:

- full Review renderer rewrite
- native Swift host streaming implementation
- final scheduler tuning numbers
- PR merge
- changing unrelated Review mock fixtures except where the verifier needs a
  negative assertion

## Product Contract

The Worktree/File product route must expose these observable regions:

1. Source/status header
   - Shows route identity and source provenance.
   - DOM exposes protocol/source facts for Playwright:
     `worktree-file`, source id, worktree/repo id, generation or revision token.

2. Tree/navigation pane
   - Shows selectable file rows with stable selected state.
   - Keeps tree scroll extent derived from size facts before all content bodies
     are loaded.
   - Supports tree filtering without fetching every file body.

3. File content pane
   - Shows opened file identity.
   - Shows loading, ready, stale, unavailable, and refresh states.
   - Keeps large-file scroll extent stable from declared line/row facts.

4. Query controls
   - Search text input with product-specific selector.
   - Regex toggle with product-specific selector.
   - Filter/status controls with product-specific selector.
   - User interaction must change observable state and visible results.

5. Provenance and negative-substitute guard
   - Verifier must reject the root Review mock route.
   - Verifier must reject a bare two-pane file list plus `<pre>`.
   - Verifier must reject raw JSON/frame dumps.

## Implementation Slices

### Slice 06P.1: Red Browser Contract

Add or tighten the Playwright verifier so it fails against the current route for
the right reason: missing product controls and insufficient product surface.

Proof:

- Run the verifier before implementation and capture failure.
- Failure message names at least one missing product control.
- Failure is not a timeout-only assertion.

### Slice 06P.2: Product Shell And Provenance

Add the Worktree/File product shell around the existing tree/content route.
Render source/status provenance from validated protocol frames and current route
metadata. Keep large bodies out of Zustand/state and render only references plus
materialized content.

Proof:

- Unit/component test for provenance derivation.
- Browser assertion for protocol/source DOM attributes.
- Screenshot shows product shell, not raw/minimal route.

### Slice 06P.3: Query And Filter Controls

Add tree/file search, regex mode, and filter/status controls with typed local
state. Filtering should operate on descriptors and metadata, not file bodies.

Proof:

- Unit tests cover plain text search, regex search, invalid regex handling, and
  status/filter composition.
- Browser proof types a query, toggles regex, changes a filter, and observes a
  stable state/result transition.

### Slice 06P.4: Open File State And Refresh Contract

Make open-file state explicit and visible: loading, ready, stale, unavailable,
and refresh. If the currently open file changes while open, show an update
notification/refresh affordance rather than silently replacing content.

Proof:

- Unit test for invalidation of the open descriptor.
- Browser proof observes stale/update affordance.
- Browser proof clicks refresh and returns to ready state.

### Slice 06P.5: Scroll Extent Canary

Keep DiffsHub-style scroll stability as a first-class canary. Tree and file
scroll extents must be based on declared row/line facts and remain stable across
selection and content hydration.

Proof:

- Browser proof records tree and content `scrollHeight`, `scrollTop`, selected
  row, and open path before and after file selection.
- Proof fails if scroll height collapses to only materialized visible content.
- Proof fails if selecting a file causes an unexplained jump outside threshold.

### Slice 06P.6: Negative Proof And Artifact

Write a JSON proof artifact and screenshots that can be inspected by parent
agent and reviewer lanes.

Proof artifact must include:

- exact URL
- timestamp
- browser executable/channel
- protocol/source facts
- selected file and open state
- search/regex/filter states
- tree/content scroll canaries
- screenshot paths
- explicit negative-substitute assertions

## Test Pyramid

Unit:

- descriptor filtering policy
- regex parsing and invalid regex behavior
- provenance derivation
- open-file invalidation/refresh state

Component:

- Worktree/File shell renders product regions from validated frames
- query controls update local state and visible tree rows
- stale refresh affordance renders from invalidated open descriptor

Integration:

- dev worktree provider returns validated metadata, descriptors, size facts, and
  descriptor resource URLs without file bodies in metadata
- content fetch uses descriptor authority and generation/cursor

Browser/E2E:

- exact current-worktree URL
- product controls present and interactive
- file click renders content
- search/regex/filter proof
- scroll extent canary
- screenshots and JSON artifact
- negative substitute guard

Native runtime:

- later PR-ready gate runs Agent Studio Bridge/WKWebView proof for the same
  protocol path
- proof includes bridge route boot, source/protocol identity, resource/content
  requests, event stream readiness, and Victoria/log marker correlation
- Vite-only proof must not be used as the final native Bridge proof

Quality:

- `pnpm --dir BridgeWeb run test:unit` for touched TS units when available
- focused browser verifier for the route
- `mise run lint` before claiming the ticket ready

## Execution Diagram

```text
current-worktree URL
        │
        ▼
Vite dev bootstrap
        │
        ├─ sets protocol = worktree-file
        ├─ installs Worktree dev backend
        │
        ▼
Worktree/File product shell
        │
        ├─ source/status header
        ├─ query/filter controls
        ├─ tree pane from descriptors + tree size facts
        └─ file pane from selected descriptor + materialized content
              │
              ▼
      descriptor resource fetch
              │
              ▼
      content ready / stale / unavailable
```

## Gate

This precursor remains open until a reviewer can inspect the proof artifacts and
confirm that the exact dev-server URL is the intended Worktree/File product
surface. Passing the old narrow verifier is not enough.
