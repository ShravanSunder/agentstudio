# Bridge + Diff Viewer Execution Plan

> Scope: Linear project `AgentStudio Bridge & Diff Viewer`  
> Date: 2026-02-23  
> Revalidated: 2026-05-22 after re-checking the stale branch, Linear graph, and Pierre CodeView/Shiki review-surface boundary
> Purpose: one detailed delivery plan with ticket-mapped sections and explicit multi-worktree execution rules.

## Canonical Architecture References

- [`docs/architecture/swift_react_bridge_design.md`](../architecture/swift_react_bridge_design.md)
- [`docs/architecture/pane_runtime_architecture.md`](../architecture/pane_runtime_architecture.md)
- [`docs/architecture/component_architecture.md`](../architecture/component_architecture.md)
- [`docs/architecture/window_system_design.md`](../architecture/window_system_design.md)
- [`docs/architecture/session_lifecycle.md`](../architecture/session_lifecycle.md)

## Canonical Ticket Graph

```text
LUNA-347 -> LUNA-337 -> (LUNA-338, LUNA-339)
LUNA-338 -> (LUNA-340, LUNA-348)
(LUNA-340, LUNA-348) -> LUNA-377 -> LUNA-341
LUNA-339 -> LUNA-341
Optional tail: LUNA-337 -> LUNA-346
```

## Product Boundary

The first bridge product surface is a performant, read-only file/diff/review pane built with React, Pierre CodeView, Shiki, web-worker-backed highlighting, and Trees navigation. Source files and diffs are display artifacts in this pane: no Monaco, no source buffer ownership, no inline code editing, no patch application, no "accept agent change" button, and no workspace-file mutation path.

Editable review artifacts are allowed and expected. Annotation notes and comment bodies can be markdown-capable, but the durable annotation/comment schema is intentionally deferred to `LUNA-340` after Hunk and Pierre annotation research. The full markdown whiteboard/editor pane is a separate fast-follow concern and remains intentionally light in this plan.

## TDD / Performance Rule

Every ticket in this project starts from tests or fixtures that describe the behavior being implemented. For bridge work, that means contract fixtures, scheme handler tests, WebKit lifecycle tests, security tests, rendering tests, or performance benchmarks before implementation is considered complete. Visual rendering alone is not completion.

## Research-Grounded Viewer Shape

The current design is anchored on four external constraints:

1. Pierre Diffs exposes `@pierre/diffs`, `@pierre/diffs/react`, `@pierre/diffs/worker`, and CodeView as the high-level mixed file/diff surface. CodeView owns the scroll container, item-level virtualization, measured layout reconciliation, annotation rendering, line selection, and item/line/range scroll targeting.
2. Pierre worker-pool highlighting is required for repo-scale review. Worker creation is bundler/environment-specific, so worker script loading is part of the bridge app-asset contract, not just a React implementation detail.
3. Shiki highlighters are expensive to create. Use Pierre's shared highlighter or worker pool, configure language/theme preloads deliberately, and never instantiate highlighters in render/hot paths.
4. Trees is path-first. Selection, focus, search, Git status, and row annotations should use canonical paths, and large manifests should use prepared or presorted input produced outside the React render path.
5. Hunk is inspiration for review workflows only: structured agent notes, live review snapshots, navigate/reload/comment flows, and batch comments. Its OpenTUI/terminal layout, PTY tests, and pager architecture are not part of this app.

That gives the bridge one data shape:

```text
BridgePaneSource
  -> DiffManifest(epoch, sourceId, orderedPaths, fileDescriptors)
  -> Trees prepared input + CodeView item descriptors
  -> ContentHandle(fileId, epoch, contentHash, cacheKey, languageOverride?)
  -> on-demand resource fetch + CodeView item version update
```

Research references for this pass:

- Pierre Diffs / CodeView: https://diffs.com/docs
- Trees: https://trees.software/docs
- Shiki: https://shiki.style/
- Hunk inspiration: https://github.com/modem-dev/hunk and https://github.com/modem-dev/hunk/blob/main/docs/agent-workflows.md

## Current Branch Reality (2026-05-22)

