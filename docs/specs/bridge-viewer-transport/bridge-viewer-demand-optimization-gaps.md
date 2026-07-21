# Bridge Viewer Demand Optimization Gaps

Date: 2026-07-20
Status: follow-up specification; excluded from the current Ghostty/filesystem merge recovery

## Product Problem

Bridge Review should keep the file the user selected responsive while a large
review is loading, scrolling, caching content, and syntax highlighting. Today,
the production path contains the beginnings of that priority system, but four
parts are not connected end to end:

1. selected and visible content do not share one capacity authority;
2. nearby and progressive background warming are incomplete;
3. the byte-owning body registry is not the production cache owner;
4. Review demand rank does not reach the real Pierre/Shiki task.

The customer-visible consequences are selected-file latency under pressure,
cold adjacent navigation, avoidable repeated body work, and lower-priority
highlighting delaying the file the user is trying to read.

This specification summarizes those completion gaps. The normative demand-lane
and performance contracts remain in
[performance-demand-lanes.md](performance-demand-lanes.md). The accepted
implementation sequence remains in
[plans/2026-07-19-review-demand-lane-completion.md](plans/2026-07-19-review-demand-lane-completion.md).

## Scope Boundary

This is Bridge Viewer follow-up work. It is not part of the current merge
recovery for Ghostty admission, filesystem projection, EventBus pressure, or
MainActor reduction.

In scope:

- Bridge Review selected, visible, nearby, speculative, and background content
  demand;
- the browser/comm-worker demand reconciler and executor;
- the production Review body cache;
- rank propagation into the actual Pierre/Shiki rendering task;
- bounded telemetry and behavior proof for those paths.

Out of scope:

- Ghostty, zmx, terminal event classification, or terminal activity inference;
- filesystem watching, Git projector admission, or EventBus redesign;
- native metadata-scheduler redesign;
- `agentstudio-git` API changes;
- Pierre dependency or source changes;
- compatibility paths, new workers, or new proof harnesses.

## Boundary And Separability Map

```text
Review UI intent
  owns: selected item, viewport, direction, hover, pane activity
  exposes: bounded demand facts
                    |
                    v
Demand reconciler
  owns: desired membership and highest role per item
  does not own: execution slots, bytes, or rendering
                    |
                    v
Shared demand executor
  owns: starts, preemption, cancellation, and exact slot release
  exposes: generation-current content results
                    |
                    v
Production body registry
  owns: bytes, protected keys, measured capacity, and LRU eviction
  does not own: demand membership
                    |
                    v
Pierre/Shiki admission
  owns: ranked materialization/highlighting execution
  receives: real Review item identity plus demand rank
                    |
                    v
Visible CodeView result
```

Each boundary can be implemented and tested independently, but the selected-file
latency promise requires rank and identity to survive the entire chain.

## Gap 1: One Shared Immediate Capacity Authority

### Current state

Selected and visible work have separate scheduling/accounting paths. Visible
work can occupy its configured capacity while selected work is admitted through
another path. That is not one global limit and does not guarantee selected
preemption.

### Required contract

- Selected and visible work share one item-keyed active-immediate ledger.
- Combined selected plus visible active starts never exceed six.
- Selected work is the highest sub-rank and preempts obsolete or the
  lowest-ranked visible work when all six slots are occupied.
- Cancellation and completion release a slot exactly once.
- Rapid viewport changes cannot leave stale active records consuming capacity.
- Queue membership is not truncated to enforce concurrency.

### Customer outcome

Clicking a file starts promptly even while viewport work is saturated.

## Gap 2: Nearby And Progressive Background Warming

### Current state

Production handles selected, visible, and some speculative work. It does not
fully provide direction-aware adjacent warming or a resumable background cursor
that eventually progresses through a large review.

### Required contract

Nearby:

- derive membership from virtualizer order without scanning the full package;
- warm two viewports in the current scroll direction and one behind;
- exclude anything already selected or visible;
- recompute deterministically when selection, viewport, direction, or
  generation changes.

Background:

- start at most one background item at a time;
- run only while the pane is foreground and higher tiers are empty;
- yield immediately when selected, visible, nearby, or speculative work
  appears;
- suspend while hidden without advancing the cursor;
- resume from the same cursor when foreground authority returns;
- advance only after a successful current-generation completion.

### Customer outcome

Adjacent navigation is more often warm, and large reviews progressively become
ready without harming selected or visible interaction.

