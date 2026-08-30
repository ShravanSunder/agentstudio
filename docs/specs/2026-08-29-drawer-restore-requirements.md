# Foreground and Background Drawer Restore — Requirements

Date: 2026-08-29  
Artifact: `Requirements` (Requirements-only; the separate Specification is deferred)

## Identity and authority

Requirements identity: `REQ-2026-08-29-DRAWER-RESTORE`

The authorized product decision in the 2026-08-29 request is to deliver one
bounded PR that restores foreground content in a deliberate order and keeps a
backgrounded pane's drawer structure recoverable across save and restart. The
request is the authority for the desired user outcomes, ordering, and one-PR
scope. It does not authorize a new drawer model, a persistence migration, or a
change to session identity semantics.

Current applicable sources:

- [Session Lifecycle Architecture](../architecture/runtime/session_lifecycle.md):
  current restore contract and stable pane/session identities.
- [Workspace composition preparation](../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCompositionPreparation.swift):
  current foreground/visible/hidden classification used to prepare startup
  content.
- [Workspace mutation coordination](../../Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceMutationCoordinator.swift):
  current backgrounding/reactivation behavior.
- [Terminal restore scheduling](../../Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift):
  current visibility-tier ordering evidence.
- [Background drawer tests](../../Tests/AgentStudioTests/Core/Atoms/WorkspaceMutationCoordinatorTests.swift)
  and [SQLite bridge tests](../../Tests/AgentStudioTests/App/State/WorkspaceSQLiteStoreBridgeRepairTests.swift):
  current behavioral evidence.

The implementation sources above are observational evidence about today’s
behavior, not authority for the desired behavior. The older
[Drawer Restore And Reconnect Invariants](2026-06-29-drawer-restore-and-reconnect-invariants.md)
document is explicitly superseded and is retained only as historical evidence.

## Consumers and affected outcomes

U1 — Returning end user. A user who launches or relaunches Agent Studio expects
the selected tab to become usable quickly: its main panes appear first, then
the drawer panes that belong to that foreground tab. Workspaces with many
other tabs or hidden panes must not make the selected tab wait for all of them.

U2 — Returning end user with a backgrounded pane. A user who backgrounds a pane,
saves, restarts, and later foregrounds it expects the pane and its drawer to be
the same workspace object they left, rather than a parent with missing or
reordered children.

U3 — User selecting a restored drawer child. The selected/active child and its
arrangement state must remain predictable after foregrounding, subject to the
stored composition being valid.

## Current observable problem

P1 — Startup ordering does not express the requested two-step foreground order.
The current scheduler sorts by visibility tier and then active status. The
prepared composition classifies both main panes and drawer children as
`activeVisible`/`visible` when they are visible in the active tab, so the
selected tab’s main-pane-first behavior is not a separately protected product
outcome.

P2 — Backgrounding removes arrangement references for the parent and its drawer
children. The current mutation path retains drawer-view payloads in process
memory. The existing tests demonstrate that a save followed by a fresh store
load preserves backgrounded pane rows/residency but does not retain those
drawer-view references in the loaded tab until reactivation occurs in the same
process.

P3 — If a valid pane is deferred because its runtime host is not ready, the
user-facing model must not be treated as deleted. The current startup and
surface code already distinguishes deferred/missing hosts from model validity;
the requested change must retain that distinction.

## Desired outcomes

O1 — On startup, the active tab’s main-layout panes are restored before its
foreground drawer panes. Remaining active-tab panes that are not foreground,
then panes in inactive tabs/background residency, are deferred for later
demand. “Deferred” means the pane remains recoverable and selectable; it does
not mean the pane or drawer membership is discarded.

O2 — A background → save → restart → foreground journey preserves the
backgrounded parent and every drawer child as one recoverable drawer family.
When the saved composition includes drawer arrangement data, foregrounding
reproduces the same drawer child membership and order, split/divider structure,
minimized-child set, and active child for each included arrangement. The
parent’s tab/arrangement placement is also preserved according to the saved
valid composition.

O3 — Valid foreground drawer state survives a deferred mount. Once geometry,
launch readiness, or another retryable host precondition becomes available,
the user can foreground or select the drawer child and see the stored
arrangement rather than a newly synthesized one.

O4 — Invalid persisted compositions continue to follow the existing strict
restore failure behavior. This request does not turn malformed rows into a new
repair or inference contract.

## Accepted requirements

### R1 — Foreground restore order

