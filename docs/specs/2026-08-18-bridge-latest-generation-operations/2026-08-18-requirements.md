# Bridge Latest-Generation Operations — User Requirements

## Purpose

Bridge File View, Review View, annotations, content hydration, and render
fulfillment perform asynchronous work while the underlying worktree, viewer,
selection, source generation, and pane activity continue changing. Today, some
newer work waits behind obsolete physical work, some producers disappear
without telling their coordinator, and some successful commands remain visually
stuck because a later read refresh fails.

This correction makes Bridge behave predictably under rapid change: the newest
applicable intent becomes current, obsolete work cannot overwrite or justify
loading, the last complete view remains usable, and every operation reaches an
observable terminal result.

## Authority and evidence

- Decision owner: Agent Studio owner.
- Owner-confirmed direction: the 2026-08-18 conversation establishing
  latest-generation authority, immediate logical supersession, asynchronous
  physical draining, exact command receipts, and separately refreshed data.
- Current File/Review and transport architecture is the foundation to preserve:
  [Bridge Product Transport](../../architecture/bridge_product_transport_architecture.md),
  [Bridge Native Runtime](../../architecture/bridge_native_runtime_architecture.md),
  and [Bridge Web Runtime](../../architecture/bridge_web_runtime_architecture.md).
- PR1 annotation meaning remains governed by
  [its Requirements](../2026-08-06-worktree-annotations/pr1-user-requirements.md)
  and is one required consumer of this correction.
- Current source, reproducible test receipts, and Victoria/OTEL records are
  observational evidence. They prove current behavior and proof gaps, not
  additional product scope.

## Affected classes

### Human reviewer

Uses File View and Review View while files, Git status, comparison content,
annotations, and rendered Markdown change. The reviewer must be able to trust
whether a command committed, whether the displayed data is current, and whether
the application is still working or has entered a recoverable degraded state.

### Agent Studio developer and operator

Must be able to assign a stuck interaction to native refresh, metadata delivery,
worker application, projection convergence, or render fulfillment without
examining private content or guessing from a generic loading spinner.

## Observable problem

```text
reviewer changes or observes a worktree
  → Bridge starts File/Review work and shows Updating/Loading
  → a newer change supersedes the old work
  → old work may remain physically active
  → successor may wait, producer may disappear, or terminal state may be lost
  → stale work cannot finish usefully, but the UI may remain stuck indefinitely
```

For annotation mutations, a related failure is already distinguishable:

```text
Save commits durably
  → exact command succeeds
  → projection refresh fails
  → UI continues to look Saving instead of Saved with unavailable refresh
```

## Desired journey

```text
reviewer action or source change
  → current work becomes visibly active
  → newer applicable work supersedes old authority immediately
  → old physical work cancels or drains without blocking current authority
  → newest work either installs one complete result or exposes failure
  → last complete File/Review/projection remains available throughout
  → loading clears on success, failure, cancellation, or stale completion
```

## Authorized needs

### BLO-U1 — Newest applicable intent wins

- Affected class: human reviewer.
- Need: When a newer source, selection, demand, viewer, or refresh intent makes
  older work obsolete, the older work must stop being authoritative immediately
  and must not delay the newest intent indefinitely.
- Why: Continuing to wait behind obsolete work makes active File/Review state
  appear frozen even though the system already knows what should replace it.
- Authority: authorized.
- Priority: must.

### BLO-U2 — Successful commands finish independently from refreshed reads

- Affected class: human reviewer.
- Need: A mutation command must end from its exact success receipt or exact
  failure. A successful durable command must not remain visually in progress
  while a subsequent projection or render refresh is pending or unavailable.
- Why: Persistence truth and read-model convergence answer different questions;
  conflating them makes committed work look uncertain.
- Authority: authorized.
- Priority: must.

### BLO-U3 — Preserve the last complete usable state

- Affected class: human reviewer.
- Need: Refresh, content, projection, or render failure must retain the last
  complete File, Review, or annotation state while clearly exposing that a
  replacement is refreshing or unavailable.
- Why: A failed replacement must not fabricate an empty success or destroy a
  still-trustworthy previous view.
- Authority: authorized.
- Priority: must.

### BLO-U4 — Every started operation settles

- Affected classes: human reviewer and operator.
- Need: Every started command, refresh, subscription, content request,
  projection, and render operation must reach exactly one observable terminal
  outcome: success, failure, cancellation, or stale/superseded.
- Why: A producer that silently disappears or a task that never relinquishes
  loading authority strands both the user and the operator.
- Authority: authorized.
- Priority: must.

### BLO-U5 — Cancellation does not block replacement

- Affected class: human reviewer.
- Need: Physical cancellation or cleanup of obsolete work may finish later, but
  it must not prevent the newest safe replacement from starting. Late obsolete
  completion must never overwrite current state.
