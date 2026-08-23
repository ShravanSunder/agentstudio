# Bridge Comm-Worker Admission And Backpressure — Requirements

Date: 2026-08-23

Decision authority: Agent Studio owner.

Related authority:

- [Demand-Driven Derived-State Refresh](../../../architecture/state/demand_driven_derived_state_refresh.md)
- [Local-First Comm Worker Architecture](../../bridge-viewer-transport/local-first-comm-worker-architecture.md)
- [Bridge Review Refresh Classification requirements](../2026-08-21-bridge-review-refresh-classification/2026-08-21-requirements.md)
- [Worktree annotation PR1 requirements](../2026-08-06-worktree-annotations/pr1-user-requirements.md)

## Problem

Bridge uses one pane-owned product `MessageChannel` between the browser main
runtime and the comm worker. Urgent user actions, desired-state demand, and
render-settlement receipts currently enter that route as ordinary RPC command
messages.

In a real 1,699-item Review, render-settlement retry amplification produced
21,806 individual `renderDisposition` messages. Each worker handler took about
0–0.1 ms, but main-to-worker queue wait reached about 47–48.5 seconds. Comment
actions waited behind that backlog, Save exceeded ten seconds, and browser
inspection timed out. SQLite persistence was not the source of that delay.

Bridge needs admission behavior that matches the meaning of each input:

```text
urgent action/control  exact, non-replaceable intent
demand                 current desired state
delivery settlement    ordered feedback about delivered work
```

## Affected people

- Reviewers creating, editing, saving, replying to, resolving, and sharing
  comments while Review content renders or refreshes.
- Reviewers navigating large Review and File surfaces under sustained demand.
- Developers relying on the Vite plus Swift development-server loop to expose
  real performance and durability failures before packaged validation.

## Goal boundary

Keep the existing pane-owned comm worker, product protocol, fulfillment state
machine, source authority, and single product `MessageChannel`. Add only the
admission, backpressure, and evidence needed to prevent render-settlement
traffic from starving exact user actions.

Measure first. Batch ordered render receipts with real worker
acknowledgement-based backpressure. Preserve current demand owners unless
evidence shows a specific producer admits obsolete work; then correct that
producer with the fitting latest-state or scope-preserving mechanism.

## Authorized needs

### U-CWA-001 — Keep exact user actions prompt

Comment mutations and correctness controls must not starve behind unsent
demand or render-settlement feedback. Each exact action keeps its own identity,
validation, ordering, and terminal outcome.

### U-CWA-002 — Preserve demand meaning

Demand must represent what a consumer currently needs. Obsolete unsent
viewport, hover, selection, projection, metadata-interest, or invalidation
facts must be suppressed, replaced, or merged only when their owning equality
and scope rules prove that contraction safe.

### U-CWA-003 — Settle delivered work without amplification

Required queued, applied, painted, rejected, and superseded render transitions
must reach the comm-worker fulfillment owner in per-attempt order before their
leases expire. Settlement traffic must not create an unbounded physical-port
backlog or a retry loop that republishes the same visible work.

### U-CWA-004 — Preserve causal and source truth

Admission must preserve ordering relationships required by Review publication
installation, displayed-source annotation commands, worker generation, and
render-attempt identity. Performance work must not weaken source fences,
revision checks, exact outcomes, leases, timeouts, or durable SQLite authority.

### U-CWA-005 — Make delay attributable

Fresh, source-scrubbed operational evidence must distinguish main-to-worker
queue wait, worker handler duration, render-receipt pending age and batch
settlement, product-control duration, annotation lifecycle, lease expiration,
and retry amplification. Telemetry batching or ingestion delay must not be
reported as application latency.

### U-CWA-006 — Prove the real comment workflow

The primary runtime proof must use a disposable real worktree through Vite,
the production comm worker, Swift development backend, production product
routes, and SQLite. A root comment plus five saved replies must remain
responsive, settle through exact committed outcomes, and survive full reload.

### U-CWA-007 — Stay efficient and recoverable

The correction must use bounded messages and bounded in-flight settlement,
avoid duplicate per-receipt RPC lifecycles, release state on acknowledgement,
failure, worker replacement, surface disposal, and document replacement, and
remain fail-open for optional telemetry.

## Priorities

1. Durable user actions and source correctness.
2. No starvation or render retry amplification.
3. Real runtime evidence and deterministic proof.
4. Minimal CPU, memory, and message overhead.

## Non-goals

- No new physical product port, worker, route, or trust boundary.
- No generic priority framework or universal scheduler without measured need.
- No UI, animation, comment-presentation, refresh-classification, comparison,
  SQLite schema, Git computation, security, authentication, or authorization
  redesign.
- No optimistic claim that a comment saved before the authoritative command
  outcome returns.
- No dropping ordered render transitions, relaxing the five-second receipt
  lease, increasing RPC timeouts, or hiding retries to make proof pass.
- No animation-frame, polling, blanket debounce, or wall-clock pacing for
  protocol settlement.
- No payload, path, selected text, comment body, edit token, raw UUID, or raw
  error export in operational evidence.
