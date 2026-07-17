# Targeted Runtime Pressure Reduction

Date: 2026-07-17
Status: accepted after one bounded spec review and remediation
Source baseline: `ghostty-performance-cleanup` at `5dea96b6`
Parent contract: [AgentStudio Performance Boundaries](../2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)

## Product Intent

AgentStudio should remain responsive while terminals produce output, users search
or interact with terminal presentation, watched folders contain hundreds of
repositories, Git refreshes run, and Bridge review panes rebuild.

The cleaned branch already has the important heavy-work owners: Ghostty owns its
host callbacks, `FilesystemActor` owns authorized filesystem ingestion,
bounded schedulers own scanning and Git reads, `FilesystemProjectionIndex` owns
off-main projection, and Bridge actors own package construction. The remaining
problem is narrower: ordinary local samples and Bridge-only invalidations still
expand into shared replay, fanout, reducer, and recurring fleet work that their
actual consumers do not need.

This design reduces that expansion using existing owners. It does not create a
new event system, callback architecture, admission framework, persistence
system, repair system, or diagnostic subsystem.

## Success Shape

The design is successful when all of the following are true:

1. Terminal presentation samples remain fully functional but produce no runtime
   envelope, runtime replay record, global EventBus post, global replay record,
   or IPC wait event.
2. Scrollbar-derived activity and inbox behavior remain equivalent through a
   narrow local evidence route.
3. Local sample pressure can no longer occupy the bounded semantic-fact channel
   or displace retained facts. This slice preserves, rather than redesigns, the
   channel's existing fact-only saturation semantics.
4. Fixed-key workspace changes no longer schedule a full repository/worktree/
   pane capture. Fleet reconciliation occurs only when the operation is actually
   fleet-wide.
5. Filesystem and Git facts refresh only matching mounted Bridge panes without
   creating derived `paneFilesystemContext` EventBus traffic or awaiting Bridge
   package construction in global ingestion.
6. MainActor performs only the existing Ghostty routing obligation, equal-write-
   suppressed local state, small immutable captures, O(affected keys) delivery,
   and compact accepted UI/canonical mutations.
7. The current filesystem authority, Git capacity, strict state, atom purity,
   Bridge currentness, and telemetry privacy boundaries remain intact.
8. Paired runtime evidence demonstrates reduced amplification and an improved or
   already-within-budget interaction tail without correctness or stability
   regression.

## Current-State Baseline

### Terminal amplification

`Ghostty.CallbackRouter.action_cb` must return Ghostty's handled Boolean
synchronously. `Ghostty.ActionRouter` copies and translates payloads, then
creates a `Task { @MainActor }` for each routed action. `TerminalRuntime` updates
observable state and currently calls `PaneRuntimeEventChannel.emit` for local
presentation samples and semantic facts alike.

Each channel emission performs sequence allocation, envelope construction,
optional local replay, local subscriber fanout, and an offer to a
`.bufferingNewest(128)` outbound stream. The detached consumer posts to the
shared EventBus. The shared bus appends every posted envelope to a 256-entry-
per-source replay and yields it to every subscriber.

Downstream lossy consolidation happens only after those costs. The MainActor
workspace coordinator also performs tab lookup before ignoring many terminal
sample cases. `persistForReplay: false` skips only the runtime's local replay; it
does not prevent global posting or global replay.

### Scrollbar semantics

Scrollbar state is both presentation and evidence:

- the terminal surface and overlays need the current viewport;
- `TerminalActivityRouter` uses total rows, quiet timing, attention, and pinned
  state to derive unseen output and agent-settled activity;
- `InboxNotificationRouter` uses pinned-to-bottom transitions to clear observed
  notifications;
- only the lower-rate derived activity outcomes are meaningful global facts.

Therefore scrollbar cannot be treated as “drop it” or “latest UI value only.”

### Filesystem and Bridge amplification

`FilesystemActor` already performs authorized canonical routing, filtering,
debounce, and bounded path chunking off-main. Git status admission and reads are
also off-main and bounded.

The remaining expansion has two forms:

1. Every workspace action currently schedules filesystem root/activity sync.
   The sync pass captures every available repository/worktree and every pane on
   MainActor even when the action did not change those relationships.