This branch is still a docs/plans lane; it does not finish the bridge implementation. The live code already has the bridge shell and transport scaffolding:

- `PaneContent.bridgePanel`, `BridgePaneController`, `BridgeRuntime`, and `BridgePaneMountView` are wired into pane creation.
- `BridgeNavigationDecider`, `BridgeBootstrap`, `RPCMessageHandler`, `RPCRouter`, typed method contracts, push plans, revision clock, and Swift fixtures exist.
- Tests cover routing, bootstrap behavior, content-world isolation, scheme classification, and push/RPC contracts on the Swift side.

The content-delivery baseline still needs implementation:

- `BridgeSchemeHandler` currently serves placeholder app HTML and placeholder `resource:<fileId>` bytes.
- `diff.requestFileContents` and `diff.loadDiff` are registered but not backed by real diff/file-content delivery.
- `BridgePaneController.loadApp()` always loads `agentstudio://app/index.html`; source-specific loading from `BridgePaneSource` is not wired.
- No React/TypeScript client tree or TS fixture suite is committed in this checkout, so Swift/TS parity is a target, not current evidence.

The architecture remains valid: Bridge stays in `Features/Bridge`, pane/runtime coordination stays in `App/Coordination`, shared pane identity and persistence stay in `Core`, and feature state should remain feature-owned. The main architecture debt is that `Core/Models/PaneContent.swift` currently persists `BridgePaneState`; treat that as a transitional persisted pane payload, not a precedent for moving more feature types into Core.

## Multi-Worktree / Multi-Agent Rules

1. One active ticket per worktree (`luna-337-*`, `luna-338-*`, etc.).
2. Never run two agents in one worktree.
3. Never mix scope from multiple tickets in one branch.
4. Rebase/merge only after direct blockers are landed.
5. If a contract changes, land fixtures + docs in the same changeset before downstream UI work.
6. Do not freeze the durable annotation/comment schema in `LUNA-347` or `LUNA-338`; `LUNA-340` owns that after research.

---

<a id="section-1-contract-baseline"></a>
## Section 1: Contract Baseline (`LUNA-347`, `LUNA-337`)

### Ownership

- `LUNA-347`: runtime-independent contract/fixture freeze.
- `LUNA-337`: runtime-coupled bridge integration and delivery behavior.
- Runtime contracts stay owned by pane runtime architecture (`LUNA-325` family).

### Deliverables

1. Freeze bridge/content contract shapes in Swift fixtures now.
2. Add TypeScript fixture parity when the React client tree lands in the repository.
3. Implement runtime-coupled content delivery semantics:
   - generation/epoch guards,
   - stale-drop,
   - cancellation and replay-safe behavior.
4. Replace placeholder app/resource serving with real bundled-app and file-content resolution.
5. Implement real `diff.loadDiff` and `diff.requestFileContents` behavior instead of stubbed handlers.
6. Keep transport envelope shape single-source; no parallel `payload`/`data` variants.
7. Define the minimal CodeView item/content-handle expectations needed by downstream viewer work; durable annotation/comment schema is deferred.
8. Make the app-asset channel capable of serving the React bundle and Pierre worker chunks from packaged WKWebView resources.
9. Include ordered path metadata so `LUNA-338` can feed Trees prepared/presorted input without reshaping large manifests in React render.

### Acceptance Criteria

1. Swift fixture suite proves valid/invalid/stale/duplicate/reordered payload behavior.
2. Once the React client exists in this repo, Swift and TS fixture suites use the same fixtures and reject the same invalid payloads.
3. `LUNA-337` behavior is deterministic across restart/cancel/reload paths.
4. Downstream tickets can consume contracts without redefining them.
5. Bridge scheme responses serve real app resources and file contents with epoch/cancellation/path validation.
6. Contract fixtures prove the content-delivery baseline before React viewer work depends on it.
7. WebKit proof shows app assets and worker assets load from `agentstudio://app/*`, not only from a local dev server.

### Ticket Mapping

- `LUNA-347`: bridge/content contract + fixture freeze only.
- `LUNA-337`: runtime-coupled content delivery integration only.

### LUNA-337 Finish Checklist

