# Targeted Runtime Pressure Reduction

Date: 2026-07-17
Status: reviewed and accepted for implementation
Source baseline: `ghostty-performance-cleanup` at `5dea96b6`
Parent contract: [AgentStudio Performance Boundaries](../2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)

## Product Intent

AgentStudio should use materially less CPU, attributable allocation/retained
memory pressure, task scheduling, EventBus fanout, and MainActor service while
terminals produce output, users search or interact with terminal presentation,
watched folders contain hundreds of repositories, and Git refreshes run. Process
physical footprint/RSS is a guardrail rather than the sole memory signal because
allocator and VM caching can hide reclaimed transient allocations after the
owned work has quiesced.

The cleaned branch already has the important heavy-work owners: Ghostty owns its
host callbacks, `FilesystemActor` owns authorized filesystem ingestion,
bounded schedulers own scanning and Git reads, `FilesystemProjectionIndex` owns
off-main projection, and the startup composition/mount lanes already separate
strict loading from bounded visible-first hosting. The remaining problem is
narrower: ordinary local terminal samples become one MainActor job each before
expanding into shared replay, fanout, reducer, and activity processing; unrelated
workspace actions still trigger full repository/worktree/pane capture instead of
affected-key filesystem effects.

This design reduces that expansion using existing owners. It does not create a
new event system, callback architecture, admission framework, persistence
system, repair system, or diagnostic subsystem.

## Success Shape

The design is successful when all of the following are true:

1. Coalescible Ghostty presentation/activity samples are copied and classified
   synchronously, retained in bounded keyed state, and drained in batches rather
   than creating one MainActor task and one consumer call per raw sample.
2. Terminal presentation remains fully functional while those samples produce
   no runtime envelope, replay record, EventBus post/delivery, or IPC wait event.
3. Scrollbar evidence is compressed without losing positive output growth,
   reset/decrease boundaries, pinned/observed edges, or quiet settlement; heavy
   activity projection runs off MainActor and publishes semantic transitions.
4. Exact commands and semantic facts keep their existing ordered behavior. Local
   sample pressure cannot occupy their bounded channel; fact-only saturation is
   preserved as a separate pre-existing limitation.
5. Unrelated workspace actions no longer schedule a full repository/worktree/
   pane capture. Actual topology changes retain one batched reconciliation;
   pane, CWD, activity, and active-worktree changes use fixed-key edges.
6. MainActor performs only bounded capture/current lookup, compact accepted
   applies, relevant host mutations, and canonical state mutations.
7. Existing UI consumers preserve terminal, notification, watched-folder,
   repository, pane, tab, and startup behavior without becoming implementation
   lanes in this spec.
8. Runtime evidence from existing tests, runners, IPC, and Victoria surfaces
   proves lower CPU, attributable allocation/retained
   memory pressure, scheduling/fanout amplification, and targeted MainActor duty
   without material physical-footprint/RSS, correctness, or stability regression.

## Current-State Baseline

### Terminal amplification

`Ghostty.CallbackRouter.action_cb` must return Ghostty's handled Boolean
synchronously. `Ghostty.ActionRouter` copies and translates payloads, then
creates a `Task { @MainActor }` for each routed action. `TerminalRuntime` updates
observable state and calls `PaneRuntimeEventChannel.emit` for local presentation
samples and semantic facts alike.

Each channel emission performs sequence allocation, envelope construction,
optional local replay, local subscriber fanout, and an offer to a
`.bufferingNewest(128)` outbound stream. The detached consumer posts to the
shared EventBus. The shared bus appends every posted envelope to a 256-entry-
per-source replay and yields it to every subscriber.

Downstream lossy consolidation happens only after those costs. The MainActor
`TerminalActivityRouter` also consumes every scrollbar sample, mutates activity
windows, updates atom state, and cancels/recreates quiet tasks. The workspace
coordinator performs tab lookup before ignoring many sample cases.
`persistForReplay: false` skips only local replay; it does not prevent global
posting or global replay.

### Scrollbar semantics

Scrollbar state is both presentation and evidence:

- the terminal surface and overlays need the current viewport;
- `TerminalActivityRouter` uses total rows, quiet timing, attention, and pinned
  state to derive unseen output and today's `agentSettled*` heuristic. This
  design preserves its behavior as terminal-output-settled evidence rather than
  treating it as agent lifecycle authority;
- `InboxNotificationRouter` uses pinned-to-bottom transitions to clear observed
  notifications;
- only the lower-rate derived activity outcomes are meaningful global facts.

Therefore scrollbar cannot be treated as “drop it” or “latest UI value only.”

### Filesystem amplification

`FilesystemActor` already performs authorized canonical routing, filtering,
debounce, and bounded path chunking off-main. Git status admission and reads are
also off-main and bounded.

Every workspace action currently schedules filesystem root/activity sync. The
sync pass captures every available repository/worktree and every pane on
MainActor even when the action did not change those relationships. Git/cache
changes also request trace-identity refresh explicitly while a broad observation
of the same inputs can request the same all-repo/worktree/pane reconstruction.

