# Geometry-Driven Terminal Hydration Scheduling — Program Design

Date: 2026-09-03

Program Design identity: `PD-2026-09-03-TERMINAL-GEOMETRY-HYDRATION`

Requirements: [REQ-2026-09-03-TERMINAL-GEOMETRY-HYDRATION](2026-09-03-terminal-geometry-driven-hydration-requirements.md)

Specification: [SPEC-2026-09-03-TERMINAL-GEOMETRY-HYDRATION](2026-09-03-terminal-geometry-driven-hydration-specification.md)

## How the system works

One accepted workspace generation supplies immutable terminal descriptors.
Trusted container bounds and the accepted canonical active arrangement for each
tab supply bootstrap geometry. One existing `TerminalActivationScheduler` owns
the complete terminal cohort and admits at most one member at a time through the
existing MainActor admission port.

The scheduler initially orders members as visible main, visible drawer,
background main, then background drawer. The active terminal leads the visible
members within its placement class. After every visibility change, App records
the complete current visible queued terminal set for the accepted generation,
not that change's delta. The scheduler promotes that snapshot as one ordered
batch: active main, stable main siblings, active drawer, then stable drawer
siblings. A claimed admission is never cancelled for a promotion.

Before activation is released, the admission port installs the trusted frame
snapshot and reports which cohort members have frames. The scheduler moves only
those members from waiting for geometry into its queue. A missing safe frame
therefore produces no admission call, Ghostty surface, or zmx attach. It settles
startup as waiting for geometry while preserving the pane, placement,
residency, and exact stored `ZmxSessionID`. Existing layout and visibility
entrypoints retry that same pane when current geometry becomes available.
Canonical geometry changes also reevaluate every prepared-deferred terminal,
including terminals that remain minimized, collapsed, or hidden, and feed newly
safe members back into the same bounded scheduler.

Exactly one owner may create a terminal surface for one pane at any instant, and
that owner is selected by the pane's prepared-custody state in the accepted
generation rather than by a launch time window. While `ViewRegistry` custody for
the pane is `pending`, `deferredGeometry`, or `mounting`, the prepared terminal
lane is the sole creator. Custody `completed` or absent releases the pane to the
existing steady-state creation owner. The two ranges are disjoint and total, so
reveal, tab selection, drawer expansion, and geometry reevaluation cannot
produce a second surface for a pane the prepared lane still owns.

```text
accepted persisted composition
  |
  | immutable terminal descriptors, one PaneId + exact ZmxSessionID each
  v
WorkspaceCompositionPreparer                         [Core owner]
  |
  | all tab-owned terminal panes; visibility is priority, not eligibility
  v
AppDelegate.finishLaunchRestore                      [App lifecycle owner]
  |
  | trusted container bounds
  v
WorkspaceSurfaceCoordinator bootstrap geometry      [App geometry owner]
  |-- active canonical main layouts
  `-- active canonical drawer views, expanded or collapsed
  |
  | frame snapshot keyed by PaneId; absence means geometry unavailable
  v
WorkspacePreparedContentMountCoordinator             [App sequence owner]
  |
  | one complete terminal cohort + frame-eligible PaneIds
  v
TerminalActivationScheduler                          [Terminal queue owner]
  |-- missing frame -> waiting; no admission call
  |-- one in-flight admission maximum
  |-- placement-aware initial order
  |-- ordered visibility-batch promotion
  `-- later safe geometry reopens waiting members
  |
  | async MainActor admission
  v
PreparedTerminalMountAdmissionPort                   [generation/claim gate]
  `-- frame present -> one generation claim
                         |
                         v
WorkspaceSurfaceCoordinator.mountPreparedTerminalContent
  -> SurfaceManager create + attach exact pane/session identity
  -> ViewRegistry registers one mounted host
  -> ready | explicit terminal failure

reveal / tab selection / drawer expansion / layout callback
  |
  | never creates directly; reads prepared custody first
  v
custody pending | deferredGeometry | mounting
  `-- route demand to the prepared lane above (record visibility, install frame)
custody completed | absent
  `-- steady-state WorkspaceSurfaceCoordinator creation owns the pane
```

This composition adds no atom, store, bus event, coordinator, queue subsystem,
persisted state, command, IPC method, or session discovery. It changes the
eligibility and queue semantics inside the owners that already perform
composition preparation, geometry resolution, startup sequencing, scheduling,
generation admission, and surface creation.

## What is wrong in the current structure

The current system is compatibility-bound by stable pane/session identity,
strict composition validation, one accepted startup generation, trusted-frame
surface admission, and the existing MainActor Ghostty boundary.

Six current edges conflict with the Specification:

1. `WorkspaceCompositionPreparer.makePreparedContentInputs` skips every pane
   whose residency is not active, and also skips drawer children whose parent
   residency is not active. Residency therefore removes terminals before
   geometry can decide eligibility. See
   [`WorkspaceCompositionPreparation.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCompositionPreparation.swift#L596-L665).