- [ ] Decide and document where the React client source lives and how the built assets are copied into app resources.
- [ ] Replace `agentstudio://app/*` placeholder serving with bundled asset lookup, MIME handling, cache headers, and missing-resource errors.
- [ ] Include Pierre worker chunks in the bundle/resource pipeline and prove their MIME/origin behavior in WKWebView.
- [ ] Replace `agentstudio://resource/file/{id}` placeholder serving with file-content resolution keyed by pane/source/epoch, including traversal rejection and cancellation.
- [ ] Make `BridgePaneSource` drive diff manifest loading for commit, branch-diff, workspace, and agent-snapshot sources that are in scope for this ticket.
- [ ] Implement non-stub `diff.loadDiff` and `diff.requestFileContents` handlers or remove the duplicate RPC surface if scheme fetch is the single content path.
- [ ] Emit ordered path metadata and file content handles with content hash/cache key/language override slots.
- [ ] Normalize push envelope fixtures around the canonical field names emitted by runtime code.
- [ ] Add deterministic unit tests for epoch mismatch, stale response drop, cancellation, and path traversal.
- [ ] Add WebKit serialized tests that prove `agentstudio://app/index.html` and at least one `agentstudio://resource/file/{id}?epoch=...` response are real, not placeholders.

---

<a id="section-2-parallel-delivery-tracks"></a>
## Section 2: Parallel Delivery Tracks (`LUNA-338`, `LUNA-339`)

### Ownership

- `LUNA-338`: read-only Pierre CodeView/Shiki/Trees viewer integration and interaction UX.
- `LUNA-339`: CWD file viewer track that reuses shared bridge delivery contracts.

### Deliverables

1. Split execution into parallel tracks after `LUNA-337` baseline lands.
2. Keep both tracks compatible with the same bridge contract.
3. Ensure CWD track does not fork transport/data envelope shapes.
4. Preserve explicit in-scope/out-of-scope boundaries in each ticket.
5. Prove CodeView can render fixture annotations at scale, but do not define durable annotation/comment schema in this section.
6. Prove Trees receives prepared/presorted input for repo-scale manifests.
7. Prove Pierre worker-backed highlighting works in the packaged WKWebView surface.

### Acceptance Criteria

1. `LUNA-338` and `LUNA-339` can be implemented independently in separate worktrees.
2. Both tracks merge cleanly against the same Section 1 baseline.
3. No duplicate contract types introduced by parallel branches.
4. `LUNA-338` includes rendering/performance tests for CodeView item updates, Shiki/highlighter worker setup, scroll targets, and fixture annotation markers.
5. `LUNA-338` has no source editing or patch-application command path.
6. `LUNA-338` keeps CodeView item IDs and Trees path identity mapped through one manifest adapter.

### Ticket Mapping

- `LUNA-338`: CodeView renderer + Shiki worker/highlighter setup + Trees navigation + UI/store integration.
- `LUNA-339`: CWD tree/file view + shared content pipeline reuse.

### LUNA-338 Finish Checklist

- [ ] Build the React review surface around CodeView, not lower-level Virtualizer, unless a measured CodeView blocker appears.
- [ ] Use CodeView imperative ownership for large/streaming surfaces: `initialItems` plus `addItems`, `updateItem`, `getItem`, and `scrollTo`.
- [ ] Map `path -> fileId -> itemId` once per epoch, and increment CodeView item `version` on content, collapse, or fixture-annotation changes.
- [ ] Configure Pierre worker highlighting through the documented worker-pool API; preload common languages/themes and choose `preferredHighlighter` deliberately.
- [ ] Use Trees path-first APIs and prepared/presorted input for large manifests; keep search/focus/selection path-based.
- [ ] Add rendering and performance fixtures for large diffs, large files, fast scroll, scroll-to-line/range, worker setup, and fixture annotations.
- [ ] Keep source editing, patch apply, and accept/reject mutation commands out of the pane.

### LUNA-339 Finish Checklist

- [ ] Reuse `BridgePaneSource`, manifest, epoch, resource URL, cache key, and cancellation contracts from `LUNA-337`.
- [ ] Render CWD file browsing without forking the diff-viewer transport shape.
- [ ] Keep editable file/markdown behavior out of this ticket unless the ticket is explicitly rescoped.
- [ ] Share tree identity expectations with `LUNA-338`: path-first navigation and prepared input for scale.