For a valid startup composition with an active tab, the user-visible restore
order is: (a) active-tab main-layout panes, (b) foreground drawer panes owned
by that tab, and (c) all remaining or background panes deferred until demand or
normal steady-state reconciliation. A pane may be considered foreground only
when it belongs to the active tab’s current arrangement and is not minimized;
an expanded drawer makes its eligible child panes foreground candidates.

Success: a user can interact with the active tab’s main panes before drawer
mounting completes, and drawer panes are attempted before unrelated inactive or
background panes.

Failure expectation: deferred panes remain present in the restored model and
become eligible for later foregrounding; they are not silently removed or
rewritten as a side effect of ordering.

Basis: U1, O1, current startup classification and scheduling evidence.  
Proof slot: V1 — automated ordering/state evidence plus a bounded startup
interaction or runtime observation at the user-visible boundary.

### R2 — Background drawer family survives save and restart

When a user backgrounds a pane that has drawer children, saves, restarts, and
foregrounds that pane, the restored family contains the same parent and drawer
child identities and membership. The family is not dependent on process-local
state surviving the restart.

Success: every child that was in the saved drawer family is present exactly
once, associated with the same parent and tab, after the fresh process
foregrounds the pane.

Failure expectation: a missing child, orphaned child, or silently empty drawer
is a failed restore outcome, not an acceptable fallback for a valid saved
composition.

Basis: U2, O2, current background/reactivation and SQLite bridge evidence.  
Proof slot: V2 — persistence/state inspection across a fresh store/process
boundary and an integration journey that backgrounds, saves, reloads, and
foregrounds the family.

### R3 — Exact saved drawer arrangement is retained

For every arrangement represented in the saved valid composition, foregrounding
the backgrounded family retains its drawer child order, split/divider layout,
minimized-child state, and active child. If a field is absent from the saved
composition, the requirement does not invent a value for it.

Success: comparing the saved and post-restart foregrounded arrangement yields
the same ordered child IDs and the same represented split, minimized, and
active-child facts.

Failure expectation: reactivation must not synthesize a default arrangement,
reorder children, clear the active child, or unminimize a child merely because
the process restarted.

Basis: U2, U3, O2, O3, and the persisted drawer/tab arrangement model.  
Proof slot: V3 — before/after state comparison through SQLite/store
integration, including arrangements with reordered children, splits,
minimized children, and a non-first active child.

### R4 — Deferred restore is non-destructive

If a valid foreground main pane or drawer child cannot mount immediately because
its host, geometry, or launch precondition is not ready, the saved parent,
children, membership, arrangement, minimized state, and active-child state
remain intact until a later foreground attempt.

Success: resolving the deferred precondition allows the user to reveal/select
the same stored drawer family and arrangement.

Failure expectation: a retryable mount/geometry condition is not treated as
proof that the pane or drawer graph is invalid.

Basis: U1–U3, O1–O3, current deferred-host behavior.  
Proof slot: V4 — automated deferred-state transition evidence followed by a
runtime or integration observation of successful later foregrounding.

## Boundaries and non-goals

This one-PR Requirements boundary includes startup restore ordering, durable
retention of background drawer membership/arrangement data, and the associated
user-visible foregrounding behavior and proof.

It does not include:

- a new drawer-only-tab validity model;
- changes to opaque `ZmxSessionID` generation, decoding, attachment, or
  reconciliation;
- stale or unreadable local-sidecar policy beyond preserving valid saved state;
- broad restore-time normalization, inference, migration, or repair of
  malformed compositions;
- eager mounting of every hidden or inactive pane;
- unrelated tab, pane, Bridge, repository, or window lifecycle behavior;
- new command, IPC, or UI semantics for drawers.

## Traceability map

| Need | Problem | Outcome | Requirement | Proof |
| --- | --- | --- | --- | --- |
| U1 | P1, P3 | O1 | R1 | V1 |
| U2 | P2, P3 | O2 | R2, R3, R4 | V2, V3, V4 |
| U3 | P2, P3 | O2, O3 | R3, R4 | V3, V4 |

## Open meaning and evidence gaps

No product decision is left open within this bounded request. The separate
Specification must define the observable startup and persistence contracts
against these Requirements. Program Design must then choose the internal
realization and proof seams without expanding the listed boundary.

The current evidence does not establish which exact existing persistence owner
should carry background drawer arrangements after restart; that is an internal
How question for Program Design, not a Requirements decision. The current
runtime/app proof surface for startup ordering also remains to be selected in
the downstream Specification/Program Design phases.