- Why: Platform cancellation is cooperative and cannot be the sole correctness
  or liveness mechanism.
- Authority: authorized.
- Priority: must.

### BLO-U6 — Dead streams and overload recover to current truth

- Affected class: human reviewer.
- Need: If a metadata or notification producer fails, ends, or exceeds bounded
  delivery capacity, Bridge must stop treating it as active, reconverge through
  reset/reopen, and replay the latest compact current state.
- Why: Silent producer death and invalid overflow behavior can leave old chrome,
  source identity, or navigation visible forever.
- Authority: authorized.
- Priority: must.

### BLO-U7 — Finite data stays bounded and atomic

- Affected classes: human reviewer and operator.
- Need: Finite content and projection responses must declare enforceable total
  bounds, validate ordering and integrity across any admitted number of pages,
  and install only after one complete logical result is validated.
- Why: Per-page bounds alone do not prevent indefinite accumulation, and a
  partial/mixed response cannot become current UI truth.
- Authority: authorized.
- Priority: must.

### BLO-U8 — Wire meaning is explicit and symmetric

- Affected classes: human reviewer and developer.
- Need: Every valid request/result variant, field name, discriminant,
  nullability rule, numeric limit, timestamp unit, and content terminal must be
  accepted consistently by Swift and BridgeWeb. Adding a field must not allow
  native code to reject its own valid response after a side effect committed.
- Why: Duplicated, disconnected wire vocabularies turn successful operations
  into false internal failures.
- Authority: authorized.
- Priority: must.

### BLO-U9 — Correlation and resource state remain bounded

- Affected class: operator.
- Need: Request rendezvous entries, descriptors, observers, cancellation
  handles, content reservations, and artifact custody must be removed or bounded
  after settlement, replacement, close, or restart.
- Why: Autosave, repeated refresh, and long-lived panes must not accumulate
  unreachable operation state.
- Authority: authorized.
- Priority: must.

### BLO-U10 — Current work is diagnosable without private content

- Affected class: developer and operator.
- Need: One scrubbed correlation must reveal whether current work is waiting in
  native refresh, transport delivery, worker application, projection install,
  or render fulfillment and whether each started stage reached a terminal
  outcome.
- Why: Construction-capacity telemetry alone cannot distinguish a native hang
  from lost metadata, a stale worker result, or a missing render receipt.
- Authority: authorized.
- Priority: must.

### BLO-U11 — File, Review, annotations, and rendering keep distinct ownership

- Affected class: developer.
- Need: The correction must preserve feature-owned policy and state while
  applying one consistent settlement and supersession contract. File and Review
  remain separate surfaces; command, projection, subscription, content, and
  render lifecycles remain distinct.
- Why: A giant shared operation framework would move feature policy into an
  abstraction that cannot express current owner-specific admission, demand,
  construction, and recovery rules.
- Authority: authorized.
- Priority: must.

### BLO-U12 — Existing current behavior remains available during cutover

- Affected class: human reviewer.
- Need: The correction must preserve current File browsing, Review comparison,
  annotations, clipboard/export effects, pane admission, and the three physical
  Bridge routes while replacing defective lifecycle behavior in one hard
  cutover.
- Why: Lifecycle repair must not create a second data plane, compatibility shim,
  or duplicate source of truth.
- Authority: authorized.
- Priority: must.

## Goal boundary

- Primary outcome: Bridge remains current, usable, and diagnosable under rapid
  source/view/demand changes and partial failure.
- Allowed surface: existing Bridge native runtime, product transport,
  communication worker, File/Review/annotation clients, render fulfillment,
  telemetry, and their tests.
- Existing authority to preserve: SQLite/repositories for durable annotation
  truth; native Git/source owners; pane product admission; worker surface state;
  last complete main-thread render/projection stores.
- Complexity limit: a small common operation contract plus feature-owned state
  machines. A new global operation service, durable task database, second
  physical transport, polling loop, or queue-capacity increase requires a new
  owner decision.
- Acceptable proof: deterministic state/interleaving tests, real native/worker
  integration, real two-pane convergence, development backend plus Vite,
  packaged WKWebView interaction, and marker-scoped operational evidence.

## Non-goals

- Redesigning annotation UI, Review comparison semantics, or File tree layout.
- Adding PR2 agent delivery, replies, acknowledgement, deletion, or App IPC
  annotation operations.
- Making every operation concurrent or cancelling immutable shared construction
  that is safe and beneficial to join.
- Treating every refresh failure as automatically retryable forever.
- Persisting in-flight operation history across app restart.
- Guaranteeing that cooperative physical cancellation completes immediately.
- Replacing the existing command, metadata, or content physical routes.