---

<a id="section-3-fan-in-hardening"></a>
## Section 3: Annotation, Agent Workflow, and Fan-In (`LUNA-340`, `LUNA-377`, `LUNA-348`, `LUNA-341`, optional `LUNA-346`)

### Ownership

- `LUNA-340`: review annotations + markdown comments.
- `LUNA-377`: agent review workflow + timeline.
- `LUNA-348`: transport-layer security hardening baseline.
- `LUNA-341`: post-fan-in viewer/workflow hardening.
- `LUNA-346`: optional push/backpressure hardening tail.

### Deliverables

1. Land annotation/comment research and domain features on top of `LUNA-338`.
2. Land transport security baseline before agent workflow paths that carry rich review context.
3. Land agent review workflow after `LUNA-340` and `LUNA-348`.
4. Execute final cross-feature hardening only after `LUNA-339`, `LUNA-377`, and `LUNA-348` converge.
5. Keep `LUNA-346` gated by profiling evidence (not default critical path).

### Acceptance Criteria

1. `LUNA-340` research happens before durable annotation/comment schema freeze.
2. Annotation/comment commands mutate review artifacts only, never source files.
3. `LUNA-377` can send review context to an agent and receive agent findings/status/timeline events without applying patches from the review pane.
4. Combined review + viewer + transport flows satisfy lifecycle and security invariants.
5. Final hardening covers page crash, cancellation, slow-consumer, and resume paths.
6. `LUNA-346` remains optional unless measured pressure requires it.

### Ticket Mapping

- `LUNA-340`: editable review annotations and markdown-capable comments.
- `LUNA-377`: agent review workflow and append-only timeline.
- `LUNA-348`: transport security controls.
- `LUNA-341`: fan-in hardening after `LUNA-339` + `LUNA-377` + `LUNA-348`.
- `LUNA-346`: optional backlog hardening.

### LUNA-340 Finish Checklist

- [ ] Research Pierre annotation APIs and Hunk sidecar/live-comment concepts before freezing the schema.
- [ ] Define markdown-capable review bodies, but keep full markdown whiteboard/editor concerns out of scope.
- [ ] Define anchors with enough identity to survive review updates: annotation/thread ID, item/file identity, side, line/range, context hash, status, author type, and summary/count metadata.
- [ ] Support human-authored and agent-authored review artifacts with add/edit/delete/resolve lifecycle and optimistic pending/failed/committed states.
- [ ] Prove every annotation/comment command mutates review data only, never source files.

### LUNA-377 Finish Checklist

- [ ] Model a review task that can be created from selected lines, hunks, files, or annotation threads.
- [ ] Add an append-only timeline for review requests, agent status, findings, comments, errors, and completion.
- [ ] Borrow Hunk's useful workflow shape: inspect current review snapshot, navigate/focus a target, reload/resync, add one comment, or apply a comment batch.
- [ ] Define sequence-numbered agent events with batching, gap detection, and resync.
- [ ] Keep "send to agent" as context/command delivery only; no patch apply or workspace mutation from the review pane.

### LUNA-348 / LUNA-341 Finish Checklist

- [ ] `LUNA-348`: harden method allowlists, content-world isolation, nonce checks, scheme URL traversal, navigation policy, and app/worker asset loading rules.
- [ ] `LUNA-348`: include worker-script loading and rich review context in the threat model.
- [ ] `LUNA-341`: run fan-in lifecycle/security/performance validation after `LUNA-339`, `LUNA-377`, and `LUNA-348` land.
- [ ] `LUNA-341`: verify crash/resume, slow-consumer backpressure, cancellation, epoch resync, and cross-feature state consistency.

---

## Ticket Description Standard (Required)

Each active ticket in this project must include:

1. Explicit in-scope and out-of-scope bullets.
2. Hard blockers (`blockedBy`) and downstream dependents (`blocks`).
3. Architecture references (from the list above).
4. Link to the exact section anchor in this plan file.

Legacy stale tickets (`LUNA-328` to `LUNA-333`) remain superseded and are not execution sources.