2. `WorkspaceSurfaceCoordinator.resolveInitialFrames` reads the
   residency-filtered `WorkspaceArrangementViewDerived` drawer projection and
   requires `drawer.isExpanded`. A valid collapsed drawer therefore receives no
   bootstrap child frames even when its parent frame and canonical drawer layout
   are available. See
   [`WorkspaceSurfaceCoordinator+ViewLifecycle.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift#L638-L684)
   and
   [`WorkspaceArrangementViewDerived.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift#L30-L66).
3. `WorkspacePreparedContentMountCoordinator` creates four separate terminal
   schedulers. Promotion is confined to the scheduler that already owns the
   pane, so a queued drawer member cannot move ahead of queued main members in a
   different background phase. See
   [`WorkspacePreparedContentMountCoordinator.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspacePreparedContentMountCoordinator.swift#L48-L118).
4. `handleVisibilitySignals` launches an unacknowledged `Task` to call
   `promote`. The scheduler can finish an admission and claim another member
   before that task reaches the actor, so the current edge cannot prove that an
   observed visibility change affects the next claim. See
   [`WorkspacePreparedContentMountCoordinator.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspacePreparedContentMountCoordinator.swift#L222-L260).
5. Existing steady-state retry enumerates only the active tab's currently
   visible panes. It cannot reactivate a prepared-deferred terminal merely
   because a canonical layout change made safe geometry calculable while the
   pane remains minimized, collapsed, or hidden. See
   [`WorkspaceSurfaceCoordinator+ActiveTabRestore.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActiveTabRestore.swift#L8-L111).
6. Two owners can create a terminal surface for the same pane, and which one
   acts is decided by a global launch presentation flag rather than by that
   pane's custody. Every steady-state creation entry point defers to the
   prepared owner only inside `if viewRegistry.isInitialRestorePending`; once
   `WorkspacePreparedContentMountCoordinator.mount` calls
   `completeInitialRestore()`, the same entry points fall through to
   `createViewForContent` for every visible pane. Tab selection is the shortest
   path to that fall-through: `selectTabAndRestoreVisibleViews` calls
   `restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)`, which after
   settlement restores the complete visible set unconditionally. A pane the
   prepared lane still owns—or has already mounted—can therefore be re-created
   on a tab switch. The flag is also a global fact, so it cannot express that
   one geometry-deferred pane is still owned while its siblings are released.
   See
   [`WorkspaceSurfaceCoordinator+ActiveTabRestore.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActiveTabRestore.swift#L33-L46),
   [`WorkspaceSurfaceCoordinator+ViewHelpers.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewHelpers.swift#L125-L172),
   [`WorkspaceSurfaceCoordinator+ViewLifecycle.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift#L58-L88),
   [`WorkspacePreparedContentMountCoordinator.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspacePreparedContentMountCoordinator.swift#L171-L173),
   and
   [`PaneTabViewController.swift`](../../../Sources/AgentStudio/App/Panes/PaneTabViewController.swift#L860-L863).

The rest of the foundation remains authoritative:

- `WorkspaceCompositionPreparer` remains the only strict composition validator
  and immutable descriptor producer.
- `WorkspaceSurfaceCoordinator` remains the bridge from accepted panes and
  trusted geometry to concrete views and surfaces.
- `TerminalActivationScheduler` remains the off-main queue and concurrency
  owner.
- `PreparedTerminalMountAdmissionPort` and `ViewRegistry` remain the generation
  and exact-once claim boundary.
- `SurfaceManager` remains the only Ghostty surface owner, and zmx attach keeps
  using the exact stored opaque session identity.
- `AppPolicies.TerminalActivation.restoreMaximumConcurrentAdmissions` remains
  the capacity authority, with value one.
- Nonterminal preparation and mounting remain unchanged.

## The structural crux and selected tradeoff

There are two cruxes: who owns the queue, and who owns surface creation.

### Queue authority

The first crux is whether initial ordering and later visibility promotion share
one queue authority. They must. Placement phases are an ordering policy, while a
visibility change is a dynamic priority change. Encoding the phases as separate
schedulers makes cross-phase promotion structurally impossible.

| Alternative | Structure | Gain | Cost and failure mode | Decision |
| --- | --- | --- | --- | --- |
| Keep four schedulers | Main/drawer and visible/background remain separate owners | Smallest textual diff | A promoted member can only move within its original phase; R3 is not realizable across background placement classes | Rejected |
| Keep foreground schedulers and combine only background | Two foreground schedulers plus one background scheduler | Cross-main/drawer background promotion; explicit startup barriers | A visibility change accepted before background begins still waits behind the remaining foreground scheduler; queue authority remains split | Rejected |
| One existing terminal scheduler | One cohort; an internal queue rank expresses initial placement order and promotion | One ordering authority, one concurrency counter, cross-class promotion, simpler exact-once reasoning | The scheduler's private rank becomes richer than the public visible/hidden label | Selected |
| Add a new hydration coordinator or priority bus | New owner/event path around current scheduler | Could model arbitrary future demand | Duplicates queue ownership and generation state; expands the authorized boundary without serving a current obligation | Rejected |

The selected design spends complexity only on a private placement-aware queue
rank and explicit geometry-deferral outcome. The Terminal feature bears the
queue-policy cost; App keeps geometry and generation admission. Revisit this
choice only if terminal admissions need independent resource pools or
preemptible in-flight work. Neither is authorized or required here.

### Surface-creation authority

The second crux is what selects the owner allowed to create a terminal surface
for one pane. Today that selector is the global `isInitialRestorePending`
presentation flag, and the flag stops describing ownership at exactly the moment
this design needs ownership to continue: geometry-deferred members remain live
in the scheduler long after aggregate settlement clears the flag. A global
boolean also cannot be per-pane, so it cannot say that one deferred member is
still owned while its already-mounted siblings are released.

| Alternative | Selector | Gain | Cost and failure mode | Decision |
| --- | --- | --- | --- | --- |
| Keep the launch-window flag | Global `isInitialRestorePending` | No change | Two creators for the same pane after settlement; a tab switch re-creates already-mounted panes; deferred members are unprotected | Rejected |
| Extend the flag's lifetime | Global boolean held until no waiting members remain | Protects deferred members | Still global, so it blocks legitimate steady-state creation for every unrelated pane, including new panes and undo restores, for as long as one member waits | Rejected |
| Per-pane prepared custody | `ViewRegistry` ledger state for `(PaneId, generation)` | Total and disjoint per pane; already the exact-once claim owner; needs no new state owner | The ledger gains one non-terminal state and becomes a read on every creation entry point | Selected |
| A separate hydration-ownership registry | New per-pane owner map beside the ledger | Explicit naming | Duplicates the generation/claim ledger; two sources of truth for the same question | Rejected |

The selected design makes prepared custody the single answer to "who may create
this pane's surface", so surface-creation authority and the exact-once claim are
the same fact read at different times. `isInitialRestorePending` keeps only its
presentation meaning.

## Component ownership and dependency direction

| Component | Owns | Consumed by | Changes when |
| --- | --- | --- | --- |
| `WorkspaceCompositionPreparer` | Strict composition validity; immutable terminal descriptor membership, placement, and initial visibility facts | Prepared composition applier and startup mount composition | Persisted composition validity or descriptor classification changes |
| `WorkspaceSurfaceCoordinator` geometry functions | Safe bootstrap frames from trusted container geometry plus canonical active-arrangement layout; reevaluation after canonical geometry changes | `AppDelegate.finishLaunchRestore`, prepared mount coordinator, and layout/reveal entrypoints | Pane/drawer layout geometry changes |
| `WorkspacePreparedContentMountCoordinator` | Installing frame availability into one terminal scheduler; synchronous visibility-observation capture; joining unchanged nonterminal mount owners; placeholder publication and the request to move a settled deferred member's placeholder mode; aggregate startup settlement | `AppDelegate` and view creation/layout entrypoints | Startup sequencing or prepared-terminal signal bridging changes |
| `TerminalActivationScheduler` | One generation's long-lived terminal queue, initial ordering, ordered-batch promotion, deferred-member reopening, retry, capacity, and terminal outcomes | Prepared mount coordinator | Terminal admission scheduling policy changes |
| `PreparedTerminalMountAdmissionPort` | Trusted frames for current and deferred members, one replaceable unacknowledged visibility snapshot, generation validation, registry custody/claim settlement, and MainActor mount admission | Terminal scheduler and prepared mount coordinator | Generation, trusted-frame, observation handoff, or claim policy changes |
| `ViewRegistry` prepared ledger | One pane-to-owner claim per accepted generation, the reversible `deferredGeometry` custody state, one stable pane host slot, and the single answer to which owner may create a pane's terminal surface | Admission ports, render hosts, every terminal creation entry point | Mount custody or host lifecycle changes |
| `WorkspaceSurfaceCoordinator.mountPreparedTerminalContent` | The only terminal surface creation performed for a pane under live prepared custody, topology-independent and driven by the accepted descriptor | Prepared terminal admission port | Terminal surface construction changes |
| `WorkspaceSurfaceCoordinator` steady-state terminal creation (`mountCurrentTerminalContent`, `createViewForContentUsingCurrentGeometry`) | Terminal creation only for panes whose prepared custody is `completed` or absent: new panes, undo restores, cross-tab moves, and explicit repair of a terminally failed pane | Reveal, layout, insertion, and repair entrypoints | Steady-state creation or repair policy changes |
| `SurfaceManager` | Concrete surface identity, create, attach, detach, resize, and destroy effects | Workspace surface coordinator | Ghostty surface lifecycle changes |
| `TerminalPaneMountView` | Rendering the pane's terminal presentation: the status placeholder in its current mode, the mounted Ghostty surface, and the in-place swap between them | `ViewRegistry` host slot and the surface coordinator's placeholder writer | Terminal presentation states change |

Allowed dependency direction:

```text
Core accepted composition
  -> App lifecycle/geometry/coordination
      -> Terminal scheduler
          -> App MainActor admission port
              -> App surface coordination
                  -> Terminal SurfaceManager
```

Forbidden edges:

- The scheduler must not read mutable atoms, layout views, repository topology,
  filesystem state, or zmx inventory.
- Geometry resolution must not infer a frame from an unowned pane, invalid
  composition, or a non-selected arrangement whose placement is ambiguous.
- The admission port must not mint or rewrite pane/session identity.
- Reveal/layout entrypoints must not bypass `ViewRegistry` host lookup and
  generation/claim rules to create a second surface.
- No terminal creation entry point may branch on `isInitialRestorePending`.
  That flag describes the launch presentation window for
  `FlatPaneStripContent` and nothing else.
- Steady-state creation must not run for a pane whose prepared custody is
  `pending`, `deferredGeometry`, or `mounting`, and the prepared lane must not
  create for a pane whose custody is `completed` or absent.
- The coordinator must not grow a second queue, retry ledger, or persisted
  hydration state.
- The admission port's unacknowledged visibility value is a replaceable
  latest-state handoff, not a job queue and not an ordering owner. Only the
  scheduler assigns promotion ranks and claims members.

The package import graph and existing architecture lint enforce module
direction. Exhaustive enum handling, preconditions on duplicate descriptors,
the registry claim runtime guard, and behavior tests enforce the remaining
edges.

## Behavioral interfaces

### Prepared terminal descriptor production

`WorkspaceCompositionPreparer` emits one descriptor for every terminal that is
owned by a strictly valid tab/drawer composition. Terminal descriptor inclusion
does not consult residency. The descriptor retains the exact accepted `Pane`,
`PaneId`, `ZmxSessionID`, host placement, and initial visibility fact.

Residency remains an input to that visibility fact: a residency-backgrounded
terminal is classified as background even when its retained canonical
arrangement references it. For a drawer child to be initially visible, both
child and parent must retain active residency and the existing selected-tab,
selected-arrangement, non-minimized, expanded-drawer visibility predicates must
hold. These predicates rank terminal work; they do not remove its descriptor.

Nonterminal descriptor rules remain active-residency-only. An unowned
recoverable background pane receives no invented host placement and therefore
does not enter terminal startup scheduling. Invalid composition continues to be
rejected before any descriptor exists.

### Bootstrap geometry resolution

Given trusted non-empty terminal-container bounds, geometry resolution returns
at most one safe frame per descriptor `PaneId`:

- Main frames come from each tab's canonical active arrangement using
  `TerminalPaneGeometryResolver`.
- Drawer child frames come only from a drawer view in that same canonical active
  arrangement. The parent must have a resolved main frame and an owned drawer
  matching the descriptor placement.
- Drawer expansion is not a geometry precondition. Collapsed and expanded
  drawers use the same bootstrap content-rect calculation.
- Residency-filtered render projections are not inputs to bootstrap geometry.
- A pane represented only by a non-selected arrangement has no startup frame
  unless the accepted active arrangement also establishes an unambiguous
  placement. Absence is deferral, not a guessed fallback.
- Every result must be finite and non-empty. Invalid results are omitted.

`DrawerLayout.iconBarFrameHeight` remains the safe bootstrap approximation used
outside SwiftUI. The measured SwiftUI icon-bar height remains the display-time
authority. This means a hidden surface may begin with approximate rows/columns,
then receive the current measured frame before display; it does not justify a
second surface.

### Geometry installation and terminal scheduling

The admission port installs one immutable initial frame snapshot before
activation. Installation validates finite non-empty frames, transitions the
prepared ledger entries without frames to `deferredGeometry` custody, and returns
the exact set of pane IDs with usable frames. The mount coordinator forwards
that set to its one scheduler before releasing activation. The scheduler begins
with every member in `waitingForGeometry`; installation moves only the returned
members to `queued`.

Frame installation does not transfer geometry ownership into the scheduler.
The scheduler sees only pane-ID eligibility; the admission port retains the
actual trusted frame map and remains the final frame-to-mount boundary. The
cohort identities and the frame-eligible set must match the same generation.
Installation is single-shot and must precede `activate`.

After initial startup, the same admission port may accept additional trusted
frames only for members whose prepared-ledger custody is deferred in the same
generation. This keyed update cannot replace the frame of a queued, attaching,
ready, failed, or replaced member. The same scheduler changes each accepted
member from `waitingForGeometry` to `queued`; it starts one drain if quiescent
or lets the current drain observe the member at its next claim boundary. No
second scheduler or steady-state admission lane is created.

The scheduler accepts one immutable generation cohort and derives a private
queue rank from descriptor placement and initial visibility:

```text
initial rank, low value admitted first

0  promoted active main
1  promoted visible main sibling
2  promoted active drawer
3  promoted visible drawer sibling
4  initial visible main, active member
5  initial visible main, visible sibling
6  initial visible drawer, active child
7  initial visible drawer, visible sibling
8  background main
9  background drawer
```

Stable source ordinal breaks ties within every tier. Every visibility revision
contains the complete current visible queued set for the accepted generation,
classified into four pane-ID sets—active main, visible main siblings, active
drawer, and visible drawer siblings. It is never only the newly visible delta.
The scheduler maps every still-queued member of that snapshot to its matching
promoted tier in one actor turn. A queued member absent from the current
snapshot loses an older promoted rank and returns to its background main or
background drawer rank.
Original background ordinal breaks ties only inside that tier; it can never move a
drawer member ahead of a promoted main member or a sibling ahead of its active
member. Promotion cannot alter identity, placement, frame, generation, or
attempt count.

The current fire-and-forget promotion task is removed. The MainActor admission
port accepts each complete current-set observation synchronously as one
generation-bound, monotonically revised, replaceable snapshot. Before every
admission—including the first and every admission after a completion—the
scheduler proposes its next ranked candidate together with the visibility
revision it has applied. The admission port atomically compares that revision
with its latest recorded snapshot and either:

- returns the newer complete batch without claiming the candidate, after which
  the scheduler applies all four tiers and proposes again; or
- accepts the matching revision and acquires the candidate's `ViewRegistry`
  claim in the same MainActor operation, returning one `ClaimedTerminalAdmission`.

That MainActor operation is both visibility acknowledgement and claim
linearization. A visibility observation recorded before it must be returned and
applied before a claim can succeed. An observation recorded after it follows an
already claimed, therefore in-flight, admission. The scheduler performs no
await between receipt of a claim and marking that member attaching.
This guarantee does not rely on task launch order, `Task.yield`, or actor
fairness.

The scheduler uses the existing policy capacity of one. The capacity applies to
the complete cohort, which is stronger than the required background-only bound
and preserves current serial surface construction.

### MainActor admission

The propose/claim handshake replaces the existing single-method
`TerminalActivationAdmissionPort`. It stays on that protocol seam: this is an
actor-to-MainActor call boundary, not a new signal, so per the coordination
plane rules no bus case, command enum, or event type is added. The types live in
the Terminal feature beside the existing scheduler contracts, and App conforms
`PreparedTerminalMountAdmissionPort` to them. Spelling below is the contract;
only formatting may change during planning.

```swift
/// Total order over visibility observations within one accepted generation.
/// A counter, never a timestamp: no wall-clock value enters this contract.
package struct TerminalVisibilityRevision: Comparable, Hashable, Sendable {
    package let generation: WorkspaceContentMountGeneration
    package let ordinal: UInt64
}

/// The complete current visible queued set, classified into the four promotion
/// tiers. Never a delta. Order within each tier is the caller's stable order.
package struct TerminalVisibleQueuedTerminals: Equatable, Sendable {
    package let generation: WorkspaceContentMountGeneration
    package let activeMainPaneIDs: [PaneId]
    package let visibleMainSiblingPaneIDs: [PaneId]
    package let activeDrawerPaneIDs: [PaneId]
    package let visibleDrawerSiblingPaneIDs: [PaneId]
}

package struct TerminalVisibleQueuedSnapshot: Equatable, Sendable {
    package let revision: TerminalVisibilityRevision
    package let terminals: TerminalVisibleQueuedTerminals
}

package struct TerminalAdmissionProposal: Equatable, Sendable {
    package let generation: WorkspaceContentMountGeneration
    package let paneID: PaneId
    package let attempt: Int
    package let appliedVisibilityRevision: TerminalVisibilityRevision
}

/// One-shot authority to perform exactly one mount effect. Only the admission
/// port can mint one; `claimID` is a `UUIDv7` the port records and consumes.
package struct ClaimedTerminalAdmission: Equatable, Sendable {
    package let claimID: UUID
    package let admission: TerminalActivationAdmission
    package let acknowledgedVisibilityRevision: TerminalVisibilityRevision
}

package enum TerminalAdmissionClaimRejection: Equatable, Sendable {
    case staleGeneration
    case paneNotInCohort
    case trustedFrameUnavailable
    case custodyUnavailableForClaim
    case retryClaimMismatch
}

package enum TerminalAdmissionClaimOutcome: Equatable, Sendable {
    case claimed(ClaimedTerminalAdmission)
    case visibilityChanged(TerminalVisibleQueuedSnapshot)
    case rejected(TerminalAdmissionClaimRejection)
}

package enum ClaimedTerminalActivationRejection: Equatable, Sendable {
    case claimAlreadyConsumed
    case claimNotIssued
}

package enum ClaimedTerminalActivationOutcome: Equatable, Sendable {
    case attempted(TerminalActivationAttemptResult)
    case rejected(ClaimedTerminalActivationRejection)
}

@MainActor
package protocol TerminalActivationAdmissionPort: AnyObject, Sendable {
    /// Replaces the latest-state visibility snapshot. Contains no `await`.
    /// Returns the existing revision unchanged when `terminals` equals the
    /// currently recorded set, so repeated equal observations mint no revision.
    @discardableResult
    func recordCurrentVisibleQueuedTerminals(
        _ terminals: TerminalVisibleQueuedTerminals
    ) -> TerminalVisibilityRevision

    /// Compare-and-claim. Contains no `await`, so the revision comparison and
    /// the `ViewRegistry` custody transition occur in one MainActor turn.
    func claimPreparedTerminal(
        _ proposal: TerminalAdmissionProposal
    ) -> TerminalAdmissionClaimOutcome

    /// Performs the one mount effect authorized by `claim` and consumes it.
    func activateClaimedTerminal(
        _ claim: ClaimedTerminalAdmission
    ) async -> ClaimedTerminalActivationOutcome
}
```

Guarantees a caller may rely on:

- **G1 ordering.** `TerminalVisibilityRevision` is totally ordered within one
  generation and strictly increases on every recorded change. Revisions from
  different generations are never compared; a proposal carrying another
  generation's revision is `.rejected(.staleGeneration)`.
- **G2 acknowledgement.** Any snapshot recorded before a `claimPreparedTerminal`
  call is returned to the scheduler by that call before any claim can succeed.
  A claim therefore proves the scheduler has applied every visibility
  observation that preceded it. This does not depend on task launch order,
  `Task.yield`, or actor fairness.
- **G3 single-turn atomicity.** `claimPreparedTerminal` contains no suspension
  point. The revision comparison, the trusted-frame contract check, and the
  `pending -> mounting` custody transition either all happen or none do.
- **G4 idempotence.** `claimID` is consumed on first use. Replaying a claim
  returns `.rejected(.claimAlreadyConsumed)` and performs no mount effect. A
  value not minted by this port returns `.rejected(.claimNotIssued)`. No caller
  can construct an accepted claim, so the mount effect is unreachable without
  one.
- **G5 retry.** Attempt two reuses the custody already held in `mounting` rather
  than re-claiming, and receives the same installed trusted frame. A proposal
  whose attempt does not match the port's recorded attempt for that pane is
  `.rejected(.retryClaimMismatch)`.
- **G6 duplicate and late claims.** A proposal carrying an older revision
  returns `.visibilityChanged` and never claims. A proposal for a pane whose
  custody is not `pending` returns `.rejected(.custodyUnavailableForClaim)`, so
  a second creator cannot appear even if a stale scheduler survives.
- **G7 cancellation.** Nothing cancels an issued claim. A promotion never
  revokes one, and a cancelled scheduler task does not leave custody in
  `mounting`: the port settles the ledger from inside the mount effect, on both
  the success and failure exits.
- **G8 fail-closed frames.** A pane declared frame-eligible whose installed
  frame is missing returns `.rejected(.trustedFrameUnavailable)` before any
  surface effect. This is an internal contract violation, not a terminal
  failure presentation.

The scheduler receives the claim before the mount effect begins. It marks the
matching member `hydrationInProgress`, then invokes `activateClaimedTerminal`,
with no `await` between those two steps. The admission port retains the trusted
frame and accepted descriptor; the claim carries only identity, attempt, and the
acknowledged revision. Replacement rejection remains generation-bound and cannot
publish into a successor generation.

The installation step classifies frame unavailability before a scheduler claim
or surface side effect. It settles prepared custody in the distinct
`deferredGeometry` state rather than masquerading as `surfaceCreationFailed`.
Admission of a pane that was declared frame-eligible but has no frame is an
internal contract violation and fails closed before surface creation. It is
reported as `.rejected(.trustedFrameUnavailable)` at the claim boundary, so no
mount effect can begin. A waiting member has no
queue rank. When later safe geometry queues it, the App records a new complete
current visible queued set, which promotes it if it is still visible.
`waitingForGeometry` is a terminal outcome for that startup settlement, but not
a terminal state for the pane's later eligibility.

`ViewRegistry` is the sole generation-bound custody and claim ledger.
`PreparedContentMountLedgerState` gains one non-terminal case,
`deferredGeometry(owner:)`, alongside the existing `pending`, `mounting`, and
`completed`. Frame installation performs the no-claim transition
`pending(owner: .terminal) -> deferredGeometry(owner: .terminal)`, and accepting
a later trusted frame performs the reverse no-claim transition
`deferredGeometry(owner: .terminal) -> pending(owner: .terminal)` before the
scheduler queues the member. The atomic candidate claim then uses the ordinary
`pending -> mounting(owner: .terminal)` transition.

Deferral is a distinct case rather than a `completed` disposition because
`completed` must keep exactly one meaning: the prepared lane has released the
pane, and steady-state creation may own it. A reversible state hidden inside
`completed` would make the custody-based creation-owner partition ambiguous, and
it would bypass the existing `settlePreparedContentMount` precondition that a
settlement follows a matching `mounting` claim. The scheduler owns queue state
and outcomes; it does not own or duplicate ledger custody. The ledger owns no
queue rank or scheduling order.

### Waiting-for-geometry placeholder presentation

`TerminalPaneMountView` is the presentation owner. It is the pane's mounted
content in the `ViewRegistry` host slot, and it already renders both terminal
presentations: it holds `TerminalStatusPlaceholderView` as a full-bounds subview
and mounts the Ghostty surface wrapper in the same view. No second host, window,
or overlay owner is introduced. See
[`TerminalPaneMountView.swift`](../../../Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift#L485-L517)
and
[`TerminalStatusPlaceholderView.swift`](../../../Sources/AgentStudio/Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift#L9-L99).

The observed state is `TerminalStatusPlaceholderMode`, which becomes
`{ preparing, waitingForGeometry, failedToStart }`. `SurfaceStartupOverlayState`
gains the matching `waitingForGeometry` case, and unlike `preparing` and
`restoring` it renders explanatory text with no `ProgressView`, so a settled
deferred pane is never presented under an indefinite spinner. It adds no button,
command, or focusable control, so the existing accessibility contract is
unchanged; `failedToStart` keeps sole ownership of the retry and dismiss
affordances.

`WorkspaceSurfaceCoordinator.registerTerminalPlaceholderIfNeeded(for:mode:)`
remains the only writer of that mode, and
`WorkspacePreparedContentMountCoordinator` is the only caller that requests the
settlement transition. For every scheduler member that settles the initial drain
as `waitingForGeometry`, the coordinator asks the surface coordinator to
reconfigure the existing placeholder from `.preparing` to `.waitingForGeometry`.
`TerminalStatusPlaceholderView.configure(mode:)` mutates the existing view in
place, so the transition neither unregisters the host nor rebuilds the pane
slot. When later geometry reopens the member, the same writer returns the mode
to `.preparing` for the bounded interval from successful requeue through the
claimed mount attempt.

`shouldRetryCreationWhenBoundsChange` stays `mode == .preparing` and is therefore
`false` for `waitingForGeometry`. This is load-bearing: a deferred pane must be
re-entered by the prepared lane through canonical geometry reevaluation, not by
a steady-state bounds-change retry. A `waitingForGeometry` placeholder also does
not make `activeTabHasMissingVisibleView` report a missing view, so a tab switch
neither creates a surface nor re-enters restore for a deferred pane.

The placeholder-to-surface swap happens without a flash because it completes
inside one MainActor turn on a stable slot.
`createTopologyIndependentTerminalView` builds the replacement
`TerminalPaneMountView`, calls `displaySurface`, which calls `clearPlaceholder()`
and mounts the surface wrapper, and only then calls `registerHostedView`. The
`ViewRegistry.PaneViewSlot` has pane lifetime rather than host lifetime, so
SwiftUI observers are not torn down across the swap, and no intermediate empty
host is drawn. See
[`WorkspaceSurfaceCoordinator+ViewLifecycle.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift#L258-L295)
and
[`TerminalPaneMountView.swift`](../../../Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift#L340-L360).

Proof seam: a placeholder render test asserts that `waitingForGeometry` shows no
progress indicator and exposes no retry or dismiss control, and that
`shouldRetryCreationWhenBoundsChange` is false;
`WorkspacePreparedContentMountCoordinatorTests` asserts the
`.preparing -> .waitingForGeometry` transition at settlement and the return to
`.preparing` on requeue, with the same host instance identity across both; the
real reveal journey confirms the deferred pane becomes usable with no visible
blank frame at the swap.

### Visibility observation and acknowledgement

After each canonical tab, arrangement, drawer, or visibility mutation, the
App-owned visibility path derives all terminals that are currently visible and
still have same-generation queued custody. It classifies that complete current
set as active main, stable main siblings, active drawer, and stable drawer
siblings, then synchronously records one snapshot through
`WorkspacePreparedContentMountCoordinator` at the existing prepared-content
visibility boundary. Recording returns the snapshot revision; it does not wait
for surface work.

The scheduler's candidate-claim handshake rejects a proposal carrying an older
revision and returns the newer snapshot without a registry claim. The scheduler
applies all still-queued members of that snapshot to the four promoted tiers,
then proposes the newly highest-ranked candidate. A successful claim
acknowledges the revision; it does not mean hydration completed. Repeated
identical complete current sets are equality-suppressed. A newer complete set
replaces an older unacknowledged snapshot because current visibility is latest-
state. Still-visible queued panes therefore survive coalescing, newly visible
queued panes join, and no-longer-visible queued panes disappear and revert to
their background main or background drawer rank. Already claimed work is never
demoted or cancelled.

### Canonical geometry-change reevaluation

Every existing App-owned action that can change the canonical active layout,
minimized set, drawer view/layout, drawer expansion, or trusted container bounds
ends with one call to the surface coordinator's prepared-terminal geometry
reevaluation. The surface coordinator asks `ViewRegistry` for the current
generation's deferred terminal pane IDs, resolves frames only for those IDs
from the new canonical state, and passes the non-empty results to
`WorkspacePreparedContentMountCoordinator`.

The mount coordinator first installs those frames through the admission port,
which accepts only same-generation deferred custody and returns it to pending,
then awaits the scheduler's acknowledgement that every accepted ID moved from
waiting to queued. It next records the complete current visible queued set so a
newly queued visible member receives the correct tier. The call
does not filter by presentation: minimized, collapsed, inactive-tab, hidden,
and residency-backgrounded panes are included whenever canonical geometry is
now safe. If placement remains ambiguous, no frame is passed and the member
stays waiting. This is an action-tail or existing container-layout callback
edge—there is no timer, poll, event-bus case, new observer, or new queue.

### Reveal and current-geometry synchronization

Tab selection, arrangement selection, drawer expansion, and layout callbacks
continue through the existing `restoreViewsForActiveTabIfNeeded` /
`restoreVisiblePaneIfNeeded` paths.

- A queued visible set is recorded synchronously and promoted as one ordered
  batch before the scheduler's next claim.
- A waiting pane with newly available canonical geometry reenters the same
  scheduler even when it remains hidden; a visible waiting pane also receives
  its promoted tier when queued.
- A ready pane resolves from its existing registry host and surface; reveal
  reattaches or resizes it.
- The display-time geometry sync applies the current measured layout frame
  before user presentation.

No reveal path creates a surface when `ViewRegistry` already contains ready
mounted content for the pane.

### Terminal surface-creation ownership after settlement

One owner creates terminal surfaces for one pane at any instant, and prepared
custody selects it. The prepared terminal lane —
`TerminalActivationScheduler` -> `PreparedTerminalMountAdmissionPort` ->
`WorkspaceSurfaceCoordinator.mountPreparedTerminalContent` — is that owner for
the entire life of the accepted generation, not only for the launch window. Its
ownership begins when the cohort is installed and ends per pane when custody
becomes `completed`.

`isInitialRestorePending` is not deleted, but it stops being an ownership
selector. It is reduced to a read-only presentation fact describing the launch
window, consumed only by `FlatPaneStripContent.resolve` to explain a
temporarily missing host. No terminal creation entry point may branch on it.
The four creation-path reads of that flag today —
[`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:72`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift#L72),
[`+ViewHelpers.swift:127`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewHelpers.swift#L127),
[`+ViewHelpers.swift:165`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewHelpers.swift#L165),
and
[`+ActiveTabRestore.swift:34`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActiveTabRestore.swift#L34)
— become unconditional per-pane custody reads.

The idempotence key is `(PaneId, WorkspaceContentMountGeneration)`. It is
resolved through one ledger read, and the mapping from custody to owner is
total and disjoint:

| Custody for `(PaneId, generation)` | Sole creation owner | What a reveal or layout entrypoint does instead |
| --- | --- | --- |
| `pending(owner: .terminal)` | Prepared lane | Records the complete current visible queued set; the scheduler promotes and claims |
| `deferredGeometry(owner: .terminal)` | Prepared lane | Resolves current canonical geometry and installs it; the scheduler requeues the same member |
| `mounting(owner: .terminal)` | Prepared lane, already claimed | Nothing; the in-flight admission finishes and is never cancelled |
| `completed(disposition: .mounted)` | No creator; a live surface exists | Resolves the existing `ViewRegistry` host and reattaches or resizes it |
| `completed(disposition: .failed)` | Steady-state creation | Explicit repair or the placeholder retry control creates, under the unchanged failure contract |
| `completed(disposition: .cancelledReplaced)` | The successor generation's prepared lane | Nothing in this generation |
| No entry, or a stale generation | Steady-state creation | Creates normally: new panes, undo restores, cross-tab moves |
| `pending`/`mounting`/`completed(owner: .nonterminal)` | Nonterminal owner, unchanged | Nothing terminal-specific |

The state transition that makes a second creation impossible is
`pending -> mounting`. It is single-assignment: `ViewRegistry` performs it once
per pane per generation and rejects any repeat with `.alreadyClaimed`. To make
that the only reachable path, the surface-creation primitive requires a witness
it cannot manufacture. `createTopologyIndependentTerminalView` and
`mountCurrentTerminalContent` take a `TerminalSurfaceCreationAuthority` value
with exactly two producers: `.prepared(ClaimedTerminalAdmission)`, which only
the admission port can mint after a successful `pending -> mounting`, and
`.released(PaneId)`, which `ViewRegistry` returns only when the pane's custody
is `completed` or absent. There is no third producer and no default value, so a
creation path that skips the custody question does not compile. This adds a
value type at an existing seam; it adds no atom, store, bus, queue, or
coordinator.

```swift
/// Proof that exactly one owner may create this pane's terminal surface now.
/// Only `PreparedTerminalMountAdmissionPort` and `ViewRegistry` can produce a
/// value, so no creation site can assert authority it was not granted.
@MainActor
enum TerminalSurfaceCreationAuthority {
    case prepared(ClaimedTerminalAdmission)
    case released(PaneId)
}

@MainActor
extension ViewRegistry {
    /// Returns `.released` only for `completed` or absent custody. Returns nil
    /// while the prepared lane owns the pane, which refuses steady-state
    /// creation without inspecting the launch presentation window.
    func terminalSurfaceCreationAuthority(
        for paneID: PaneId,
        generation: WorkspaceContentMountGeneration
    ) -> TerminalSurfaceCreationAuthority?
}
```

Ownership remains per pane after aggregate startup settlement because a
geometry-deferred member stays live in the long-lived scheduler. A reveal, a
tab switch, and a geometry-reevaluation tail therefore cannot race two
surface-creation owners for the same `PaneId`, and a pane already
`completed(.mounted)` is reused rather than re-created on the tab-switch hot
path.

Proof seams that fail if a second creation path exists:

- `PreparedContentMountStartupBoundaryTests` already asserts that
  `completeInitialRestore()` has exactly one caller. It gains two assertions:
  no file under `Sources/AgentStudio` reads `isInitialRestorePending` inside a
  terminal creation path, and every production call of
  `createTopologyIndependentTerminalView` and `mountCurrentTerminalContent`
  passes a `TerminalSurfaceCreationAuthority`.
- A behavior test settles a cohort, then drives `selectTabAndRestoreVisibleViews`
  for a tab whose terminals are `completed(.mounted)` and asserts zero
  `SurfaceManager.createSurface` calls and unchanged surface IDs.
- A behavior test settles a cohort containing one `deferredGeometry` member,
  drives a reveal of that pane, and asserts the steady-state path created
  nothing while the prepared lane produced exactly one surface after geometry
  installation.
- The runtime claim guard rejects a duplicate `pending -> mounting`, so a
  regression surfaces as a rejected claim rather than a second surface.

## Terminal hydration state machine

The scheduler owns hydration queue/outcome state while the prepared ledger owns
generation-bound custody and claims for one accepted generation. Both are
runtime-only. Pane/session identity,
residency, tab/drawer membership, and arrangements remain canonical persisted
state and never transition as a side effect of hydration.

```text
                                      newer accepted generation
                                    +----------------------------+
                                    |                            v
accepted descriptor --------> waiting for geometry -----------> replaced
                                  |          ^
              installed safe frame          | no frame yet; remain waiting
                                  v          |
                              +---+--------+-+
                              |   queued   |--------------------> replaced
                              | rank + try |
                              +-----+------+
                                    | claim; capacity available
                                    v
                           hydration in progress
                              /       |        \
                     success/   retryable     \terminal failure
                            v       failure     v
                          ready ------+------> failed
                            |         |
                            | reveal  `-> queued (bounded existing retry)
                            v
                     reattach + resize
                     same live surface

waiting after startup settlement
  -> later valid layout or visibility supplies current safe frame
  -> existing App layout path requeues the same pane in this scheduler

invalid/unowned composition has no transition into this machine
```

| State | Owner | Entry guard | Side effects | Legal exits |
| --- | --- | --- | --- | --- |
| Waiting for safe geometry | Scheduler outcome; `ViewRegistry` separately owns the matching `deferredGeometry` custody | Accepted tab-owned terminal; trusted geometry has not been installed or the installed snapshot lacks its key | No claim, surface, attach, identity write, or canonical mutation; the prepared lane retains creation ownership of the pane | Queued in the same scheduler when initial or later canonical geometry supplies a frame; replaced |
| Queued | `TerminalActivationScheduler` | Installed snapshot declares a safe frame, or later retry has current geometry | None | In progress; promoted rank update; replaced |
| Hydration in progress | Scheduler plus `ViewRegistry` claim | Generation current; no prior claim; capacity available | MainActor may create and attach one surface | Ready; one retry; failed; replaced outcome suppresses stale publication |
| Ready | `ViewRegistry` host plus `SurfaceManager` | Surface creation and exact-pane attachment succeeded | Register mounted host; mark runtime running | Reattach/resize; explicit close/repair outside this design |
| Failed | Existing terminal failure presentation | Existing retry is exhausted or not requested | Failure placeholder; no canonical deletion or identity rewrite | Existing explicit retry/repair; explicit close |
| Replaced | Scheduler generation outcome | New accepted generation supersedes queued/in-progress work | Obsolete completion cannot attach/publish into successor | Terminal for obsolete generation |

Placeholder presentation is a projection of these states rendered by
`TerminalPaneMountView`, not another hydration owner: waiting after initial
settlement projects neutral `.waitingForGeometry`; queued or in-progress work
may project `.preparing`; terminal failure projects `.failedToStart`; ready
clears the placeholder in the same MainActor turn that mounts the surface.

The scheduler lifecycle is `awaitingGeometry -> draining -> quiescent`.
Quiescent means there is no queued or attaching member; it may still retain
waiting members. The initial `mount()` caller receives an immutable settlement
snapshot when the first drain becomes quiescent, so launch can complete.
Accepting later safe frames changes quiescent back to draining on the same
scheduler. Only no waiting members or generation replacement makes the
scheduler fully terminal. Concurrent drain-start requests join the one existing
drain and never create a second worker.

Illegal transitions are rejected: a second claim is refused by `ViewRegistry`,
an admission from another generation is refused by the admission port, a
promotion cannot change claimed or terminal work, and a nil/invalid frame can
never enter surface creation. A visible waiting member may retain promotion
tier but cannot be claimed until safe geometry is installed.

## Current-to-proposed call-path deltas

The following view pairs every changed runtime edge with its current source
anchor. `UNCHANGED` marks preservation-critical edges.

```text
1. Composition membership

CURRENT
SQLite snapshot
  -> WorkspaceCompositionPreparer.prepare
  -> makePreparedContentInputs
  -> [residency.isActive guard] ------------------------ REMOVED for terminals
  -> [active parent-residency guard] ------------------- REMOVED for terminal children
  -> TerminalActivationInput

PROPOSED
SQLite snapshot
  -> WorkspaceCompositionPreparer.prepare                UNCHANGED strict validation
  -> makePreparedContentInputs
  -> [terminal + valid tab/placement] ------------------- CHANGED eligibility
  -> TerminalActivationInput                             UNCHANGED identity payload

Nonterminal active-residency filters                     UNCHANGED

Evidence: WorkspaceCompositionPreparation.swift:596-665
Result/error: invalid composition still returns the existing rejection;
unowned recoverable panes receive no fabricated descriptor.
```

```text
2. Bootstrap geometry

CURRENT
AppDelegate.finishLaunchRestore
  -> WorkspaceSurfaceCoordinator.resolveInitialFramesByTabId
  -> tab.activeArrangement main layout                   UNCHANGED
  -> WorkspaceArrangementViewDerived.drawerView          REMOVED from bootstrap path
       [requires active residency]
  -> drawer.isExpanded guard                              REMOVED from geometry eligibility
  -> frame map
  -> PreparedTerminalMountAdmissionPort.installTrustedInitialFrames

PROPOSED
AppDelegate.finishLaunchRestore                          UNCHANGED entry/bounds authority
  -> WorkspaceSurfaceCoordinator.resolveInitialFramesByTabId
  -> tab.activeArrangement main layout                   UNCHANGED
  -> tab.activeArrangement.drawerViews[ownedDrawerID]    CHANGED canonical source
  -> resolvedDrawerContentRect                           CHANGED applies collapsed/expanded
  -> TerminalPaneGeometryResolver                        UNCHANGED geometry engine
  -> finite non-empty frame map
  -> PreparedTerminalMountAdmissionPort.installTrustedInitialFrames
                                                        CHANGED returns eligible PaneIds
  -> WorkspacePreparedContentMountCoordinator.installTerminalGeometryAvailability
                                                        ADDED existing-owner handoff
  -> TerminalActivationScheduler waiting -> queued       ADDED state transition

Evidence: AppDelegate+LaunchRestore.swift:16-68;
WorkspaceSurfaceCoordinator+ViewLifecycle.swift:607-725;
WorkspaceArrangementViewDerived.swift:30-66.
Result/error: absent or invalid frame remains absent and is classified as
waiting; it is never replaced by a guessed default.
```

```text
3. Scheduling and promotion

CURRENT
WorkspacePreparedContentMountCoordinator.init
  -> four phase cohorts
  -> four TerminalActivationScheduler actors             REMOVED
  -> sequential phase settlement
visibility signal
  -> terminalSchedulersByPaneID[pane]
  -> promotion within one phase only

PROPOSED
WorkspacePreparedContentMountCoordinator.init
  -> one complete terminal cohort                        CHANGED
  -> one TerminalActivationScheduler actor               CHANGED
  -> install frame-eligible PaneIds before activate       ADDED
  -> private placement-aware initial rank                ADDED
visibility signal
  -> synchronous complete CURRENT visible queued snapshot
                                                        CHANGED acknowledged handoff
scheduler before every claim
  -> propose candidate + applied visibility revision
  -> admission port returns newer batch OR atomically claims
                                                        ADDED claim-boundary revalidation
  -> apply active-main/main-sibling/active-drawer/drawer-sibling tiers
                                                        ADDED batch ordering
  -> promoted batch follows accepted in-flight claim
nonterminal foreground owners/phases                     UNCHANGED behavior

Evidence: WorkspacePreparedContentMountCoordinator.swift:48-180,212-260;
TerminalActivationScheduler.swift:47-217.
Result/error: each independent admission settles; one failure does not stop the
worker from claiming the next eligible member.
```

```text
4. Admission, deferral, and reveal

CURRENT
TerminalActivationScheduler
  -> PreparedTerminalMountAdmissionPort.activate
  -> ViewRegistry claim
  -> mountPreparedTerminalContent(initialFrame: nil)
  -> surfaceCreationFailed("trusted_initial_frame_unavailable")
  -> failed prepared ledger
  -> later visible repair only when deferred intent is captured

PROPOSED
PreparedTerminalMountAdmissionPort.installTrustedInitialFrames
  -> ViewRegistry pending -> deferredGeometry              ADDED no-claim transition
  -> later safe frame: deferredGeometry -> pending         ADDED reverse transition
  -> eligible PaneIds -> mount coordinator -> scheduler   ADDED waiting-to-queued edge
  -> placeholder .preparing -> .waitingForGeometry         ADDED settlement projection
TerminalActivationScheduler
  -> claimPreparedTerminal(proposal + revision)           CHANGED admission boundary
  -> newer visibility snapshot OR ClaimedTerminalAdmission ADDED handshake result
  -> ViewRegistry pending -> mounting                     CHANGED permitted claim origin
  -> activateClaimedTerminal(claim)                       ADDED claimed-effect boundary
  -> trusted frame contract check                        CHANGED fail-closed guard
  -> mountPreparedTerminalContent                        UNCHANGED effect owner
  -> SurfaceManager create/attach                        UNCHANGED identity effect
visibility/layout signal
  -> per-pane same-generation prepared-custody gate       CHANGED ownership gate
  -> synchronously record complete current queued set     CHANGED race-free handoff
canonical geometry-change tail
  -> enumerate same-generation deferred terminal IDs     ADDED existing-owner path
  -> resolve safe frames without visibility filtering    ADDED hidden recovery
  -> same port accepts deferred frames
  -> same scheduler queues newly safe IDs                 ADDED bounded retry
  -> ready host reattach/resize                           UNCHANGED reuse path

Evidence: PreparedTerminalMountAdmissionPort.swift:55-128;
WorkspaceSurfaceCoordinator+TerminalContentMounting.swift:88-120;
WorkspaceSurfaceCoordinator+ActiveTabRestore.swift:8-111;
WorkspaceSurfaceCoordinator+ViewHelpers.swift:140-203;
WorkspaceSurfaceCoordinator+ActionExecution.swift:272-396.
Result/error: geometry absence is contained as waiting; real terminal startup
failures retain their current retry/failure presentation. Pending,
deferredGeometry, or mounting custody refuses steady-state terminal creation,
so reveal and prepared requeue cannot create two surfaces.
```

The `ViewRegistry` prepared ledger's transitions for the terminal lane are
exhaustive. Every legal edge appears here; anything absent is rejected at
runtime.

| From | To | Trigger | Owner performing it | Invariant it preserves |
| --- | --- | --- | --- | --- |
| (none) | `pending(.terminal)` | `installPreparedContentMountCohort` for one accepted generation | `ViewRegistry`, called by `WorkspacePreparedContentMountCoordinator.init` | One pane maps to one owner lane; a duplicate pane or a repeated install is a precondition failure |
| `pending(.terminal)` | `deferredGeometry(.terminal)` | Frame installation finds no finite non-empty frame for the pane | `PreparedTerminalMountAdmissionPort.installTrustedInitialFrames` | No claim, surface, attach, or identity write occurs; the pane stays canonical and stays owned by the prepared lane |
| `deferredGeometry(.terminal)` | `pending(.terminal)` | A canonical geometry change yields a safe frame for that pane in the same generation | `PreparedTerminalMountAdmissionPort` keyed frame acceptance | The member becomes claimable again without a second scheduler, a second cohort, or a new claim budget; the reverse edge is legal only within the installed generation |
| `pending(.terminal)` | `mounting(.terminal)` | `claimPreparedTerminal` on a matching visibility revision | `ViewRegistry.claimPreparedContentMount` | Single-assignment: this is the only edge that authorizes a mount effect, and a repeat is rejected `.alreadyClaimed` |
| `mounting(.terminal)` | `mounting(.terminal)` | Scheduler attempt two after a retryable failure | `PreparedTerminalMountAdmissionPort` attempt check | Retry reuses the held custody and the same trusted frame; it never re-claims and never mints a second claim |
| `mounting(.terminal)` | `completed(.terminal, .mounted)` | `activateClaimedTerminal` returns `ready(surfaceID:)` | `PreparedTerminalMountAdmissionPort.settleIfTerminal` | One live surface exists; the prepared lane releases the pane and reveal reuses the registered host |
| `mounting(.terminal)` | `completed(.terminal, .failed)` | Terminal failure, or a retryable failure with the attempt budget exhausted | `PreparedTerminalMountAdmissionPort.settleIfTerminal` | Canonical state is untouched; the existing explicit repair contract becomes the only remaining creator |
| `pending(.terminal)`, `deferredGeometry(.terminal)`, or `mounting(.terminal)` | `completed(.terminal, .cancelledReplaced)` | A newer accepted generation supersedes this one | `ViewRegistry` generation replacement | Obsolete work cannot publish or attach into the successor generation |

Illegal for the terminal lane and rejected rather than tolerated:
`deferredGeometry -> mounting` without the intervening `pending` edge, so no
member can be claimed while its frame is unknown; any transition out of
`completed`, so a released pane never returns to the prepared lane inside the
same generation; `pending -> mounting` for a pane whose recorded owner is
`.nonterminal`, rejected `.wrongOwner`; and any transition carrying a
generation other than the installed one, rejected `.staleGeneration`.

```text
5. Terminal surface-creation ownership

CURRENT
PaneTabViewController.selectTabAndRestoreVisibleViews
  -> restoreViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)
  -> if viewRegistry.isInitialRestorePending
       -> preparedContentVisibilitySignalHandler filters handled panes
     else
       -> paneIDsToRestore = every visible pane ------------ REMOVED fall-through
  -> createViewForContent -> mountCurrentTerminalContent
restoreVisiblePaneIfNeeded / ensureTerminalPaneView / createViewForContent
  -> same isInitialRestorePending branch ------------------- REMOVED selector

PROPOSED
PaneTabViewController.selectTabAndRestoreVisibleViews    UNCHANGED entrypoint
  -> restoreViewsForActiveTabIfNeeded                     UNCHANGED entrypoint
  -> ViewRegistry.terminalSurfaceCreationAuthority(paneID, generation)
                                                          ADDED per-pane custody read
  -> pending | deferredGeometry | mounting
       -> record complete current visible queued set       CHANGED routes to prepared lane
       -> no steady-state creation                         CHANGED ownership
  -> completed(.mounted)
       -> reuse existing ViewRegistry host, resize          UNCHANGED reuse path
  -> completed(.failed) | completed(.cancelledReplaced) | absent
       -> .released authority -> mountCurrentTerminalContent
                                                          UNCHANGED steady-state owner
isInitialRestorePending
  -> read only by FlatPaneStripContent.resolve             CHANGED presentation-only

Evidence: PaneTabViewController.swift:860-863;
WorkspaceSurfaceCoordinator+ActiveTabRestore.swift:33-46,88-107;
WorkspaceSurfaceCoordinator+ViewHelpers.swift:125-172;
WorkspaceSurfaceCoordinator+ViewLifecycle.swift:58-88,200-215;
WorkspaceSurfaceCoordinator+TerminalContentMounting.swift:30-83;
ViewRegistry.swift:82-96,121-163;
FlatPaneStripContent.swift:15-27.
Result/error: a tab switch over already-mounted panes performs no surface
creation; a pane under live prepared custody is routed to the prepared lane
instead of being created twice; panes outside the accepted generation keep the
current steady-state behavior unchanged.
```

## Normal startup and reveal sequence

```text
AppDelegate              Geometry owner        Mount coordinator       Scheduler       Admission/ViewRegistry       Surface owner
    |                          |                       |                    |                    |                       |
    | trusted bounds          |                       |                    |                    |                       |
    |------------------------>|                       |                    |                    |                       |
    |                         | canonical active      |                    |                    |                       |
    |                         | layouts + drawers     |                    |                    |                       |
    |                         |---- frame snapshot ------------------------------->| install/classify       |                       |
    |                         |                       |<--- eligible PaneIds --------|                    |                       |
    |                         |                       |---- configure waiting/queued ->|                    |                       |
    | publish placeholders -------------------------->|                    |                    |                       |
    | wait first interactive frame                    |                    |                    |                       |
    | release activation ---------------------------->|------------------->|                    |                       |
    |                         |                       |                    | propose + revision  |                       |
    |                         |                       |                    |------------------->| compare latest       |
    |                         |                       |                    |<-- newer batch -----| no claim; retry       |
    |                         |                       |                    | apply full batch     |                       |
    |                         |                       |                    | propose + revision  |                       |
    |                         |                       |                    |------------------->| claim atomically      |
    |                         |                       |                    |<-- claim -----------| generation + frame    |
    |                         |                       |                    | mark in progress     |                       |
    |                         |                       |                    |------------------->| activate claim        |
    |                         |                       |                    |                    |---------------------->|
    |                         |                       |                    |                    | surfaceID / failure   |
    |                         |                       |                    |<-------------------|<----------------------|
    |                         |                       |                    | yield; claim next   |                       |
    |                         |                       |<--- settlement ----|                    |                       |
    |<------------------------ aggregate settlement --|                    |                    |                       |

while one admission is in flight:
tab selection reveals active main + main siblings
    -> record revision N containing the complete current visible queued main set
before acknowledgement, drawer opens and reveals active drawer + drawer siblings
    -> recompute from current state, replacing N with revision N+1
    -> N+1 still contains the visible queued main set and adds the drawer set
    -> in-flight admission finishes
    -> candidate-claim handshake returns and applies N+1 before claim
    -> promoted batch claims active main, stable main siblings,
       active drawer, stable drawer siblings

after panes settled waiting for geometry:
canonical layout/minimized/drawer/container geometry changes
    -> surface coordinator enumerates every same-generation deferred terminal
    -> resolves only safe current canonical frames, regardless of visibility
    -> admission port accepts frames and scheduler acknowledges requeue
    -> same bounded worker hydrates exact PaneId + ZmxSessionID
    -> if visible, promoted tier controls its claim; otherwise background rank applies

after aggregate settlement, user switches to a tab of ready terminals:
selectTabAndRestoreVisibleViews -> restoreViewsForActiveTabIfNeeded
    -> per-pane custody read returns completed(.mounted) for each terminal
    -> no creation authority is produced, so no surface is created
    -> existing ViewRegistry host resolves; display-time geometry sync resizes
    -> same surface IDs; no re-render and no second zmx attach

same tab switch, one member still deferred for geometry:
    -> that pane's custody read returns deferredGeometry
    -> reveal records the complete current visible queued set and installs any
       newly safe frame; it creates nothing itself
    -> prepared lane requeues, claims, and mounts the one surface
```

## Failure, recovery, and partial success

| Condition | Detection owner | Containment | Recovery owner and trigger | Observable result |
| --- | --- | --- | --- | --- |
| Trusted container bounds absent | Existing launch readiness gate | Activation does not start | `WindowRestoreBridge` or existing timeout recovery supplies non-empty bounds | Startup remains gated; no surface receives fake dimensions |
| Pane frame absent from valid bootstrap snapshot | Admission-port installation plus scheduler | Member remains waiting; no claim, surface creation, or zmx attach; canonical state unchanged | Existing reveal/layout path retries when current geometry exists | Waiting/deferred outcome, not terminal startup failure |
| Non-finite, empty, or negative frame | Geometry owner | Omit frame exactly as unavailable | Same as missing frame | No invalid Ghostty surface creation |
| zmx attach command unavailable or surface creation fails | Existing terminal mount owner | Per-pane failure placeholder; unrelated queue members continue | Existing bounded scheduler retry or explicit user repair, according to current failure class | Explicit failed terminal; no identity rewrite |
| Surface created but attachment fails | Existing terminal mount owner | Destroy unattached surface and roll back prepared runtime | Existing one retry; then explicit failure | No leaked second surface |
| Duplicate or wrong-owner claim | `ViewRegistry` | Reject before mount | None for duplicate attempt; current generation remains authoritative | One host/surface maximum per pane |
| Visibility arrives during queued background work | Admission-port revision plus atomic revision-check-and-registry-claim | Current claimed admission is not cancelled; no later claim can bypass an already recorded observation | Complete four-tier promoted batch receives the next claims | User-demanded main/drawer set overtakes queued background work in required tier order |
| Visibility arrives after geometry deferral | Visibility snapshot plus canonical geometry-change reevaluation | Deferred custody prevents parallel creation; no unsafe frame is guessed | Same admission port accepts a newly safe frame and same scheduler reopens the member | Visible member receives promoted tier; hidden member hydrates at background rank |
| Canonical geometry changes while deferred panes remain hidden | Surface-coordinator action tail or existing container-layout callback | Reevaluation is limited to current-generation deferred IDs; ready/failed/in-flight members are untouched | Same mount coordinator installs accepted frames and resumes same scheduler | Newly safe minimized/collapsed/hidden terminals hydrate without reveal |
| Reveal overlaps a post-settlement prepared requeue | Per-pane custody read at every terminal creation entry | The creation primitive requires a `TerminalSurfaceCreationAuthority`, which pending, deferredGeometry, and mounting panes cannot produce | Existing prepared scheduler remains the sole creator until custody becomes `completed` | One claim and one surface ID for the exact pane |
| Tab switch reaches an already-mounted cohort pane | Per-pane custody read returning `completed(.mounted)` | No creation is attempted; the existing `ViewRegistry` host is resolved | Reveal path reattaches and resizes the live surface | No re-render, no second surface, unchanged surface ID |
| A second creation path is reintroduced by later work | `ViewRegistry` single-assignment `pending -> mounting` claim plus the authority-witness type | The duplicate claim is rejected before any surface effect | Architecture boundary test fails at build time; the runtime guard fails closed | Rejected claim and a failing proof gate, never a second surface |
| New generation replaces queued work | Scheduler and admission generation checks | Queued/claimed obsolete members cannot publish into successor | Successor generation owns its own cohort and claims | Replaced outcome; no stale host attachment |
| One member fails | Scheduler | Failure is per pane | Worker yields and admits next member | Partial success; independent panes become ready |

Retry does not reconstruct descriptors or identities. Scheduler attempt two
uses the same immutable descriptor and its accepted trusted frame. Geometry
deferral is not consumed by that surface-failure retry budget; later safe
geometry reopens the original member in the same scheduler and generation.

## Concurrency and consistency

### Ordering and capacity

`TerminalActivationScheduler` is the single serializable authority for queue
state. Its actor isolation orders claims, completions, retries, promotions, and
replacement. `restoreMaximumConcurrentAdmissions == 1` means only one call may
cross into the MainActor admission port at once. The worker yields after every
completed attempt so hidden work cannot monopolize execution.

### Promotion linearization and batch order

A complete current visibility snapshot takes effect when the MainActor
admission port records its revision. The scheduler may claim only through the admission port's atomic
revision-check-and-registry-claim operation. A stale proposal receives the
newer batch and no claim. A matching proposal creates the claim and in-flight
boundary in that same operation. The scheduler atomically ranks the complete
still-queued batch before proposing again. Applying the snapshot also resets an
older promoted rank for every still-queued member absent from the new current
set. Tier precedes original ordinal, so
background source order cannot reverse active-main, main-sibling,
active-drawer, drawer-sibling order. Within a tier, original ordinal is stable.
Attaching, ready, failed, replaced, waiting, or unknown members are absent from
the queued snapshot. When safe geometry later queues a waiting member, the
subsequent complete-current-set revision determines whether it is promoted.

There is no unstructured promotion task and no fairness assumption. The
`ClaimedTerminalAdmission` returned by the existing claim owner supplies the
ordering proof directly.

### Exact-once consistency

The immutable cohort rejects duplicate pane IDs. Single-shot geometry
installation binds one eligibility set and frame map to that cohort generation.
`ViewRegistry` admits one owner claim for one generation. The admission port
checks generation, frame contract, and claim before the mount effect.
`SurfaceManager` attaches the returned surface to the exact descriptor pane.
Registry registration replaces a placeholder host; it does not create a second
canonical pane or session. Reveal first checks the registry host and reuses
ready content.

Deferred custody is not a second scheduler outcome store. The scheduler owns
whether a member is waiting, queued, attaching, or has a terminal outcome;
`ViewRegistry` owns whether the current generation may perform the mount side
effect. The direct pending-to-deferred and deferred-to-pending ledger
transitions perform no claim. Only the later same-generation
pending-to-mounting transition authorizes surface creation.

Every creation entry point consults that custody before creating a terminal.
This is a read of the existing generation ledger, not a second lock, queue, or
state owner. It closes the post-settlement interval in which the
launch-presentation flag is false but prepared custody remains live.

The idempotence key is `(PaneId, WorkspaceContentMountGeneration)`. Custody for
that key is total, so it always names exactly one creation owner, and
`pending -> mounting` is single-assignment within it. Because the creation
primitive accepts only a `TerminalSurfaceCreationAuthority` — mintable solely by
a successful claim or by a custody read that returned `completed` or absent — a
second creation for one key has no reachable path. Two attempts to hydrate one
pane in one generation therefore resolve to one claim, one mount effect, and one
surface ID, whichever entrypoint arrives first.

### MainActor boundary

Queue selection, ordering, promotion, yield, and retry remain on the scheduler
actor. MainActor receives only one already-selected admission at a time and
performs the required view/surface mutation. Geometry is calculated once per
trusted snapshot before bulk activation and again only through existing
canonical layout-action tails and trusted container-layout callbacks. Each
reevaluation is keyed to prepared-deferred pane IDs; no per-frame polling or new
observer is introduced.

### Backpressure

The cohort is finite and contains at most one member per accepted terminal
pane. There is no producer stream and no unbounded pending queue. Multiple
visibility signals collapse into one latest complete-current-set snapshot and
then into each member's current rank; they do not append jobs or lose a still-
visible pane from an earlier coalesced change. Repeated equal current sets are
suppressed. Repeated geometry
reevaluation can transition a deferred ledger entry only once, and the same
scheduler capacity counter governs initial and later admissions.

## Compatibility and cutover

This is a hard internal cutover within one app version:

- Persisted schema, pane identity, `ZmxSessionID`, residency values, tab/drawer
  membership, arrangement data, commands, IPC, and zmx protocol do not change.
- Existing databases require no migration and can roll back because no new
  state is written.
- The former four-scheduler terminal path is removed rather than kept as a
  compatibility branch.
- The `isInitialRestorePending` ownership branch is removed from every terminal
  creation entry point in the same change that introduces the custody read.
  There is no interim in which both selectors are consulted.
- `PreparedContentMountLedgerState` gains `deferredGeometry(owner:)` and every
  existing switch over it is updated exhaustively; the enum stays App-internal,
  so no cross-module contract changes.
- `TerminalStatusPlaceholderMode` gains `waitingForGeometry` and every switch
  over it is updated exhaustively.
- Nonterminal startup keeps its current visibility and phase behavior, and its
  ledger custody semantics are unchanged.
- Strict invalid-composition rejection precedes both old and new hydration.

Rollback is code-only: restoring the former scheduler/geometry behavior reads
the same persisted state. A partially hydrated process is not a persisted
cutover phase; a restart reconstructs runtime state from the unchanged accepted
composition.

## Cross-cutting realization

| Obligation | Structural realization | Degradation/failure behavior | Proof seam |
| --- | --- | --- | --- |
| Reliability | Canonical composition remains immutable input; geometry deferral never mutates it; exact generation claim gates effects | One pane may wait/fail while independent panes continue | Descriptor/outcome/registry state by `PaneId`; fresh restart and reveal |
| Performance | One scheduler, one in-flight admission, yield after completion, finite member map, no new polling/observer | Large cohorts take longer but cannot burst surface creation | Scheduler maximum-in-flight diagnostics plus marker-correlated admission trace and exact-process CPU |
| Responsiveness | Initial queue ranks visible main before drawer/background; each revision is the complete current visible queued set; atomic revision-check-and-registry-claim promotes its four-tier batch | In-flight admission finishes rather than being cancelled; coalescing retains every still-visible queued pane | Ordered revisions, stale-proposal response, and successful claim trace |
| Observability | Existing restore/performance recorder receives pane-correlated classification and lifecycle outcomes with controlled enum values | Missing exporter remains fail-open; local proof still records outcomes | Eligible/waiting/queued/promoted/in-progress/ready/failed/replaced markers without path/content payloads |
| Privacy and trust | No new data collection; exact opaque typed zmx identity crosses the existing subprocess boundary | Invalid/missing identity follows existing strict failure | Typed descriptor and attach-boundary inspection; no raw content/path export |
| Accessibility | No new interactive control or command; `TerminalPaneMountView` renders one added `TerminalStatusPlaceholderMode` case whose overlay carries text and no `ProgressView`, and retry/dismiss stay owned by `.failedToStart` | A geometry-deferred pane is neither presented as failed nor left under an indefinite progress spinner | Placeholder mode-render assertions, coordinator settlement transition, and the reveal journey |
| Platform compatibility | Existing macOS layout, AppKit/SwiftUI host, Ghostty, and zmx boundaries remain | Bootstrap uses documented app-owned approximation and converges to measured layout | Bootstrap-frame versus final visible-frame observation |

No new trust boundary exists. The zmx subprocess and Unix-socket boundary is
unchanged, so a separate trust-boundary diagram would add no decision clarity.

## How each requirement is realized and verified

| Requirement | Immediate observable contract | Structural owner and mechanism | Observable proof seam | Enforcement class |
| --- | --- | --- | --- | --- |
| R1 | Every valid tab-owned terminal with safe geometry hydrates without reveal | Preparer includes terminals independent of residency; canonical active-arrangement geometry supplies frame map; geometry-change tails reevaluate every prepared-deferred ID without visibility filtering | Descriptor classification and ready/waiting outcomes across active, backgrounded, minimized, collapsed-drawer, hidden, and non-selected-arrangement cases | Exhaustive classification tests plus real debug restart |
| R2 | Visible main, visible drawer, background main, background drawer | Scheduler private initial rank; stable ordinal within class | Admission order from one mixed cohort | Automated scheduler/coordinator integration and runtime trace |
| R3 | The complete current visible queued set is the next ordered batch after accepted in-flight work | MainActor records a complete four-tier current-set revision; latest-state replacement retains still-visible panes and removes no-longer-visible panes; atomic revision-check-and-registry-claim rejects stale proposals | Two visibility changes before acknowledgement prove the second snapshot retains the first change's still-visible main panes, adds drawer panes, and admits active main, stable main siblings, active drawer, stable drawer siblings despite opposing background ordinals | Claim-boundary coalescing/interleaving test and runtime revision/stale-proposal/claim trace |
| R4 | At most one non-visible admission in progress | Existing policy value one applied to the single complete cohort | Maximum simultaneous admissions and per-pane start/finish intervals | Runtime guard, scheduler diagnostics, real-size performance proof |
| R5 | Missing geometry creates no surface, preserves canonical state, exits active-progress presentation at settlement, and retries later | `deferredGeometry` no-claim ledger custody, `TerminalPaneMountView` rendering the added `.waitingForGeometry` placeholder mode under the coordinator-requested transition, and App-owned canonical geometry-change reevaluation reopening newly safe members in the same scheduler, whether visible or hidden | No admission/create/attach while unsafe; `.preparing` -> `.waitingForGeometry` at settlement with the same host instance and no progress indicator; hidden/minimized/collapsed same-pane ready result after later safe geometry | Scheduler/admission unit evidence, placeholder mode-render and coordinator transition integration, real reveal journey |
| R6 | One pane/session identity has at most one admission and surface per generation | Immutable descriptor, one scheduler member, single-assignment `pending -> mounting` registry claim, custody-selected creation ownership enforced by the `TerminalSurfaceCreationAuthority` witness, SurfaceManager attach, ready-host reuse | Claim decisions, tab-switch over mounted panes creating nothing, reveal-plus-requeue interleaving, one surface ID, attach counts, exact stored zmx identity | Architecture boundary test on creation call sites and `isInitialRestorePending` reads, runtime claim guard, integration and real zmx-backed restart |
| R7 | Bootstrap geometry converges before display | Canonical bootstrap resolver plus existing visible geometry sync/resize | Initial frame and final displayed frame on the same surface ID | Geometry unit proof and debug collapsed-drawer reveal |

The production proof path must keep `WorkspaceSurfaceCoordinator`,
`PreparedTerminalMountAdmissionPort`, `ViewRegistry`, `SurfaceManager`, and real
zmx attachment intact. Queue and geometry edge cases may replace the terminal
mount port for deterministic state proof, but mocks alone cannot establish
surface identity, reveal reuse, or CPU behavior.