### Measured cleanup baseline

The current real watched-folder qualification contained 100 repositories and
106 worktrees. It recorded 118 Git status completions, pending high-water 102,
final pending zero, four bounded running slots, and three explicit one-second
timeouts. Across 94 coordinator records, maximum measured MainActor apply was
0.063 ms while maximum total coordinator time was 189.957 ms.

Those numbers prove bounded Git convergence and distinguish compact apply from
awaited end-to-end work. They do not prove terminal responsiveness, do not prove
the 189.957 ms was MainActor occupancy, and do not by themselves prove this
design's improvement.

## Design Boundary And Separability Map

```text
Ghostty callback and payload translation                 unchanged owner
  owns: synchronous handled result, borrowed-payload copy
  exposes: strict copied signal disposition + surface-lifetime key
             │
             ├── exact command/fact ─────────► existing MainActor route
             │                                      │
             │                                      ▼
             │                                TerminalRuntime
             │                                      │ semantic facts only
             │                                      ▼
             │                                PaneRuntimeEventChannel
             │                                      │
             │                                      ▼
             │                                existing EventBus
             │
             └── coalescible sample ─────────► TerminalLocalActionAccumulator
                                                bounded by live surfaces +
                                                fixed signal keys
                                                     │
                          ┌──────────────────────────┴──────────────────────┐
                          ▼                                                 ▼
                 one MainActor batch apply                    activity aggregate
                 latest presentation state                              │
                                                                         ▼
                                                        TerminalActivityProjector actor
                                                        off-main state/timers
                                                                         │
                                                                         ▼
                                                        semantic transitions
                                                                         │
                                                                         ▼
                                                        TerminalActivityRouter
                                                        MainActor adapter:
                                                        bus/context + compact state

FilesystemActor / GitWorkingDirectoryProjector       unchanged authority
  owns: registered roots, routing, filtering, bounded Git worktree facts
  coordinated by: existing pipeline and accepted topology effects
  exposes: existing authorized worktree facts through existing EventBus
                         │
                         ▼
FilesystemProjectionIndex                             off-main projection owner
  owns: rebuildable worktree/pane reverse indexes and currentness checks
  exposes: compact affected-key projection
                         │
                         ▼
WorkspaceSurfaceCoordinator                           effect owner
  owns: topology-triggered fleet reconciliation plus pane/CWD/active-worktree
        fixed-key effects
                         │
                         ▼
canonical atoms + keyed cache slots                   compact MainActor apply
```

These surfaces are separable:

- Terminal batching may change without changing exact facts, EventBus, or
  filesystem routing.
- Filesystem trigger proportionality may change without changing watcher,
  scanner, Git capacity, or topology authority.
- Repo Explorer, AppKit, and other UI consumers remain unchanged validation
  surfaces for this implementation slice.
- Observability measures each surface but owns no correctness state.

## Terminal Signal Contract

### Existing Ghostty boundary remains

TR-1. Ghostty callback ownership, payload-copy rules, target resolution, and
synchronous handled-result semantics remain unchanged. This spec does not move
`ghostty_app_tick`, redesign `action_cb`, add a gather thread, or claim callbacks
are safe to execute on an unproven actor.

TR-2. After synchronously copying any borrowed payload, the Terminal feature
classifies each signal before choosing its MainActor scheduling path. Exact
commands and semantic facts retain the existing route. Coalescible presentation
and activity samples enter one Terminal-owned keyed accumulator that permits at
most one scheduled MainActor drain per live surface while work is pending. The
same narrow per-surface serialization boundary admits meaning-changing local
lifecycle barriers; it does not turn semantic facts into queued samples.

TR-3. Signal disposition is one exhaustive discriminated union. It distinguishes
exact command/fact, latest presentation value, activity evidence, and diagnostic
outcome. It contains no optional callback, multiple-Boolean lifecycle, string
tag, or default “emit everything” branch. `TerminalRuntime` remains the semantic
publication boundary after current pane/surface resolution; it is not the first
place where coalescible samples are contracted.

TR-3a. The accumulator is a narrow Terminal implementation, not a generic
mailbox or reusable admission framework. Its coalescible retained storage is
bounded by the number of live surfaces and a compile-time-fixed signal-key set,
not by raw sample count. Callback offers and lifecycle barriers have one
synchronous per-surface linearization point and are safe under reentrant or
concurrent callback delivery. The accumulator retains copied Sendable values
and non-retaining lifetime identity only—never borrowed C pointers, a strong
`SurfaceView`, controller, atom, Inbox policy, or EventBus state.

### Signal classification