## Gap 3: A Production Byte-Owning Body Registry

### Current state

A body-registry concept exists, but the production comm-worker/store does not
use it as the authoritative owner of loaded Review bodies. Identity-only cache
entries do not prove bounded byte retention, protected visible content, or
deterministic release.

### Required contract

- One pane-local production registry owns Review body bytes.
- Every entry records exact byte size, content identity, freshness, and
  generation.
- Selected and visible entries are protected from ordinary eviction.
- Unprotected entries evict in deterministic least-recently-used order.
- Per-item and total byte limits remain separate from demand membership and
  execution concurrency.
- Generation reset and pane teardown release retained bytes exactly once.
- Oversized content follows the existing oversized/windowed behavior rather
  than forcing unbounded residency.

### Customer outcome

Returning to recently viewed files avoids unnecessary reload and reconstruction
while memory remains bounded and attributable.

## Gap 4: Demand Rank Reaches Real Pierre/Shiki Work

### Current state

Review demand rank is calculated before worker publication, but the real
CodeView item/file task shape does not carry that numeric rank into the
Pierre/Shiki scheduler. The scheduler therefore treats production Review tasks
as unranked even though lower-level tests can fabricate ranked inputs.

### Required contract

- The typed Review item passed into real CodeView/Pierre admission carries its
  demand rank.
- Selected work ranks ahead of visible, nearby, speculative, and background
  work.
- The rank remains generation-bound and cannot be inherited by a stale item.
- Production integration proof starts from a real Review diff job; constructing
  a ranked test-only file object is not sufficient.
- Equal-rank tasks may complete out of order, but lower-rank saturation cannot
  indefinitely delay selected work.

### Customer outcome

The file the user selected is highlighted and displayed before lower-value
offscreen work under renderer pressure.

## Cross-Cutting Invariants

```text
membership   = what the product currently wants
concurrency  = how many starts the executor permits
retention    = what completed bytes remain cached
rank         = which runnable work matters most
```

These are separate authorities. One number or map must not silently serve more
than one of them.

Additional invariants:

- selected work always outranks every other tier;
- desired membership is latest-wins and generation-bound;
- capacity pressure queues or preempts work; it does not silently drop desired
  membership;
- hidden panes start no background work;
- cancellation, completion, eviction, generation reset, and teardown each have
  exact ownership and idempotent release;
- demand and cache telemetry use bounded taxonomies and never export content,
  paths, prompts, or raw identifiers.

## Tradeoffs

One shared immediate ledger adds lifecycle state, but it removes conflicting
capacity authorities and makes the six-start guarantee enforceable.

Nearby and background warming add controlled work that is not immediately
visible. Their value depends on strict yielding; without that contract they
become latency competition rather than optimization.

A byte-owning registry adds explicit memory accounting and eviction work. The
alternative is lower implementation cost but no enforceable memory or re-entry
latency contract.

Rank propagation widens the typed task contract through multiple layers. The
cost is justified because computing rank without delivering it to the real
scheduler provides no product benefit.

## Proof Expectations

The implementation plan must provide permanent proof at the narrowest real
boundary:

- deterministic reconciler tests for membership, direction, tier deduplication,
  suspension, and cursor resumption;
- executor tests holding six visible starts while selected work arrives,
  proving preemption and exactly-once release;
- production-store integration proving bodies, measured bytes, protected keys,
  eviction, generation reset, and teardown;
- real Review diff-to-CodeView integration proving demand rank reaches the
  Pierre/Shiki task;
- Browser/native heavy-scroll proof with no blank or wrong visible rows;
- performance evidence meeting the existing Review click, scroll, foreground
  queue-wait, and visible queue-wait budgets in
  [performance-demand-lanes.md](performance-demand-lanes.md).

Test-only ranked objects, identity-only cache maps, simulated membership counts,
or a dev-server route that bypasses the production comm-worker are not accepted
substitutes.

## Completion Condition

This specification is complete when all four production gaps are connected and
the proof chain shows:

```text
combined immediate active starts <= 6
selected preempts lower-ranked visible work
nearby membership is direction-aware and bounded by viewport shape
background active starts <= 1 and hidden background starts = 0
production body bytes are measured, bounded, protected, and released
real Review Pierre/Shiki tasks receive the correct demand rank
existing click, scroll, and queue-wait budgets remain green
```