2. A worktree filesystem or Git snapshot fact is projected off-main to matching
   panes, then rebuilt as one critical `paneFilesystemContext` envelope per pane,
   posted to the same EventBus, received by the same MainActor coordinator, and
   finally delivered only if the pane is a mounted Bridge pane.

Repository-wide search found Bridge as the only production behavior consumer of
`PaneFilesystemContextEvent`. Bridge uses it as “the current package may be
dirty,” not as exact filesystem history: it checks nonempty relevant change,
pane identity, and worktree identity, then reloads current state.

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
  exposes: translated Ghostty signal through existing MainActor route
                         │
                         ▼
TerminalRuntime                                          admission owner
  owns: current local terminal state and exhaustive disposition
  exposes:
    local presentation update ───────────────► mounted terminal presentation
    local activity evidence ─────────────────► TerminalActivityEvidenceConsumer
                                                bound by AppDelegate composition
                                                to TerminalActivityRouter
    exact semantic fact ─────────────────────► PaneRuntimeEventChannel
                                                     │
                                                     ▼
                                               existing EventBus

FilesystemActor / GitWorkingDirectoryProjector       unchanged authority
  owns: registered roots, routing, filtering, bounded Git worktree facts
  coordinated by: FilesystemGitPipeline topology update
  exposes: existing authorized worktree facts through existing EventBus
                         │
                         ▼
FilesystemProjectionIndex                             off-main projection owner
  owns: rebuildable worktree/pane reverse indexes and currentness checks
  exposes: source deltas and compact Bridge invalidations
                         │
                         ▼
WorkspaceSurfaceCoordinator                           composition edge
  owns: current mounted-view lookup and O(affected Bridge panes) delivery
                         │
                         ▼
BridgePaneController                                  refresh owner
  owns: dirty coalescence, active refresh, package/review currentness
                         │
                         ▼
Bridge review actors                                  heavy-work owners
  own: provider/Git/package/delta/content construction off-main
  expose: one compact current-generation MainActor apply