| Signal class | Current examples | Required route | Runtime/global replay |
| --- | --- | --- | --- |
| Local presentation | scrollbar viewport; mouse shape/visibility; search matches/selection | Keyed latest value, one batch apply, equal-write suppression | Never |
| Local ordered lifecycle | search start/end and other local state boundaries whose order changes meaning | Exact local transition without runtime/global publication | Never |
| Local activity evidence | total rows, pinned edges, observation/attention context, output timing | Bounded sufficient-statistics aggregate to off-main activity owner | Raw evidence never; derived outcomes only |
| Direct host state | initial size, cell size, current configuration snapshot | Preserve the existing direct `SurfaceView` cache/update; do not duplicate it in runtime or accumulator state | Never |
| Local state plus semantic transition | progress, secure input, renderer health, read-only | Current state stays local; deduped cross-feature/IPC transitions retain their existing semantic route | Only changed semantic transitions |
| Exact semantic fact | command finished, bell, desktop notification, deduped title/tab title/CWD, lifecycle/security facts | `PaneRuntimeEventChannel` and existing EventBus | Domain-specific existing replay |
| Host command/control | tab/split/navigation/close, URL/clipboard/undo/redo/prompt/config control | Preserve the existing direct or exact command/control behavior | Never converted into a lossy UI sample |
| Diagnostic-only | size limits, mouse link, key sequence/table, color change, deferred/unhandled outcomes with no demonstrated product consumer | Existing bounded diagnostic treatment or typed drop | Never |

TR-4. The hard-cut local-only set is exhaustive for scrollbar, mouse
shape/visibility, search state, direct host geometry/config state, and typed
diagnostic/drop outcomes with no product consumer. These cases must not call
`PaneRuntimeEventChannel.emit`, appear in `PaneRuntime.subscribe`, consume local
or global replay, reach EventBus subscribers, or satisfy IPC event waits.

TR-4a. Direct host state is not copied into accumulator storage merely to
preserve an obsolete runtime event. Initial/cell-size and configuration updates
retain their existing direct host cache behavior. Size-limit, link, key-table,
and color cases gain retained state only if implementation revalidation finds a
live product consumer; diagnostics/replay alone are not such a consumer.

TR-5. Local does not mean discarded. The latest current-surface presentation
value remains available. Equal repeated presentation values do not wake
Observation. They are not treated as new output evidence unless a distinct
semantic signal proves activity.

TR-6. Search remains a typed lifecycle, with inactive and active states distinct
at compile time. Unknown match count or selection may remain optional evidence
inside the active state; optional values must not encode whether search itself is
active. Search start, query, next/previous, match total, selected match, cancel,
close, keyboard responder behavior, overlay hit testing, and visible result text
remain unchanged. Search start/end are exact local lifecycle barriers. Each
barrier splits or invalidates pending search values from the prior lifecycle;
match/selection values carry that local lifecycle identity, and a late batch from
an ended search cannot synthesize or reactivate active search state.

TR-7. Every offer, batch, drain, and cleanup is scoped to one terminal-surface
lifetime, not an address-derived `ObjectIdentifier` alone. The lifetime key may
reuse existing managed-surface identity or a narrow non-durable Terminal-local
token. A batch resolves the current surface-to-pane/runtime mapping and verifies
that same lifetime immediately before apply. Close, replacement, remount, or
teardown uses compare-and-remove semantics: old cleanup cannot delete replacement
work, and an old batch cannot apply to a new surface even if an address is reused.
No new durable ID or cross-owner runtime generation is introduced solely for
sample batching.

### Scrollbar activity contract

TR-8. Scrollbar callbacks produce two independent batch products:

1. the latest viewport state for one compact presentation apply; and
2. a bounded activity aggregate for off-main projection.

The second route is a private Terminal-feature seam, not a generic event bus,
actor-per-pane fleet, replay log, or persisted history.

TR-9. One batch preserves sufficient statistics rather than only its final
viewport value. At minimum it retains:

- cumulative positive row growth, including growth before a reset/decrease;
- first and latest qualifying activity time;
- pinned-to-bottom entry/exit edges even when the final value hides them;
- attended/observed suppression and reset;
- sample count plus first/latest total and pinned state; and
- close, stop, replacement, and cancellation boundaries.

While a drain is active, new samples update the next bounded batch and request at
most one follow-up drain. Exact semantic facts never enter or wait behind this
state. Exact local lifecycle changes and activity-affecting control transitions
instead act as narrow barriers: earlier affected sample state is detached,
retired, or epoch-invalidated before the boundary, and later samples belong to
the next side of the boundary.

TR-10. Activity windows, quiet timing, output/settled projection, and revocation
move into one Terminal-owned `TerminalActivityProjector` actor that consumes
batch aggregates off MainActor. `TerminalActivityRouter` remains a thin
MainActor adapter for the existing exact semantic-fact subscription, current
attended/observation context, pane-close cleanup, and compact accepted
`TerminalActivityAtom` apply. The atom stores current state only; it does not
classify events or own timers.

Derived pinned/observed and output-settled transitions use the existing
`TerminalActivityEvent` semantic-fact route and are published only when their
semantic value changes. Adding the required typed derived cases does not change
EventBus implementation or restore raw scrollbar publication. Inbox consumes
those derived facts, never raw scrollbar samples.

