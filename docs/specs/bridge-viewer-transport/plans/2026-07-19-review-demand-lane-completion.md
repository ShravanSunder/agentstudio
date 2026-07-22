# Review Demand-Lane Completion Plan

Date: 2026-07-19
Status: next-PR plan; explicitly out of scope for current stabilization PR
Depends on: PR-ready completion of
`2026-07-19-bridge-recovery-stabilization-pr-wrapup.md`

## 1. Outcome

Complete the accepted unified Review content-demand scheduler after the current
recovery PR is stable. The next PR must implement six bounded production gaps:

```text
selected/visible  immediate and globally capped
nearby            two viewports ahead, one behind
speculative       hover/prediction; freely droppable
background        one start at a time, foreground only, yields immediately
cancellation      obsolete viewport work aborts and releases capacity
rank propagation  selected/visible priority reaches real Pierre/Shiki work
```

Remove the obsolete 40-file and 25%-of-cache background membership limits.
They are neither batch size nor concurrency. Background concurrency remains
one start at a time; byte-bounded eviction and protected visible/selected
content remain separate retention policy.

## 2. Current Production Baseline

Direct source inventory shows:

- selected and visible demand exist;
- one speculative hover path exists;
- there is no complete nearby reconciler, bounded progressive background
  cursor, global visible-start cap across updates, or obsolete viewport abort;
- native pane foreground authority already suspends/resumes the comm-worker
  scheduler;
- demand/preparation begins through worker `queueMicrotask`, not
  `requestAnimationFrame`;
- rAF remains main-thread paint/visibility/selection proof and is not the owner
  of demand admission;
- the worker Review job preserves lane/priority, but the main render-snapshot
  application stores/submits only the item payload;
- production CodeView item/file/fileDiff shapes do not carry the numeric Pierre
  task rank consumed by `bridge-pierre-worker-pool.tsx`;
- the existing Pierre rank unit test fabricates ranked file tasks and therefore
  does not prove rank propagation from a real Review diff job.
- `performance.bridge.web.review_content_demand` has an adapter and type but no
  production caller, so current runs cannot truthfully report nearby/
  background membership, global active count, cancellation or yield through
  that event.

The normative gap section is in
`docs/specs/bridge-viewer-transport/performance-demand-lanes.md` near the
current-implementation gap inventory. The unified reconciler contract earlier
in that document remains authoritative.

## 3. Scope And Non-Goals

In scope:

- one browser/worker-local desired-demand reconciler;
- nearby derivation from current virtual ranges and scroll direction;
- resumable background cursor with foreground-only suspension;
- global active-start accounting across rapid updates;
- cancellation/terminalization of obsolete viewport work;
- end-to-end Review rank propagation into actual Pierre/Shiki task admission;
- removal of 40-file/25%-cache membership constants;
- a production byte-owning Review body registry with selected/visible
  protection, measured capacity and owner-attributed retention telemetry;
- unit, Browser, Vite, packaged and performance proof.

Out of scope:

- Swift shared-construction redesign;
- native metadata scheduling changes;
- Pierre source/package/dependency changes;
- a new worker, new harness, compatibility owner, production TS Git, File cap,
  or timeout inflation;
- resurrecting the parked React selection-authority lifecycle;
- background work while a pane is hidden/inactive.

## 4. Requirements / Proof Matrix

| Requirement | Owning slice | Proof | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| Total selected plus visible immediate starts obey one global cap across updates; selected preempts lower-ranked visible work | D1 | rapid-update contention unit/Browser | parent-run scheduler evidence | reconciler generation and combined active count | required |
| Obsolete viewport requests abort, terminalize and release slots/bytes exactly once | D1 | abort red/green, Browser heavy scroll, packaged telemetry | parent-run test and metrics | request generation, marker | required |
| Nearby is two viewports ahead and one behind, direction aware | D2 | pure policy unit plus Browser virtualizer journey | parent-run tests | final source generation and viewport sequence | required |
| Background cursor progresses one item at a time only while foreground and yields to any higher tier | D3 | deterministic reconciler unit, mode-idle integration, packaged run | parent-run tests/Victoria | pane activity epoch and marker | required |
| 40-file/25%-cache membership limits are gone | D3 | static/policy tests plus progressive background proof | parent audit/workload | final diff, cursor progress, marker | required |
| Production Review bodies are retained by one byte-bounded LRU with selected/visible protection | D3b | registry/store unit, worker integration, memory workload | parent tests/workload | final diff, measured capacity, owner totals, marker | required |
| Selected/visible rank reaches real Review Pierre/Shiki tasks | D4 | real-diff rank integration, Browser/Pierre evidence | parent-run tests | item generation, lane, worker task | required |
| Heavy scroll remains within interaction/queue budgets | D5 | >=100 scroll/click samples, p95/p99 and zero blank/wrong rows | workload verifier | final SHA/runtime/machine/marker | stop-line gate |
| Inactive pane suspends all background starts and resumes cursor without starvation | D3/D5 | hidden/foreground flip and mode-idle smoke | parent-run verifier | pane activity epoch and marker | required |