```

These surfaces are separable:

- Terminal admission may change without changing filesystem or Bridge routing.
- Filesystem trigger proportionality may change without changing Bridge package
  construction.
- Direct Bridge invalidation may change without changing EventBus implementation
  or filesystem authority.
- Observability measures each surface but owns no correctness state.

## Terminal Signal Contract

### Existing Ghostty boundary remains

TR-1. Ghostty callback ownership, payload-copy rules, target resolution, and
synchronous handled-result semantics remain unchanged. This spec does not move
`ghostty_app_tick`, redesign `action_cb`, add a gather thread, or claim callbacks
are safe to execute on an unproven actor.

TR-2. The existing per-action MainActor routing hop is accepted debt for this
slice. Work after resolution is contracted. Removing that hop requires separate
source-proven thread-affinity and lifetime design if post-cut measurement still
identifies it as the dominant term.

TR-3. `TerminalRuntime` is the exhaustive product admission boundary. Every
translated signal receives one compile-time-visible disposition. Routing control
state uses a discriminated union; it is not represented by optional callbacks,
multiple booleans, string tags, or a default “emit everything” branch.

TR-3a. The local activity edge is a required Terminal-feature protocol whose
input is a typed value containing pane identity, current surface/runtime
generation, previous and current scrollbar state, and observation time. The
protocol contains no Inbox or App composition policy. `AppDelegate`, as the
composition root that already constructs `TerminalActivityRouter`, creates that
router before terminal runtime composition and injects it through
`WorkspaceSurfaceCoordinator`. Production runtime construction has no unbound
or optional control state; tests may use an explicit no-op implementation.

### Signal classification

| Signal class | Current examples | Required route | Runtime/global replay |
| --- | --- | --- | --- |
| Local presentation | scrollbar viewport; cell and initial size; size limits; mouse shape/visibility/link; key sequence/table; color/config presentation; search start/end/matches/selection | Equal-write-suppressed current local state or existing Ghostty-owned presentation behavior | Never |
| Local activity evidence | total rows, previous/current pinned state, observation/attention context, output timing | Ordered O(1) input to the existing terminal activity owner | Raw evidence never; derived outcomes only |
| Local state plus semantic transition | progress, secure input, renderer health, read-only | Current state stays local; deduped cross-feature/IPC transitions retain their existing semantic route | Only changed semantic transitions |
| Exact semantic fact | command finished, bell, desktop notification, deduped title/tab title/CWD, lifecycle/security facts | `PaneRuntimeEventChannel` and existing EventBus | Domain-specific existing replay |
| Host command/control | tab/split/navigation/close, URL/clipboard/undo/redo/prompt/config control | Preserve the existing direct or exact command/control behavior | Never converted into a lossy UI sample |
| Diagnostic-only | deferred/unhandled diagnostics without product behavior | Existing bounded diagnostic treatment | No replay unless an existing product contract explicitly requires it |

TR-4. The hard-cut local-only set is exhaustive for scrollbar, cell/initial
size, size limits, mouse shape/visibility/link, key sequence/table, color/config
presentation, and search state. These cases must not call
`PaneRuntimeEventChannel.emit`, appear in `PaneRuntime.subscribe`, consume local
or global replay, reach EventBus subscribers, or satisfy IPC event waits.

TR-5. Local does not mean discarded. The last current-generation value required
by the mounted surface or observable runtime remains available. Equal repeated
values do not wake Observation or invoke activity processing.

TR-6. Search remains a typed lifecycle, with inactive and active states distinct
at compile time. Unknown match count or selection may remain optional evidence
inside the active state; optional values must not encode whether search itself is
active. Search start, query, next/previous, match total, selected match, cancel,
close, keyboard responder behavior, overlay hit testing, and visible result text
remain unchanged.

TR-7. Local presentation and activity input are bound to the current pane/
surface runtime generation. Close, replacement, remount, or teardown invalidates
late work. A sample from generation N cannot mutate generation N+1.

### Scrollbar activity contract

TR-8. A scrollbar callback produces two independent products:

1. current viewport state for presentation; and
2. ordered typed activity evidence for the existing activity owner.

The second route is a private Terminal-feature seam, not a generic local event
bus, mailbox, actor-per-pane fleet, replay log, or persisted history.

TR-9. The safe default is direct ordered O(1) evidence delivery. If a later plan
chooses coalescence, its sufficient statistics must preserve at least:

- positive row growth that occurred before a total-row reset or decrease;
- first and latest qualifying activity time;
- pinned-to-bottom entry even when the final sample is not pinned;
- attended/observed suppression and reset;
- agent-settled promotion and revocation state;
- close, stop, replacement, and generation cancellation.

Latest viewport state alone is not sufficient evidence.

TR-10. Existing activity policy remains owned by `TerminalActivityRouter`, not
an atom. `TerminalActivityAtom` remains current state/derived read state. Inbox
clearing consumes a typed derived pinned/observed outcome or another equally
narrow local contract; Inbox no longer subscribes to raw scrollbar events.

TR-11. Unseen activity, agent-settled promotion/revocation, first-output
evidence, pinned-to-bottom clearing, read/dismiss behavior, and quiet-window
timing remain behaviorally equivalent under identical injected-clock sequences.

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

TR-15. Content-bearing semantic envelopes that remain in local or global replay
retain realistic payload-aware byte accounting plus existing count and TTL
bounds. No new stringify fallback may log retained payload content.

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

FS-3. Raw callback paths, scanner candidates, Git metadata, pane CWDs, and Bridge
requests are evidence. They cannot register a root, widen authority, or replace
the current registered-source identity.

### Proportional trigger model

FS-4. A full topology/pane snapshot is permitted only for cold in-memory index
bootstrap, an explicit rebuild, or a genuine fleet-wide topology reconciliation.
It is not a valid tail action for every workspace command.

FS-5. Ordinary changes use the narrowest existing owner edge:

- topology addition/removal/change updates only affected registrations;
- pane mount/create/close updates only that pane's membership;
- CWD/worktree reassignment updates only that pane and affected worktree
  activity;
- active pane changes update only active-worktree priority;
- unrelated layout, sidebar, inbox, presentation, and no-op actions schedule no
  filesystem root/activity reconciliation.

FS-5a. Canonical topology effects cross into runtime owners as one strict
`FilesystemTopologyUpdate`-equivalent discriminated union owned by the existing
`FilesystemGitPipeline`:

- `replace(generation, contexts)` is permitted for cold bootstrap, explicit
  rebuild, or genuine fleet replacement;
- `delta(generation, upsertedContexts, removedWorktreeIds)` is required for
  fixed-key topology change.

The update is an effect derived from accepted canonical topology; it is never a
second topology source of truth. Stale generations are rejected. The pipeline
applies one coherent generation to `GitWorkingDirectoryProjector` and
`FilesystemActor` before subsequent registration/change evidence is eligible,
and the coordinator applies the same accepted generation to
`FilesystemProjectionIndex`. An added worktree is authorized in the Git
projector before the filesystem actor emits its registration; removal stops the
filesystem source before revoking the projector context, so late evidence is
rejected without enumerating unrelated worktrees.

FS-6. Fixed changed-key work is O(changed keys plus affected memberships), not
O(all repositories + all worktrees + all panes). A genuine topology replacement
may remain fleet-wide and must be measured as such.

FS-7. `FilesystemProjectionIndex` remains an actor-owned, in-memory,
rebuildable index. It owns no atoms, persistence, repair, durable journal,
consumer registry, mounted-view truth, or canonical product topology.

FS-8. Index mutation and projection ordering remains provable. The implementation
may simplify today's pending snapshots, generations, and waiters only when one
serialized boundary or equivalent typed currentness contract prevents an older
source snapshot from rolling back a newer pane update.

FS-9. Stale, superseded, and inapplicable outcomes are explicit discriminated
states, not `nil` or overloaded empty arrays. Currentness is revalidated
immediately before registration effects, destructive absence, or downstream
delivery.

## Bridge Invalidation Contract

BR-1. Raw authorized filesystem and Git facts continue to use the existing
EventBus because they have legitimate global worktree consumers. Only the
derived pane-level reflection is removed.

BR-2. `PaneRuntimeEvent.paneFilesystemContext` and its global production path
are hard-cut. The compiler should make construction of a derived Bridge-only
runtime envelope impossible after cutover; no compatibility dual path remains.

BR-3. The projection actor returns a Bridge-specific invalidation only for an
affected Bridge pane. The contract is a strict discriminated union of reason,
such as relevant CWD-subtree change or Git-working-tree change, and carries:
pane identity, current worktree association, source/projection generation, and
the ephemeral controller-mount generation issued by `ViewRegistry`. It does not
carry raw paths, CWD, Git output, package data, or filesystem authority.

BR-4. The coordinator performs O(affected Bridge panes) current mounted-view
lookups through `ViewRegistry` and submits a non-awaiting dirty/request-refresh
operation. Global runtime ingestion never waits for provider, Git, package,
delta, content-store, WebKit, or React completion.

BR-5. `BridgePaneController` remains the single refresh lifecycle owner. It may
have at most one active refresh and one latest-convergent dirty follow-up for
this input. No second scheduler, mailbox framework, participant registry, or
atom-owned workflow is introduced.

BR-6. Bridge invalidation is current-state convergence, not exact filesystem
history. Multiple matching invalidations may coalesce, but the last accepted
demand cannot be lost. An unmounted pane receives no live invalidation, matching
current behavior; mounting/loading obtains current package state through the
existing source provider.

BR-7. `ViewRegistry` owns the ephemeral monotonic mount generation because it
already owns the current mounted view; it is not a durable identifier or second
registry. `BridgePaneController` owns its lifecycle and review generation.
Source/projection generation is owned by `FilesystemProjectionIndex`. Package
ID, review generation, pane/worktree association, mount generation, and
controller lifecycle are revalidated before content activation and again
immediately before the final MainActor state commit after all reentrant awaits.
Teardown, replacement, a newer package, or reassociation makes an older result a
no-op.

BR-8. Bridge review pipeline, change index, and content store retain expensive
work off-main. MainActor applies only a compact, internally consistent accepted
package/delta/status mutation.

## MainActor And Atom Boundaries

MA-1. MainActor continues to own AppKit, Ghostty host interaction, observable
terminal presentation state, canonical atoms, current mounted-view lookup, and
compact accepted mutations.

MA-2. MainActor must not perform filesystem traversal, Git reads, package
construction, large serialization, path canonicalization, per-event all-pane
filtering, or repeated all-fleet reconstruction.

MA-3. MainActor service for a local terminal sample is bounded decoding plus
equal-suppressed O(1) state/evidence application. Its downstream work does not
scale with EventBus subscribers, replay capacity, tabs, panes, repositories, or
worktrees.

MA-4. Atoms remain pure current state or pure derivation. They do not own signal
classification, debounce windows, timers, filesystem projection, path
canonicalization, Bridge refresh, queues, persistence, revisions, leases,
pagers, participants, or repair.

MA-5. Coordinators and runtime owners decide effects. Atom mutation methods
remain narrow and non-public where the current architecture requires it.

## Type And Static Enforcement Contract

TY-1. New and changed routing/control contracts use exhaustive enums or structs
with explicit invariants. Optional values represent genuinely absent payload
evidence, not lifecycle, acceptance, currentness, or ownership states.

TY-2. The terminal disposition switch is exhaustive over current translated
signals. Adding a new Ghostty signal without choosing local presentation, local
activity, semantic fact, host command/control, or diagnostic disposition fails
compilation or architecture lint.

TY-3. Local-only signal cases cannot call the semantic publication helper. The
smallest SwiftSyntax rule may enforce this after behavior is cut over; no new
lint framework or shell-based architecture checker is introduced.

TY-4. Removal of the global `paneFilesystemContext` event is compiler-enforced.
Production code cannot construct it, and tests prove direct Bridge behavior
rather than preserving obsolete envelope construction.

TY-5. Enforcement is proportionate to what each mechanism can prove:

- existing named SwiftSyntax rules continue to protect their current AtomLib,
  declared-input, keyed-read, comparator, import, and placement boundaries;
- narrow new SwiftSyntax rules protect only mechanically recognizable forbidden
  publication/construction edges from TY-2 through TY-4;
- targeted structural tests protect named filesystem/Git/Bridge heavy-work
  seams and atom workflow exclusions;
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

SEC-4. Registration, scan run, demand coverage, pane context, topology, and
package/mount identities remain where they are required to reject stale or ABA
results. Compact does not mean deleting currentness evidence.

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
payloads, errors, tokens, Git output, or package data from these new producers.
OTLP projection remains defense in depth and export remains fail-open. This does
not redesign or make a broad safety claim about unrelated existing local logs or
JSONL producers.

SEC-9. Full semantic envelopes retained locally remain content-sensitive.
Existing replay byte, count, and TTL bounds remain effective and payload sizing
accounts for variable strings and collections.

## Proof Expectations

### Structural proof

P-1. Every local-only terminal case produces the correct current local state or
Ghostty presentation behavior and exactly zero:

- `PaneRuntimeEventChannel` emissions;
- runtime subscription events;
- local replay writes;
- global EventBus posts and replay writes;
- global subscriber deliveries;
- IPC wait results.

P-2. A large interleaved sample stream cannot change the count or order of
command-finished, bell, desktop-notification, title/CWD, progress,
secure-input, renderer-health, lifecycle, or security facts.

P-3. The same sample-pressure cell proves zero semantic-fact drops and unchanged
runtime/IPC replay behavior. Fact-only overload is not used to claim a new
delivery guarantee in this slice.

P-4. Identical injected-clock scrollbar sequences produce identical activity,
first-output, agent-settled/revoked, pinned/observed, read, dismiss, and inbox
clearing outcomes. Reset/decrease, close/replacement, and pinned-edge sequences
are included.

P-5. Search, mouse/cursor/visibility/link, cell geometry, scrollbar presentation,
and terminal commands retain their final state and native behavior.

P-6. Ordinary unrelated and fixed-key workspace changes cause no full topology/
pane capture. Pane/CWD/activity/active-worktree mutations update only affected
entries. Cold bootstrap and genuine topology reconciliation still converge to an
independent final-state oracle.

P-7. Relevant filesystem/Git changes submit invalidation only to matching
mounted Bridge panes. Unrelated, non-Bridge, unmounted, stale-context, and stale-
mount panes receive none. No global `paneFilesystemContext` envelope is posted.

P-8. Gated and overlapping Bridge refreshes prove one active plus one convergent
follow-up, no stale post-await commit, no global-ingestion wait on build, and a
final package equal to an independent provider oracle.

P-8a. Focused deterministic regression proof preserves registered-root
authority, canonical/deepest-root containment, topology-generation/ABA
rejection, non-destructive incomplete evidence, Git logical-timeout versus
physical-drain capacity, payload-aware replay bounds, and new-producer
JSONL/OTLP content canaries.

### Runtime performance proof

P-9. Runtime proof reuses the existing isolated debug app identity, marker-
scoped Victoria stack, performance recorder, IPC surface, Bridge observability,
and PID-targeted native automation. It adds no runner, backend, heartbeat,
ledger, or correctness dependency on telemetry.

P-10. Baseline and candidate use the same debug flavor, deterministic bundle/
data-root configuration, hardware/display environment, active pane, terminal-
output pressure, search/scroll interaction, watched-folder fixture, Git mutation
pattern, Bridge mutation pattern, trace tags, and trial policy. Every trial has a
fresh marker and PID. Baseline and candidate must record distinct immutable
source revision and executable/build fingerprints; stale or cross-marker rows
cannot satisfy either cell.

P-11. Reproducible scale proof uses generated fixtures and the existing
large-worktree workload. A separate local qualification may use the configured
development roots under `/Users/shravansunder/Documents/dev/open-source` and
`/Users/shravansunder/Documents/dev/project-dev`; raw roots remain local and are
never exported as telemetry dimensions.

P-12. Metrics are aggregate and distinguish queue age from service time. The
owned measurements include:

- translated terminal signals by controlled class;
- local state/evidence applications and equal-write suppressions;
- runtime-channel and global posts by semantic class;
- EventBus subscriber deliveries, replay writes, drops, and high-water lag;
- filesystem full-reconciliation requests versus fixed-key updates;
- affected Bridge invalidations, coalesced demands, active refreshes, stale
  rejections, and final commits;
- MainActor queue age and compact-apply service;
- existing Git queue/running/timeout/final-pending evidence;
- existing Bridge package/delta/content/apply/render stage distributions.

Aggregate Victoria distributions must expose threshold-resolving buckets at or
inside 1, 2, 5, 8, and 16 ms for the targeted MainActor metrics, plus p95, p99,
and sample count. A coarse histogram that cannot classify a budget boundary is
not acceptance evidence.

### Workload and statistical contract

P-12a. The deterministic contraction cell processes at least 100,000 local-only
terminal samples across at least 10 current-generation panes and interleaves at
least 1,000 retained semantic facts. It is valid only when every local signal
class and every retained semantic class appears.

P-12b. Each runtime trial is bounded to 60 seconds and is valid only when it
contains at least 10,000 local terminal sample applications, 500 measured
callback-to-local-commit observations, active typing plus search/scroll
interaction, at least 100 repositories, 100 worktrees, 10 panes, four concurrent
Git mutation sources, and 50 relevant Bridge invalidations including at least 10
arriving while a refresh is active. Insufficient pressure or samples invalidates
the trial; it does not pass as a low-latency result.

P-12c. Baseline and candidate each run one unscored warm-up followed by five
qualifying trials. Percentiles are calculated per trial from the named metric
population, then compared using the median per-trial p95 and p99; trials are not
pooled. The 20 percent comparison applies specifically to
callback-to-current-local-commit queue-age p95.

P-13. Structural budgets are absolute:

- raw local terminal sample global posts/replay/deliveries: `0`;
- derived `paneFilesystemContext` global posts/replay/deliveries: `0`;
- semantic-fact drops during the declared mixed sample-pressure workload: `0`;
- unrelated workspace actions causing full filesystem reconciliation: `0`;
- stale Bridge commits: `0`;
- accepted/queued logical watched-folder and Git demand after bounded
  quiescence: `0`; timed-out physical drains may remain only while still counted
  against the configured physical slot bound and unable to mutate current truth.

P-14. Initial interaction/MainActor budgets are:

- compact MainActor apply p95 below 2 ms and p99 below 5 ms;
- callback-to-current-local-commit queue age p95 below 8 ms and p99 below 16 ms
  during the declared pressure workload;
- fewer than three targeted MainActor service samples at or above 20 ms in any
  qualifying trial, and none at or above 60 ms;
- zero regression in semantic counts, final state, native interaction, Git
  boundedness, or Bridge correctness.

If the baseline median queue-age p95 is already below 8 ms and p99 below 16 ms,
meeting the absolute budgets plus structural zeroes and staying within 10
percent of both baseline medians is sufficient. Otherwise the candidate must
meet the absolute budgets and improve median queue-age p95 by at least 20
percent. One best-case sample or event presence does not pass.

P-15. Stability proof includes crash-free workload execution, successful
bounded quiescence, exact final state, no growth in critical EventBus failures,
zero accepted/queued logical demand, bounded and capacity-accounted physical
Git/native drains, no late-result mutation, bounded runtime-channel/replay
high-water and final retained debt, and successful debug-app relaunch with
terminal/IPC readiness. It does not require an arbitrary multi-day soak.

P-16. Native proof validates visible typing/caret response, search start/query/
navigation/close, scroll-away and follow-bottom recovery, cursor/link behavior,
notification appearance/clearing, and refreshed Bridge content. Native proof
does not substitute for deterministic, integration, or Victoria evidence.

## Alternatives And Tradeoffs

### Keep raw samples and rely on reducer coalescing

Rejected. It preserves all work before the reducer: MainActor envelope creation,
replay, subscriber fanout, outbound buffering, queueing, and irrelevant
deliveries.

### Add a gather thread or generic mailbox/admission framework

Rejected. The current goal can be satisfied through `TerminalRuntime`, the
existing activity owner, the existing projection actor, and the existing Bridge
controller. A general framework adds lifecycle, capacity, shutdown, fairness,
and proof burden before a second use case exists.

### Redesign EventBus into topics or a fact plane

Rejected. Existing low-rate semantic facts and authorized worktree facts remain
on the current bus. Producer admission and one Bridge-only reflection are the
actual scoped problems.

### Keep `paneFilesystemContext` for possible future consumers

Rejected. No second production consumer exists. A global critical event is not a
free extension point. If a second real consumer appears, it should trigger a new
consumer contract based on its exact semantics.

### Replace the projection index with a persistent root database

Rejected. Root authority and topology already have owners. The required index is
rebuildable runtime projection, not durable truth.

### Move activity or Bridge workflow into atoms

Rejected. Atoms are current state and pure derivation. Timers, coalescence,
currentness, I/O, and workflow remain with runtime/coordinator/controller owners.

## Non-Goals

- No Ghostty tick, callback ownership, surface lifetime, or vendor redesign.
- No EventBus implementation, topic, replay-model, or subscriber redesign.
- No gather thread, actor-per-pane fleet, generic mailbox, generic admission
  framework, consumer registry, or universal signal plane.
- No new persistence, SQLite schema, migration, repair, quarantine, revision,
  journal, lease, pager, participant, checkpoint, or diagnostic ledger.
- No persistent root index or replacement filesystem watcher/scanner/scheduler.
- No Git operation-model expansion, network Git, worktree mutation, repository
  locking, or timeout widening.
- No terminal search, scrollbar, notification, inbox, or Bridge UI redesign.
- No change to strict SQLite loading, exact stored ZMX identity, or UUIDv7 rules
  for newly generated durable IDs.
- No implementation sequence, file-edit list, worker assignment, exact command
  list, or execution DAG. Those belong in the implementation plan after review.

## Revisit Triggers

Reopen a broader design only when current evidence shows one of these conditions:

- the retained per-action MainActor hop remains the attributable dominant input
  latency term after contraction;
- a second genuine consumer needs a removed local terminal sample;
- a second product consumer needs pane-scoped filesystem invalidation;
- topology reconstruction itself, rather than unconditional triggering, becomes
  the measured hot path;
- unmounted panes require exact live filesystem history;
- remaining semantic facts produce sustained critical pressure or explicit
  replay gaps on the existing bus.
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