TR-10a. Attention, observation, read/dismiss, close, reset, and semantic signals
that revoke or split activity windows enter the projector through the MainActor
adapter as typed ordered controls. When one crosses pending evidence, the
adapter first detaches the earlier aggregate and submits aggregate then control
in semantic order; later evidence enters a new aggregate. The projector does
not infer historical attention from whichever state happens to be current when
a delayed batch arrives. This adapter/projector seam is private Terminal
implementation, not EventBus replacement or atom workflow.

TR-11. An injected-clock semantic oracle—not delivery-count parity—proves unseen
activity, output-settled promotion/revocation, first-output evidence,
pinned-to-bottom clearing, read/dismiss behavior, and quiet settlement. Duplicate
presentation samples with no new evidence do not extend activity windows. The
oracle includes gated-drain interleavings for focus/blur, observation/read,
reset, close/replacement, and activity-resetting semantic signals.

### Agent lifecycle boundary

TR-11a. Terminal activity and agent lifecycle are separate authorities.
Scrollbar growth, output timing, and terminal silence may establish only
terminal-output evidence. They do not author `working`, `blocked`, or `idle`
agent lifecycle state.

TR-11b. Existing `agentSettled*` event/model names, thresholds, and the consumed
pane-classification candidacy gate remain compatibility vocabulary in this
performance slice. They mean “terminal output settled for a pane already
classified elsewhere,” not “this projector determined agent lifecycle.” Their
count/order and Inbox behavior are preserved; renaming the cross-feature
vocabulary is outside this slice.

TR-11c. A later focused design may combine authenticated agent hook/plugin
reports with independently implemented, bounded terminal-screen heuristics for
agents whose hooks are incomplete. That future work must preserve existing
pane-bound IPC authorization and treat Ghostty text extraction as an expensive,
throttled request. This spec adds no hook installer, pane relay, lifecycle IPC
method, screen polling, detection manifest, or Ghostty/zmx modification.

### Semantic-fact contract

TR-12. Title, tab title, CWD, progress, secure-input, renderer-health, and other
state-like semantic facts are emitted only when their semantic value changes.
Progress remains available to the stable IPC `progressChanged` condition;
secure-input activation and renderer-unhealthy transitions remain available to
Inbox; renderer-healthy remains available to IPC.

TR-13. Retained semantic facts preserve the current per-pane sequence,
`PaneRuntimeEventChannel`, runtime subscription/replay, IPC `afterSequence`, and
EventBus behavior. Local-only samples never allocate a sequence or occupy those
paths, so sample pressure cannot cause their bounded outbound queue to evict a
semantic fact.

TR-14. Fact-only saturation behavior is a known pre-existing limitation and is
not redesigned by this slice. The channel remains finite and bounded; this spec
does not replace newest buffering with an unbounded queue, introduce rejection/
gap semantics, or change EventBus delivery. A measured fact-only overflow or
replay-gap regression is a revisit trigger for a separate delivery contract.

TR-15. Content-bearing semantic envelopes that remain in local runtime replay
retain realistic payload-aware byte accounting plus existing count and TTL
bounds. Global EventBus replay remains unchanged and count-bounded per source.
No new stringify fallback may log retained payload content.

## Filesystem Projection Contract

### Existing source owners remain

FS-1. `FilesystemActor` remains the only owner of registered filesystem source
authority, deepest-root routing, canonical root association, filtering,
debounce, bounded path chunking, watched-folder result application, and raw
worktree fact publication.

FS-2. The existing watched-folder scheduler, scanner, validation executor, Git
working-directory projector/provider, explicit operation budgets, physical
capacity bounds, and `GIT_OPTIONAL_LOCKS=0` behavior remain unchanged. This
design does not add repository locks or borrow capacity from mutation/network
Git operations.

FS-3. Raw callback paths, scanner candidates, Git metadata, and pane CWDs are
evidence. They cannot register a root, widen authority, or replace the current
registered-source identity.

### Proportional trigger model

FS-4. A full topology snapshot is permitted for cold in-memory bootstrap, an
explicit rebuild, or one accepted actual-topology mutation batch. It is not a
valid tail action for every workspace command, pane change, selection, layout,
sidebar, inbox, or presentation mutation.

FS-5. Ordinary changes use the narrowest existing owner edge:

- pane mount/create/close updates only that pane's membership;
- CWD/worktree reassignment updates only that pane and affected worktree
  activity;
- active pane changes update only active-worktree priority;
- unrelated layout, sidebar, inbox, presentation, and no-op actions schedule no
  filesystem root/activity reconciliation.

FS-5a. Accepted `WorktreeTopologyDelta` batches remain the ordered topology
effect edge. They may trigger one existing full source/index reconciliation per
accepted batch. This spec does not add a second topology-delta algebra or a new
cross-owner generation protocol. Incremental topology authority is a revisit
only if post-cut evidence shows actual topology reconciliation—not unconditional
triggering—is still a dominant cost.

FS-6. Pane/CWD/activity/active-worktree work is O(changed keys plus affected
memberships), not O(all repositories + all worktrees + all panes). One accepted
topology batch may remain fleet-wide and is measured separately.

FS-7. `FilesystemProjectionIndex` remains an actor-owned, in-memory,
rebuildable index. It owns no atoms, persistence, repair, durable journal,
consumer registry, mounted-view truth, or canonical product topology.

