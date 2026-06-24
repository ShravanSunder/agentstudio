# Ticket 00: Gate 0 Worktree/File Product E2E

Status: draft for plan-review-swarm
Depends on: accepted Bridge transport spec review
Blocks: Gates 1-4 implementation claims

## Deliverable

Make the exact Vite dev-server URL render and operate the intended Worktree/File
product surface:

```text
http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree
```

The route must not pass as a Review mock route, raw frame dump, concatenated
path dump, or minimal two-pane list plus `<pre>` renderer.

## Proof Surface Boundary

This ticket proves the Vite dev-server/browser product loop only. It is still a
real product proof gate, not a mock gate: the verifier must launch or attach to
the dev server, open the exact URL, interact with the rendered page, capture
screenshots and JSON diagnostics, and assert visible product behavior.

Native Agent Studio Bridge/WKWebView proof is deliberately not satisfied here.
Ticket 04 must rerun equivalent product behavior through the native app-hosted
Bridge path before PR-ready.

## Current Red Evidence

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`
- Backend returned 432 frames and 431 rows.
- Browser protocol attribute was `worktree-file`.
- Tree/content rendered after wait.
- Required product controls were absent:
  - search input: 0
  - regex toggle: 0
  - filter/status controls: 0

Old narrow green proof:

- `pnpm --dir BridgeWeb run test:dev-server:worktree`
- Latest observed artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-51-13-807Z`
- This proof is retained as a regression signal only. It is not Gate 0 proof.

## Vertical Slices

### 00.1 Red Product Verifier

Add or tighten the browser verifier so it fails against the current route for
missing product behavior.

Proof:

- Verifier fails before product implementation.
- Failure names missing product controls or product contract violation.
- Failure is not a timeout-only failure.
- Negative assertions reject Review mock route, raw payload/frame dump, and
  minimal list plus `<pre>`.

### 00.2 Product Shell And Provenance

Render source/status provenance and product shell around the Worktree/File
surface.

Proof:

- Unit/component proof for provenance derivation.
- Browser proof for protocol/source DOM attributes.
- Screenshot shows product shell, not raw/minimal route.

### 00.3 Query, Regex, And Filter Controls

Implement tree/file search, regex mode, and filter/status controls over
descriptors and metadata, not file bodies.

Proof:

- Unit tests for plain search, regex search, invalid regex, and status/filter
  composition.
- Browser proof changes query, regex mode, and filters.
- JSON artifact records before/after visible row count or sampled visible path
  set, active filter tokens, regex-valid/error state, and fixture-specific
  visible result deltas.

### 00.4 Open File State, Stale, And Refresh

Make open-file states visible: loading, ready, stale, unavailable, refreshing.
If an open file is invalidated, show stale/update state and require explicit
refresh before replacing content.

Proof:

- Unit/component proof for invalidation state.
- Browser proof records ready -> stale/update -> refresh -> ready.
- Screenshot/JSON evidence proves refresh is user-invoked, not silent
  replacement.

### 00.5 Stable Scroll Extent

Use declared tree row and file line/extent facts so scroll size remains stable
before and after content hydration.

Proof:

- Browser proof records tree/content scrollHeight, scrollTop, selected row/open
  path before and after selection/hydration.
- Proof fails if scroll height collapses to visible materialized content.
- Proof fails on unexplained jump outside threshold.

### 00.6 Artifact And Inspection Gate

Write a proof artifact and screenshots that reviewers can inspect without
trusting hidden test state.

Proof artifact includes:

- exact URL
- timestamp
- browser executable/channel
- protocol/source facts
- selected file and open state
- search/regex/filter states
- per-interaction result deltas
- stale/refresh transition
- tree/content scroll canaries
- screenshot paths
- explicit negative-substitute assertions

Completion requires parent/human/reviewer inspection of the artifacts. A failed
or disconnected subagent review does not satisfy or invalidate this gate by
itself.

## Required Commands

Red/green browser verifier:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

New or updated Gate 0 verifier command must be named in the implementation
commit. If the existing command remains the entry point, it must be upgraded so
the old narrow green route can no longer pass.

Focused supporting tests:

```bash
pnpm --dir BridgeWeb run test -- <focused worktree/product tests>
pnpm --dir BridgeWeb run check
```

Repo quality before ticket close:

```bash
mise run lint
```

## Not In This Ticket

- Native Agent Studio Bridge/WKWebView proof. This is required before PR-ready
  but belongs in Gate 4 unless implementation work naturally exposes it earlier.
- Full Review renderer cutover.
- Generic transport core rewrite beyond what the product route needs to prove
  Gate 0.

phase_result: complete
evidence: Gate 0 ticket drafted with red/current proof, vertical slices, and proof gates.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 0 has a reviewable implementation ticket.