Stop lines remain:

```text
Review click p95 < 100 ms, p99 < 200 ms
Review scroll p95 < 100 ms, p99 < 200 ms
foreground queue wait p95 < 16 ms, p99 < 32 ms
visible queue wait p95 < 32 ms, p99 < 64 ms
blank/wrong visible rows = 0
background active starts <= 1 per pane
inactive background active starts = 0
```

Nearby/speculative/background have no standalone latency budget, but they may
not worsen foreground/visible budgets or starve manifest progress.

## 5. Vertical Slices

### D0 — Freeze Baseline And Failing Proofs

- verify the current PR head is clean and all stabilization gates are green;
- inventory existing demand-policy/reconciler/hydration/worker/Pierre paths;
- capture baseline controlled workload metrics;
- add no production code until each planned behavior has its smallest failing
  permanent test.

Checkpoint: baseline/proof receipt; no behavior commit.

### D1 — Global Immediate Lifecycle: Selected/Visible Cap And Obsolete Cancellation

Replace generation-local ticket counting with one item-keyed active-immediate
ledger shared by selected and visible records. Each record retains the ticket,
child abort controller and parent-abort detach. At the start of every viewport
reconciliation:

1. synchronously abort/remove active work whose item is no longer visible;
2. release its active/in-flight capacity before planning new starts;
3. compute `availableStarts = 6 - activeImmediateCount` across selected plus
   visible work across all updates;
4. keep fetch/preparation publication membership-gated so a late obsolete
   completion cannot publish.

Selected is the highest rank inside this immediate ledger. When selected work
arrives at capacity, it preempts one obsolete or lowest-ranked visible record;
the combined active count never exceeds six, and the released record
terminalizes exactly once.

Likely owner:

- `bridge-comm-worker-review-demand-scheduling.ts`;
- `bridge-comm-worker-executor.ts` only if active-capacity calculation belongs
  at that boundary;
- existing scheduling/executor tests.

Red/green:

- hold six viewport-A opens unresolved, then submit selected work and viewport
  B/C repeatedly;
- total selected plus visible active starts never exceeds six;
- selected starts as soon as one obsolete/lower-ranked visible record releases;
- obsolete A controllers abort and release slots in the same turn;
- current members begin as capacity opens;
- late obsolete completions cannot publish;
- terminalization releases every slot/controller exactly once.

Checkpoint commit after focused scheduler/executor and Browser contention
proof.

### D2 — Nearby Derivation

Derive ordered nearby membership worker-side from previous/current viewport
ranges and `orderedIds`: two viewports ahead and one behind. Initial direction
is forward; a stable range retains the previous direction. Selected and visible
remain immediate and always outrank/deduplicate nearby. The derivation is pure,
generation-bound and never truncates membership. Existing nearby execution
capacity remains two starts.

Likely writes:

- `bridge-comm-worker-reconciler.ts`;
- `bridge-comm-worker-store.ts`;
- `bridge-comm-worker-review-demand-scheduling.ts`;
- `BridgeWeb/src/core/demand/bridge-content-demand-policy.ts`;
- existing reconciler/store/scheduling tests.

Red/green:

- forward/backward, boundary, short-list and reset cases;
- selected/visible exclusion and deterministic order;
- Browser proof that heavy scroll updates desired membership without duplicate
  starts.

Checkpoint commit after focused unit and Browser proof.

### D3 — Progressive Foreground-Only Background Cursor

Replace the 40-file/25%-cache membership cap with an ordered resumable cursor.
At most one background item starts at a time. Before every start, recheck pane
foreground authority and the absence of selected/visible/nearby/speculative
work. Higher-tier arrival immediately aborts/cancels background work, releases
capacity and does not advance the cursor; hidden/inactive state suspends without
advancing the cursor. Only a successful current completion advances it.

Retention remains separate:

```text
demand membership: what should load next
concurrency:       how many starts are admitted now (background = 1)
byte cache:        what completed offscreen data may remain resident
```

Red/green:

- more than 40 items eventually progress without starving foreground;
- cache capacity changes do not truncate demand membership;
- hidden pane starts zero background work and resumes at the same cursor;

Checkpoint commit after unit, Browser and mode-idle proof.

### D3b — Production Byte-Body Registry And Protected LRU