FS-8. Existing index mutation and projection ordering remains provable. The
implementation may simplify today's pending snapshots, generations, and waiters
only when one serialized boundary or equivalent typed currentness check prevents
an older source snapshot from rolling back a newer pane update. No new
persistence or durable generation is introduced.

FS-9. Stale, superseded, and inapplicable outcomes are explicit discriminated
states, not `nil` or overloaded empty arrays. Currentness is revalidated
immediately before registration effects, destructive absence, or downstream
delivery.

## MainActor And Atom Boundaries

MA-1. MainActor continues to own AppKit, Ghostty host interaction, observable
terminal presentation state, canonical atoms, current mounted-view lookup, and
compact accepted mutations.

MA-2. MainActor must not perform filesystem traversal, Git reads, large
serialization, path canonicalization, per-event all-pane filtering, or repeated
all-fleet reconstruction.

MA-3. Callback-side offer cost for a coalescible terminal sample is bounded O(1)
copy/classification/key replacement. MainActor task count and state mutation
scale with drained batches and changed keys, not raw sample count, EventBus
subscribers, replay capacity, tabs, panes, repositories, or worktrees.

MA-4. Atoms remain pure current state or pure derivation. They do not own signal
classification, debounce windows, timers, filesystem projection, path
canonicalization, queues, persistence, revisions, leases, pagers, participants,
or repair.

MA-5. Coordinators and runtime owners decide effects. Atom mutation methods
remain narrow and non-public where the current architecture requires it.

## Type And Static Enforcement Contract

TY-1. New and changed routing/control contracts use exhaustive enums or structs
with explicit invariants. Optional values represent genuinely absent payload
evidence, not lifecycle, acceptance, currentness, or ownership states.

TY-2. The terminal disposition switch is exhaustive over current translated
signals. Adding a Ghostty signal without choosing exact command/fact, latest
presentation, activity evidence, exact local lifecycle, or diagnostic outcome
fails compilation or architecture lint.

TY-3. Local-only signal cases cannot call the semantic publication helper. The
smallest SwiftSyntax rule may enforce this after behavior is cut over; no new
lint framework or shell-based architecture checker is introduced.

TY-4. Enforcement is proportionate to what each mechanism can prove:

- existing named SwiftSyntax rules continue to protect their current AtomLib,
  declared-input, keyed-read, comparator, import, and placement boundaries;
- one narrow new SwiftSyntax rule may protect the mechanically recognizable
  forbidden Terminal publication edge from TY-2 and TY-3 when the final type
  surface alone cannot make it impossible;
- targeted structural tests protect named filesystem/Git heavy-work seams and
  atom workflow exclusions;
- Victoria queue-age and service-time evidence proves actual MainActor cost.

No general “pure atom” or “expensive MainActor” heuristic lint is claimed.
Lint is a final regression guard, not the performance implementation or proof of
product responsiveness.

## Security And Trust Invariants

SEC-1. Evidence never mints filesystem authority. Only an existing
host-authorized registration grants scan scope.

SEC-2. Canonical containment remains absolute, local-volume and volume-identity
aware, case/Unicode aware where required, lexical and once-resolved, and checked
before and after Git discovery where the current source requires it.

SEC-3. Callback routing remains bound to a current registered source and uses
deepest-root ownership for nested worktrees.

SEC-4. Registration, scan run, demand coverage, pane context, topology,
terminal-surface lifetime, and projection request identity remain where they are
required to reject stale or ABA results. Compact does not mean deleting
currentness evidence.

SEC-5. Only complete, current, authoritative scan evidence may express
destructive absence. Partial, unavailable, failed, timed-out, cancelled,
superseded, or dropped evidence is additive or preserving.

SEC-6. A logical Git timeout does not prove absence, stop a non-cooperative
native read, or manufacture a free physical slot. Late returns cannot re-enter
current truth.

SEC-7. Projection accepts only internal canonical root-relative evidence from
the filesystem owner. It is not an untrusted path parser or new IPC/plugin
surface.

SEC-8. New instrumentation in this slice is content-safe before sink fanout:
controlled code-owned bodies plus aggregate counts, durations, and bounded
buckets only. Neither JSONL nor OTLP receives raw paths, pane/surface/
notification IDs, terminal/search/notification content, URLs, prompts,
payloads, errors, tokens, Git output, or projected row content from these new producers.
OTLP projection remains defense in depth and export remains fail-open. This does
not redesign or make a broad safety claim about unrelated existing local logs or
JSONL producers.

SEC-9. Full semantic envelopes retained locally remain content-sensitive.
Existing replay byte, count, and TTL bounds remain effective and payload sizing
accounts for variable strings and collections.

## Proof Expectations

### Structural proof

P-1. Every coalescible terminal case produces the correct current presentation
state with at most one scheduled drain per live surface while work is pending,
bounded storage independent of raw sample count, and lifetime-scoped
compare/apply/remove behavior under close and address reuse, plus exactly zero:

