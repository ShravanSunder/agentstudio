# Startup Runtime Reconciliation and zmx Session Safety

> **OBSOLETE — DO NOT IMPLEMENT.** The startup discovery, anchor hydration,
> adoption, fallback, and persistence design below is superseded by
> [Session Lifecycle Architecture](../../architecture/session_lifecycle.md).
> Existing nonempty `ZmxSessionID` values restore verbatim; new values use
> UUIDv7; restore performs no identity inference, repair, list, or write.

Date: 2026-06-12
Historical status: superseded accepted design

## Problem

Agent Studio now has the right terminal identity spine:

- `PaneId` is the primary app identity.
- `TerminalState.zmxSessionId` is a persisted spawn-time anchor.
- zmx session names encode the pane UUID tail, so legacy sessions can be
  adopted or protected by kind-aware pane-id matching.

The startup hazard this spec addressed was destructive cleanup. Before the
current slice, startup still ran zmx orphan cleanup during boot and could call
`zmx kill` before pane restore was fully established. That was the wrong safety
boundary for terminal sessions: terminal processes and scrollback are user data
until proven otherwise.

Startup should repair ownership. It must not destroy sessions.

## Pre-Change Evidence

The branch was based on the post-observability `origin/main` merge and already
contained the zmx anchor/source-removal work when this design was written.
Relevant evidence at design time:

- `TerminalState.zmxSessionId` is a frozen spawn-time identity. Attach, restore,
  and cleanup are expected to read it rather than re-derive from live facets:
  `Sources/AgentStudio/Core/Models/PaneContent.swift`.
- Migration `008_add_zmx_session_id` persists that anchor on terminal content:
  `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift`.
- `TerminalRestoreRuntime.zmxSessionId(for:store:)` already prefers a valid
  stored anchor and only falls back to legacy derivation when the anchor is
  missing: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift`.
- zmx session ids encode the last 16 hex chars of the pane UUID:
  `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift`.
- Boot awaited `cleanupOrphanZmxSessions()` inside
  `bootEstablishRuntimeBus`, before `ViewRegistry`, `PaneCoordinator`, and
  restored pane slots are fully established:
  `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`.
- `runOrphanZmxCleanup` could still call `backend.destroySessionById`, which
  reaches `zmx kill`: `Sources/AgentStudio/App/Boot/AppDelegate.swift`.
- `ZmxOrphanCleanupPlanner` already separates useful read-only classification
  from destructive execution: it computes protected session ids and anchors to
  persist, and its `destroyableOrphanSessionIds` result is consumed later by
  `AppDelegate`.

## Core Decision

Boot must be non-destructive.

Boot may:

- discover runtime inventory,
- match live zmx sessions to panes by stored anchor or pane UUID tail,
- hydrate missing `zmxSessionId` anchors,
- persist those hydrated anchors,
- log unmatched live-session facts for later maintenance.

Boot must not:

- call any API that can reach `zmx kill`,
- delete, quarantine, or rename zmx socket state,
- infer that an unprotected live session is disposable,
- block app readiness on destructive cleanup.

Destructive cleanup becomes a later background janitor with stricter gates.

## Mental Model

```text
BOOT RECONCILIATION

  restore SQLite
        |
        v
  load pane anchors + pane UUIDs
        |
        v
  all persistent zmx panes have valid anchors?
        |
        +-- yes --> skip live inventory
        |
        +-- no ---> read zmx inventory
                    |
                    v
  classify by ownership
        |
        +-- stored anchor valid -------------------> protect
        |
        +-- missing anchor + unique pane-tail match -> adopt + persist
        |
        +-- ambiguous / missing / partial ----------> leave alone
        |
        v
  continue app startup

  No transition in this machine destroys a session.
```

```text
BACKGROUND JANITOR

  app healthy
        |
        v
  acquire janitor exclusivity
        |
        v
  query full datastore ownership
        |
        v
  request complete runtime inventory
        |
        v
  classify candidates
        |
        v
  wait TTL / second observation
        |
        v
  refresh complete inventory
        |
        v
  kill only confirmed unowned candidates