Wire the existing `bridge-body-registry.ts` concept into the production comm
worker instead of treating `bridge-comm-worker-store.ts`'s identity-only
`byteCache: Map<string, string>` or the unit-only registry as retention proof.
The comm-worker store owns one pane-local byte registry; Review content-ready
and materialization paths put bodies with measured byte length and freshness
key. Selected and visible keys are protected during eviction;
lower-tier/offscreen LRU entries evict first. Stale-generation and pane teardown
paths release their bytes exactly once.

Likely writes:

- `BridgeWeb/src/core/demand/bridge-body-registry.ts` and its unit tests;
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-store.ts` and tests;
- Review content-ready/preparation/materialization paths that currently write
  identity-only cache entries;
- existing worker telemetry snapshots for scrubbed capacity, retained,
  protected and evicted byte totals.

Red/green:

- production integration proves bodies, not only identities, enter the
  registry with exact byte accounting;
- capacity is measured/configured from the representative workload rather than
  derived from the removed 25% membership rule;
- selected/visible content survives pressure while oldest unprotected content
  evicts deterministically;
- replacement, stale generation, cancellation and teardown drain owner totals
  to the expected baseline without double release;
- baseline/peak/post-drain memory evidence attributes registry bytes separately
  from descriptive process RSS.

Checkpoint commit after registry/store integration and focused memory proof.

### D4 — Real Review Rank Into Pierre/Shiki

First create a red path covering an actual worker Review diff job through main
publication into a real CodeView/Pierre task under saturation. Carry the
reconciler's selected/visible rank only after that proof exposes a stable public
task correlation. Preserve rank as scheduling metadata; do not change Pierre
or Shiki source, add another queue, or deepen reliance on private internals.

Likely writes:

- `bridge-worker-review-pierre-job-planner.ts` only if the existing payload
  boundary needs an explicit typed field;
- `bridge-app-review-render-snapshot-controller.ts`;
- Review CodeView materialization/prepared-item types;
- `bridge-pierre-worker-pool.tsx` adapter and its existing rank tests;
- focused real Review-diff integration tests.

Red/green:

- a real selected Review diff task outranks visible, nearby, speculative and
  background tasks;
- a real visible task outranks lower tiers;
- equal-rank FIFO remains stable;
- reset/stale tasks cannot retain rank authority;
- no fabricated file-only fixture may satisfy the end-to-end proof.

Split/reconverge if no stable public task identity/API exists.

Checkpoint commit after unit, real-diff integration and Browser/Pierre proof.

### D5 — Product And Performance Closure

Run focused lower gates, full BridgeWeb gates, Vite E2E, hosted WebKit, existing
packaged WKWebView journey, actual-worktree two-pane heavy-scroll validation,
and the two accepted representative workloads.

Add scrubbed reconciler/scheduler membership, active, in-flight, abort, yield
and cap facts through the existing telemetry transport; this is proof support,
not a sixth demand owner. Collect per-lane counts, active/queued/aborted/deferred/stale totals,
click/scroll/queue p95 and p99, memory baseline/peak/drain, manifest progress,
telemetry loss, and source-to-paint correctness. Do not call exploratory manual
samples final percentile proof.

Complete one implementation review/remediation cycle and PR wrap-up as a
separate PR. Do not merge without explicit authorization.

## 6. Execution DAG

```text
D0 baseline + six failing proofs
  |
  +--> D1 global selected/visible lifecycle (cap + cancellation)
  |       |
  |       v
  |     D2 nearby derivation
  |       |
  |       v
  |     D3 background cursor/yield + delete 40/25 limits
  |       |
  |       v
  |     D3b production byte-body registry + protected LRU
  |
  +--> D4 real Review rank propagation (parallel after real-task RED)
  |
  v
integration gate: one reconciler, one rank vocabulary, no duplicate owner
  |
  v
D5 product/performance/full quality
  |
  v
implementation review -> one remediation -> CI/PR ready, not merged
```

`bridge-comm-worker-review-demand-scheduling.ts` is a conflict hot spot, so
D1-D3 production edits are serial even when proof design/review runs in
parallel. D4 may proceed in parallel after its real-task correlation RED fixes
the typed boundary and its write scope is disjoint.

## 7. Split / Replan Triggers

Stop and reconverge if:

- native metadata scheduling must change to implement content demand;
- Pierre source or dependency changes appear necessary;
- cache retention and demand membership cannot be separated cleanly;
- the global cap requires more than one demand owner;
- hidden panes need background hydration to meet correctness;
- a proof needs a new harness instead of extending the existing permanent
  suites/verifiers;
- the work cannot preserve the current PR's two-pane/shared-construction proof.