- `PaneRuntimeEventChannel` emissions;
- runtime subscription events;
- local replay writes;
- global EventBus posts and replay writes;
- global subscriber deliveries;
- IPC wait results.

P-2. A large burst proves raw coalescible sample count is greater than MainActor
drain/task count, final state equals an independent last-value oracle, and
activity aggregates equal an independent sufficient-statistics oracle. Gated
drains also prove reentrant/concurrent offers cannot lose replacements, create
duplicate drains, or cross a local lifecycle barrier.

P-3. An interleaved sample stream cannot change the count or order of
command-finished, bell, desktop-notification, title/CWD, progress,
secure-input, renderer-health, lifecycle, or security facts.

P-3a. The same sample-pressure cell proves zero semantic-fact drops and
unchanged runtime/IPC replay behavior while semantic facts are acknowledged or
paced below observed fact-only saturation. Fact-only overload remains a
non-gating revisit signal and is not used to claim a new delivery guarantee.

P-4. Injected-clock raw sequences and their aggregated equivalents produce the
same semantic activity, first-output, output-settled/revoked, pinned/observed,
read, dismiss, and inbox-clearing outcomes. Reset/decrease, growth before reset,
close/replacement, duplicate-state, pinned-edge, focus/blur, observation during a
pending batch, and activity-resetting semantic-signal sequences are included.

P-5. Search, mouse/cursor/visibility/link, cell geometry, scrollbar presentation,
and terminal commands retain their final state and native behavior. Gated
start/matches/end and start/selection/cancel sequences prove a late batch cannot
reactivate or overwrite an ended search lifecycle.

P-6. Ordinary unrelated and fixed-key workspace changes cause no full topology/
pane capture. Pane/CWD/activity/active-worktree mutations update only affected
entries. Cold bootstrap and actual topology mutation batches still converge to
an independent final-state oracle through the existing topology-effect edge.

P-7. Focused deterministic regression proof preserves registered-root
authority, canonical/deepest-root containment, existing topology/currentness
rejection, non-destructive incomplete evidence, Git logical-timeout versus
physical-drain capacity, local replay bounds, and new-producer JSONL/OTLP
content canaries.

### Runtime performance proof

P-9. Runtime proof reuses the existing isolated debug app identity, marker-
scoped Victoria stack, performance recorder, IPC surface, and PID-targeted
native automation. It extends those surfaces only with bounded
aggregate resource/admission metrics; it adds no backend, heartbeat, ledger, or
correctness dependency on telemetry.

P-10. Comparative cells use the same debug flavor, deterministic bundle/data
root, hardware/display environment, workload inputs, trace tags, and trial
policy. The behavioral baseline is the pinned source revision plus the same
behavior-preserving instrumentation layer used by the candidate. Every trial has
a fresh marker and PID and records immutable behavioral source, instrumentation,
and executable/build fingerprints. Metrics absent or semantically different in
the baseline use absolute gates only.

P-11. Reproducible scale proof uses generated fixtures and the existing
large-worktree workload. A separate local qualification may use the configured
development roots under `/Users/shravansunder/Documents/dev/open-source` and
`/Users/shravansunder/Documents/dev/project-dev`; raw roots remain local and are
never exported as telemetry dimensions.

P-12. Metrics are aggregate, content-safe, and distinguish queue age from service
time. The owned measurements include:

- translated terminal signals by controlled class;
- raw coalescible samples, accumulator replacements, scheduled drains,
  follow-up drains, MainActor tasks, activity aggregates, compact applies, and
  equal-write suppressions;
- runtime-channel and global posts by semantic class;
- EventBus subscriber deliveries, replay writes, drops, and high-water lag;
- filesystem full-reconciliation requests versus fixed-key updates;
- trace-identity refresh requests, coalesced requests, fleet captures, and equal
  snapshot suppressions;
- process CPU time/duty, physical footprint/RSS high-water and post-quiescence
  footprint, bounded pending storage, and relevant task/allocation counts;
- MainActor queue age, compact-apply service, admission count, and targeted
  operation duty;
- existing Git queue/running/timeout/final-pending evidence; and
- existing sidebar, tab, pane, and terminal-geometry distributions only as
  unchanged downstream regression signals.

Paired T1 metric meanings and buckets freeze before baseline capture.
Candidate-only bounded aggregate event vocabulary and content-safe OTLP
projection entries required to expose the new T3/T4 owners may be installed
after that baseline; they remain absolute gates and must never emit one trace
record per raw callback or filesystem path.

Aggregate Victoria distributions must expose threshold-resolving buckets at or
inside 1, 2, 5, 8, and 16 ms for the targeted MainActor metrics, plus p95, p99,
and sample count. A coarse histogram that cannot classify a budget boundary is
not acceptance evidence.

### Workload and statistical contract

P-12a. Validation uses existing product seams instead of building a new proof
script or harness. Each cell has one declared evidence role:

1. deterministic terminal contraction and activity equivalence — candidate-only
   structural/correctness proof;
2. watched-folder/Git proportionality through the existing large-worktree
   workload — paired comparative performance plus correctness proof;