```

## Ownership Facts

Stored session anchor:

- Strongest restore source of truth.
- If a valid `zmxSessionId` belongs to a pane, restore and attach use it
  verbatim.
- It is spawn-time state, not live topology state.
- It is not, by itself, cleanup authority. A stale-but-valid stored anchor can
  still require recovery if trusted inventory shows a different same-pane live
  session. That recovery path must preserve sessions first and resolve the
  conflict explicitly; it must not destroy during boot.

Pane UUIDv7 tail:

- Strong adoption and protection evidence.
- It can prove a live zmx session is associated with a known pane id.
- It must protect sessions from destruction.
- It does not, by itself, authorize destruction of anything else.

Repo/worktree stable keys:

- Useful provenance and legacy minting input.
- Not a live ownership source.
- Not a cleanup authority, because panes can roam and worktrees can disappear.

zmx inventory:

- Required for adoption and cleanup.
- Inventory quality matters:
  - complete inventory can support janitor decisions,
  - partial inventory can support protection/adoption of observed matches,
  - unavailable inventory can support no destructive action.

## Proposed Boundaries

### Boot Reconciliation Owner

Location: `App/Boot/`

Potential name: `StartupRuntimeReconciliationCoordinator`

Owns:

- launch-time orchestration,
- calling inventory providers,
- asking planners for classification,
- persisting safe anchor hydration,
- publishing startup diagnostics.

Does not own:

- zmx protocol details,
- attach command generation,
- pane graph mutation rules beyond calling existing store APIs,
- destructive cleanup.

### Pure Planning Owner

Location: `App/Coordination/`

Current seed: `ZmxOrphanCleanupPlanner`

Target shape:

- keep the existing pure planner style,
- split read-only reconciliation output from destructive janitor output,
- model inventory quality explicitly,
- keep kind-aware pane matching.

Useful output vocabulary:

- `anchorsToHydrate`
- `protectedRuntimeIds`
- `candidateOrphans`
- `unresolvedAnchors`
- `cleanupDisposition`

### Runtime Inventory Provider

Location: `Core/RuntimeEventSystem/Contracts/` or adjacent runtime contract
folder, with zmx implementation under `Core/RuntimeEventSystem/Runtime/`.

Potential types:

```swift
enum RuntimeInventorySnapshot<Record> {
    case complete(records: [Record], observedAt: Date)
    case partial(records: [Record], gaps: [RuntimeInventoryGap], observedAt: Date)
    case unavailable(reason: RuntimeInventoryUnavailableReason)
}
```

Provider responsibilities:

- snapshot live backend instances,
- expose opaque backend instance ids,
- report complete, partial, or unavailable inventory.

Provider non-responsibilities:

- no pane lookup,
- no UI policy,
- no attach command generation,
- no app command routing.

### zmx Provider

`ZmxBackend` remains backend plumbing.

Today the provider can wrap CLI `zmx list` / `zmx kill`. Later, a
`ZmxSessionCatalogClient` can replace CLI list with direct zmx IPC without
changing app-level reconciliation policy.

The app-level seam is runtime inventory, not zmx IPC. Future worktree/doc IPC
should only plug into this pattern if those systems have durable anchors plus
runtime inventory. They should not be generalized merely because they also use
IPC.

## Background Janitor Policy

The janitor is a maintenance job, not boot.

It may destroy a session only when all required gates pass:

1. Full datastore ownership was read, not only the active workspace atom.
   The global `ZMX_DIR` can contain sessions for more than one workspace or app
   instance.
2. Runtime ownership is explicit. Shared `ZMX_DIR` membership and `as-*` prefix
   are not ownership proof. Instance-scoped directories, an owner token, or an
   equivalent machine-readable owner fact is required before destructive cleanup
   becomes acceptable.
3. Inventory is complete. Partial or unavailable inventory can never authorize
   destruction.
4. The candidate id is parseable and belongs to Agent Studio's zmx namespace.
5. The candidate does not match any persisted pane UUID tail for the relevant
   kind.
6. The candidate is observed as orphaned across at least two snapshots separated
   by a TTL.
7. Any unresolvable persisted zmx pane anchor poisons the sweep.
8. The job has instance exclusivity for the `ZMX_DIR`, such as a janitor lock.
9. Kill failures are logged and do not create tight retry loops.

Tombstone cleanup can be a stricter, more intentional lane later:

- permanent close or undo-expiry records a kill-intent tombstone,
- the janitor executes tombstones after process/app-instance checks,
- inference-by-absence remains the slow, conservative fallback.

## Branch / PR Implication

This branch should not be PR'd with boot-time zmx killing present.

Reason: the branch's purpose is persistence/session safety. Shipping any known
startup path that can call `zmx kill` from active workspace state while `ZMX_DIR`
is global would leave a data-loss class inside the safety PR.

The minimal PR-blocking change is not the full janitor. It is:

- keep boot anchor hydration/adoption,
- remove boot destruction,
- update tests that expected startup to destroy unrelated sessions,
- update architecture docs that promised TTL cleanup but did not match the
  implemented safety boundary.

The background janitor can be a follow-up PR once no boot path can destroy
sessions.

## Error Traps

Partial zmx inventory:

- Safe to protect and possibly hydrate exact unique matches.
- Unsafe to kill.

Unavailable zmx inventory:

- Continue boot from persisted anchors.
- No hydration based on live inventory.
- No cleanup.

Ambiguous same-pane matches:

- Do not persist an anchor.
- Protect all same-kind pane-tail matches from cleanup.

Invalid stored anchor:

- Ignore for restore if it fails pane validation.
- Do not destroy it during boot.
- Later janitor may consider it only under complete inventory and TTL gates.

Flush failure after hydration:

- Boot continues.
- No cleanup depends on it.
- Emit persistence recovery/diagnostic event.

Multiple app instances or channels:

- Janitor must not assume a process is the only owner of `ZMX_DIR`.
- Debug, beta, and stable builds need explicit app-data isolation or janitor
  exclusivity before destructive action.

Shared directory collision:

- A live session from another workspace or app instance in the same `ZMX_DIR`
  is not an orphan just because it is absent from the active workspace atom.
- Destructive cleanup must use full datastore ownership and instance ownership,
  not the current in-memory active workspace alone.

Stale valid stored anchor:

- A structurally valid stored anchor remains the restore default, but if trusted
  inventory shows a different same-pane live session, the app has a recovery
  conflict rather than a cleanup candidate.
- The safe behavior is preserve both until a recovery rule is explicit.

SQLite unavailable or recovering:

- No destructive cleanup.
- Startup should favor restoring the app over housekeeping.

## Validation Strategy

Unit tests:

- boot reconciliation hydrates a unique legacy same-pane match,
- boot reconciliation never calls destroy,
- partial inventory protects observed same-pane sessions but yields no kill plan,
- unavailable inventory yields no kill plan,
- ambiguous same-pane matches are protected but not persisted,
- invalid stored anchors do not authorize destruction.

Integration tests:

- real zmx session with scrollback is adopted and preserved after restart,
- unrelated live zmx session remains alive after boot reconciliation,
- persisted anchor remains stable after pane cwd/worktree roaming,
- two app instances or two workspaces sharing a `ZMX_DIR` cannot reap each
  other's sessions during boot,
- stale valid stored anchor plus different same-pane live session is preserved
  as a recovery conflict, not cleaned up,
- `SWIFT_TEST_INCLUDE_ZMX_E2E=1 mise run test` covers the real zmx path.

Runtime observability:

- startup trace includes inventory outcome, hydration count, protected count,
  unresolved count, and unmatched live-session count,
- janitor trace includes each destructive gate and the reason for skip/kill,
- collector-backed Victoria stack is preferred for manual runtime proof.

Repo gates:

- `mise run test`
- `mise run lint`
- explicit zmx E2E gate when touching zmx cleanup or restore semantics.

## Non-Goals

- Do not build the full background janitor in the no-boot-kill slice.
- Do not expose zmx IPC as Agent Studio's external app API.
- Do not make a universal IPC framework.
- Do not merge startup inventory with `RuntimeRegistry`; registry is for
  in-process pane runtimes after creation.
- Do not use repo/worktree facets as restore identity.
- Do not kill malformed or unparseable zmx session ids.

## Open Decisions

1. Should boot still perform live zmx discovery for anchor hydration, or should
   all live discovery move after the app is visually ready?

   Recommended default: keep live discovery in boot for now, but make it
   non-destructive and bounded. This preserves legacy anchor hydration while
   removing data-loss risk.

2. Should the first janitor be observe-only for one release?

   Recommended default: yes, if the janitor lands soon after no-boot-kill.
   Emit candidates and gate decisions first, then enable killing after real
   Victoria trace evidence.

3. Should full datastore ownership include all workspaces immediately?

   Recommended default: yes for any destructive janitor. Active workspace atoms
   are insufficient for a global `ZMX_DIR`.

## Recommended Next Workflow

The corresponding implementation plan is
`docs/plans/2026-06-12-startup-runtime-reconciliation.md`.