3. one combined real-app pressure qualification — paired primary CPU,
   allocation/retained-memory, physical-footprint/RSS, and targeted-MainActor
   resource proof; and
4. one PID-targeted candidate debug-app smoke for terminal interaction,
   watched-folder convergence, and downstream consumer stability.

P-12b. The deterministic terminal cell processes at least 100,000 coalescible
samples across at least 10 live pane/surface keys and covers every disposition.
Retained semantic facts are interleaved below observed fact-only saturation so
the cell proves isolation from sample pressure rather than redesigning delivery.
The watched-folder cell retains at least 100 repositories/worktrees and multiple
Git writers. Existing repository/sidebar, pane, tab, and startup behavior remains
covered by the current permanent tests and one bounded native smoke; those
consumers do not gain new projection, observation, AX, IPC, or benchmark seams.
Exact workload floors and one-sided noise bands are frozen only for the paired
watched-folder/Git and combined pressure cells; insufficient pressure invalidates
those trials.

P-12c. Cells 2 and 3 use an
unscored warm-up and at least three qualifying baseline and candidate trials.
Percentiles and normalized resource
measurements are calculated per trial and compared using median per-trial values;
trials are not pooled. The plan records calibration evidence for every nonzero
budget and labels fixture-adequacy floors separately from product budgets.

P-12d. A qualifying resource interval begins at the first scored workload action
and ends after the same bounded quiescence condition in both builds; warm-up and
launch setup are excluded. Process CPU duty is process CPU-time delta divided by
that wall interval and is additionally normalized by external accepted stimuli
only when stimulus counts differ. Physical memory uses the same OS population
and sampling cadence for both builds—macOS physical footprint is preferred; RSS
may substitute only symmetrically—and records interval high-water plus the same
post-quiescence sample. Paired targeted MainActor duty is the summed service time
of one declared operation inventory present with identical metric semantics in
both builds, divided by the interval; it must not be called global MainActor
occupancy. Candidate-only Terminal route/commit queue age, admission, drain,
activity, compact-apply, and quiescence metrics are excluded from paired duty and
remain absolute structural/interaction gates. Allocation/retained-byte evidence
uses the same named owner scopes and measurement mechanism in both builds.

P-13. Structural budgets are absolute:

- raw local terminal sample global posts/replay/deliveries: `0`;
- more than one pending scheduled drain per live terminal accumulator key: `0`;
- retained terminal sample storage growth with raw sample count: `0`;
- semantic-fact drops during the declared mixed sample-pressure workload: `0`;
- unrelated workspace actions causing full filesystem reconciliation: `0`;
- accepted/queued logical watched-folder and Git demand after bounded
  quiescence: `0`; timed-out physical drains may remain only while still counted
  against the configured physical slot bound and unable to mutate current truth.

P-14. Initial interaction/resource budgets are:

- compact MainActor apply p95 below 2 ms and p99 below 5 ms;
- callback-to-current-batch-commit queue age p95 below 8 ms and p99 below 16 ms
  during terminal pressure;
- fewer than three targeted MainActor service samples at or above 20 ms in any
  qualifying trial, and none at or above 60 ms;
- normalized CPU, attributable allocation/retained-byte pressure, and paired
  targeted MainActor duty improve beyond the plan-calibrated one-sided noise
  band against the instrumented baseline; candidate-only Terminal admission and
  task counts must independently prove sublinear contraction and zero final debt;
- peak and post-quiescence physical footprint/RSS do not regress beyond the
  plan-calibrated one-sided noise band. When the baseline shows repeatable
  workload-attributable physical-footprint growth above that band, the candidate
  must improve it beyond the band; all new pending storage remains structurally
  bounded;
- zero regression in semantic counts, final state, native interaction, Git
  boundedness, downstream sidebar/pane/tab behavior, or startup readiness.

Callback-to-current-batch-commit queue age is a candidate-only metric because
the behavioral baseline has no semantically equivalent route/commit emitter. It
must meet the absolute p95/p99 budgets in every qualifying candidate trial and
cannot satisfy or be used for a paired improvement claim. One best-case sample
or proxy counter does not pass.

P-15. Stability proof includes crash-free workload execution, successful
bounded quiescence, exact final state, no growth in critical EventBus failures,
zero accepted/queued logical demand, bounded and capacity-accounted physical
Git/native drains, no late-result mutation, bounded runtime-channel/replay
high-water and final retained debt, and successful debug-app relaunch with
terminal/IPC readiness. It does not require an arbitrary multi-day soak.

P-16. Native proof is one bounded smoke, separate from statistical cells. It
validates visible typing/caret response, search start/query/navigation/close,
scroll-away and follow-bottom recovery, cursor/link behavior, notification
appearance/clearing, watched-folder repository discovery, Git-status convergence,
and basic pane/tab/startup stability through existing reliable control surfaces.
It does not add an Accessibility, IPC, UI-driver, or benchmark seam and does not
substitute for deterministic, integration, or Victoria evidence.

## Alternatives And Tradeoffs

### Keep raw samples and rely on reducer coalescing

Rejected. It preserves all work before the reducer: MainActor envelope creation,
replay, subscriber fanout, outbound buffering, queueing, and irrelevant
deliveries.

### Remove EventBus fanout but keep one MainActor job per sample

Rejected. It improves downstream amplification while preserving task creation,
routing lookup, activity processing, and timer churn proportional to raw
Ghostty callback volume. The contraction boundary must precede scheduling for
coalescible samples.

### Add a gather thread or generic mailbox/admission framework

Rejected. A Terminal-owned fixed-key accumulator is required, but a reusable
admission framework is not. A general framework adds leases, revisions,
registries, generic capacity policy, cleanup, and proof burden that these fixed
signal classes do not need.

### Redesign EventBus into topics or a fact plane

Rejected. Existing low-rate semantic facts and authorized worktree facts remain
on the current bus. Producer admission and proportional filesystem effects are
the scoped problems.

### Replace the projection index with a persistent root database

Rejected. Root authority and topology already have owners. The required index is
rebuildable runtime projection, not durable truth.

### Add an incremental topology update algebra before measuring topology work

Rejected. The known expansion is unconditional triggering after ordinary
workspace actions. Existing accepted topology batches may retain one full
reconciliation until post-cut evidence identifies topology reconstruction itself
as hot.

### Treat terminal silence as authoritative agent lifecycle

Rejected. Terminal output and silence are evidence about terminal activity, not
proof that an agent is working, blocked, or idle. Authenticated hooks and bounded
screen heuristics require a separate lifecycle design.

### Move activity or filesystem workflow into atoms

Rejected. Atoms are current state and pure derivation. Timers, coalescence,
currentness, off-main projection, I/O, and workflow remain with feature runtime
or coordinator owners.

## Non-Goals

- No Ghostty tick, callback ownership, surface lifetime, or vendor redesign.
- No EventBus implementation, topic, replay-model, or subscriber redesign.
- No gather thread, actor-per-pane fleet, generic mailbox/admission framework,
  lease/revision protocol, consumer registry, or universal signal plane. The
  narrow fixed-key Terminal accumulator in this spec is explicitly in scope.
- No new persistence, SQLite schema, migration, repair, quarantine, revision,
  journal, lease, pager, participant, checkpoint, or diagnostic ledger.
- No persistent root index, second topology-delta algebra, or replacement
  filesystem watcher/scanner/scheduler.
- No Git operation-model expansion, network Git, worktree mutation, repository
  locking, or timeout widening.
- No terminal search, scrollbar, notification, inbox, sidebar visual, tab, or
  main-pane visual redesign.
- No Repo Explorer projection, SwiftUI invalidation, AppKit observation,
  pane/tab host, restore, or geometry implementation lane. Existing consumers
  remain regression-validation surfaces only.
- No agent lifecycle hook/plugin integration, pane relay, lifecycle IPC method,
  screen polling, detection manifest, or Ghostty text-snapshot classifier.
- No Bridge, BridgeWeb, package/content refresh, WebKit/React, or
  `paneFilesystemContext` cutover in this goal.
- No new native File View/CodeViewer runtime or file-loading redesign; current
  production reachability does not justify it.
- No startup composition, persistence, identity, or prepared-mount redesign.
- No change to strict SQLite loading, exact stored ZMX identity, or UUIDv7 rules
  for newly generated durable IDs.
- No implementation sequence, file-edit list, worker assignment, exact command
  list, or execution DAG. Those belong in the implementation plan after review.

## Revisit Triggers

Reopen a broader design only when current evidence shows one of these conditions:

- exact low-rate actions, after coalescible samples are contracted, remain the
  attributable dominant input-latency term;
- a second genuine consumer needs a removed local terminal sample;
- a second product consumer needs pane-scoped filesystem invalidation;
- topology reconstruction itself, rather than unconditional triggering, becomes
  the measured hot path;
- unmounted panes require exact live filesystem history;
- post-cut measurement still attributes dominant SwiftUI/AppKit work to a
  consumer outside the Terminal/filesystem owners, justifying a separate UI
  performance spec;
- native CodeViewer becomes a real production filesystem-change consumer and
  first-mount I/O is measured as a material interaction problem;
- remaining semantic facts produce sustained critical pressure or explicit
  replay gaps on the existing bus;
- the existing fact-only newest-buffer semantics cause an observed product or
  IPC loss after local samples are removed.

Until one of those signals exists, the narrow owners in this spec are sufficient.

## Supersession

This spec narrows the future-work sections of the cleaned performance-boundary,
[Ghostty Host Boundary and Terminal Interaction Fairness](../2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md),
and [Watched-Folder Admission and MainActor Fairness](../2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md)
for this implementation slice. It
retains their semantic classification, correctness, security, and proof lessons
but supersedes only their conflicting future-mechanism proposals for a gather
thread, generic admission types,
`RuntimeFactBus`, persistent generation index, repair/lease/pager systems, or
diagnostic ledgers.

No historical document authorizes implementing a mechanism that this spec lists
as a non-goal.
