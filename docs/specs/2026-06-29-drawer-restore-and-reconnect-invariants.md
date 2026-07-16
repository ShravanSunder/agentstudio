# Drawer Restore And Reconnect Invariants

> **SUPERSEDED — DO NOT IMPLEMENT.** This draft's restore-time graph repair and
> zmx anchor reconciliation/fallback model conflicts with the current strict
> restore contract in [Session Lifecycle Architecture](../architecture/session_lifecycle.md).
> Restore is strict SQLite decode → one composition apply → activation → exact
> stored opaque `ZmxSessionID` attach, with no normalization, repair, discovery,
> adoption, inference, backfill, fallback, or write. The remainder is retained
> only as non-normative historical problem evidence.

Date: 2026-06-29
Historical status: superseded draft
Scope: close-tab undo restore and cold app restart restore for drawer panes

## Product Intent

When a user closes a tab and restores it with Cmd-Shift-T, or quits and relaunches the app, drawer panes should not silently disappear. The user expectation is that the tab comes back with its drawer structure, drawer pane membership, active drawer child, expansion state, and reconnectable terminal sessions intact whenever the underlying workspace and sessions are still valid.

This spec treats "drawer restored" as a multi-domain contract, not a single state blob.

## Current Mental Model

There are two user-visible flows:

```text
close tab -> undo restore
  in-memory undo snapshot
  -> model restore
  -> view/surface restore or deferred placeholder
  -> autosave can persist whatever model survived

app restart -> cold restore
  core.sqlite + <workspace>.local.sqlite
  -> SQLite snapshot bridge
  -> atom hydration and repair
  -> zmx startup reconciliation
  -> launch/visible view restore
```

The flows are different, but both depend on the same invariant chain:

```text
durable graph
  -> local cursor
  -> terminal zmx anchor
  -> runtime visibility and geometry
  -> mounted view/surface when visible or restorable
```

`terminal zmx anchor` is listed before runtime visibility because startup reconciliation happens before surface creation. Visibility and geometry decide whether a restored pane mounts now; they do not decide whether its pane-owned zmx identity exists.

## Spec Boundary / Separability Map

```text
Core SQLite graph
  owns:
    pane identity and parent relationships
    drawer identity
    drawer child membership and order
    tab membership
    arrangement drawer views and drawer-view layouts
    terminal zmx anchor column
  tables:
    pane
    pane_content_terminal.zmx_session_id
    drawer
    drawer_pane
    tab_shell
    tab_pane
    tab_arrangement
    arrangement_drawer_view
    drawer_view_layout_pane
    drawer_view_layout_divider
    drawer_view_minimized_pane

        |
        v

Local SQLite cursor
  owns:
    active tab
    active arrangement
    active pane
    expanded drawer
    active child per arrangement and drawer
  tables:
    local_workspace_cursor
    local_tab_cursor
    local_arrangement_cursor
    local_drawer_cursor
    local_arrangement_drawer_cursor

        |
        v

Atom and repair layer
  owns:
    in-memory pane graph hydration
    tab graph hydration
    cursor composition
    invalid-state pruning and repair
  must preserve:
    valid drawer graph and drawer views
  may repair:
    invalid parent/child/layout references according to explicit rules
  forbidden:
    treating retryable runtime view deferral as authority to delete a
    valid restored drawer graph

        |
        v

Runtime view layer
  owns:
    visible/hidden classification
    launch-settle and bounds gates
    drawer child frame resolution
    placeholder versus hard failure classification
    mounted NSView / terminal surface creation
  may:
    defer mounting and register retry placeholders
  forbidden:
    normalizing or pruning core drawer graph state merely because
    geometry or surface creation is not ready yet

        |
        v

Zmx runtime
  owns:
    live session discovery
    startup anchor reconciliation
    attach command construction
  source of truth:
    pane-owned TerminalState.zmxSessionId
```

## Requirements

### R1. Close-Tab Undo Preserves Drawer Model State

Closing and undo-restoring a tab must restore:

- the parent pane;
- each drawer child pane exactly once;
- the parent drawer id;
- drawer child membership and order;
- tab membership for parent and drawer children;
- arrangement-level `DrawerView` entries;
- drawer-view layout pane ids, dividers, and minimized child state;
- active drawer child cursor for the restored arrangement when that cursor was valid at close time;
- drawer expansion state when it was valid at close time.

Deferred or unavailable view creation must not delete restored model state unless the pane has been proven invalid by a hard model or rendering failure.

### R2. Cold Restart Preserves Durable Drawer Graph

When core SQLite rows are valid, cold restore must preserve:

- `pane` rows for parent and drawer children;
- `drawer` and `drawer_pane` rows;
- `tab_pane` membership for parent and drawer children;
- `arrangement_drawer_view` for every valid drawer view;
- `drawer_view_layout_pane` and `drawer_view_layout_divider`;
- `drawer_view_minimized_pane`.

Repair code may prune invalid references, but every prune rule must be explicit, tested, and distinguishable from accidental drawer loss.

### R3. Cold Restart Preserves Local Cursor When The Local Snapshot Is Valid

When the local sidecar is readable and its completion token matches the core snapshot token, cold restore must preserve:

- `local_drawer_cursor.is_expanded`;
- `local_arrangement_drawer_cursor.active_child_id`;
- active tab, active arrangement, and active pane cursors relevant to restoring the selected drawer child.

When the local sidecar is stale or unreadable, fallback behavior must be explicit. The current observed behavior is default cursor synthesis, which collapses drawers and clears active drawer child state.

For this bugfix, stale or unreadable local-sidecar recovery is out of scope. The required behavior is to preserve local drawer cursor state when the local snapshot is valid and matched. Stale or unreadable local state remains a negative-path repair case: durable core drawer graph rows may survive, but drawer expansion and active child cursor state may fall back to defaults unless a later spec changes the local-sidecar trust model.

### R4. Visible Runtime Restore Uses A Complete Drawer Visibility Tuple

A drawer child can be restored as currently visible only when all of these are true:

- the active tab exists;
- the parent pane belongs to the active tab layout;
- the parent drawer is expanded;
- the active arrangement has a `DrawerView` for the drawer;
- the drawer view layout contains the child pane;
- the child pane is not minimized;
- bounds and geometry are available enough to resolve an initial frame.

If any of these are absent, the model may still be restored even though the view is not immediately mounted. The UI/runtime layer must distinguish "not visible yet" or "deferred placeholder" from "state is invalid and should be deleted."

### R5. Zmx Reconnect Is Pane-Owned, With Kind-Aware Fallback

For terminal drawer panes:

- the durable reconnect identity is `TerminalState.zmxSessionId`;
- SQLite storage is `pane_content_terminal.zmx_session_id`;
- startup reconciliation must run before surface creation;
- a valid stored anchor wins;
- missing or invalid anchors may be repaired only by same-kind adoption or valid legacy derivation;
- current drawer active-child/focus state is not a zmx identity source.

A correct zmx anchor does not guarantee immediate visible reconnect if runtime geometry or drawer visibility gates fail.

### R6. Close/Undo Damage Must Not Become Persisted Restart Damage

If close/undo temporarily cannot mount a view, autosave must not persist a model with valid drawer panes removed merely because view creation deferred. Persistence should save the restored drawer graph and cursor state, not a cleanup artifact caused by geometry not being ready.

### R7. Drawer-Only Tabs Remain Invalid Repair Cases

For this bugfix, drawer-only tabs are not a newly supported persisted shape. Current tab liveness remains anchored to a valid main arrangement layout. Negative-path tests should assert the current repair-away behavior for drawer-only tabs, not redesign tab validity.

## Restore Failure Classification Contract

Undo and launch restore must classify restore outcomes before mutating durable drawer state:

- `restored`: a view/surface is mounted for the pane. Durable pane, drawer, tab, drawer-view, local cursor, and zmx anchor state remain intact.
- `deferred`: the pane model is valid, but mounting cannot happen yet because geometry, launch readiness, bounds, or a retryable placeholder/surface-preparation precondition is not ready. Durable pane, drawer, tab, drawer-view, local cursor, and zmx anchor state must remain intact. Deferred state may register a placeholder or retry marker.
- `hard failure`: the pane or arrangement is invalid by model/repair rules, or a non-retryable renderer/surface failure proves the pane cannot be restored without preserving invalid state. Cleanup may remove or repair invalid model references only through the owning mutation/repair layer, and tests must name the invalid condition.

Examples:

- Empty terminal bounds or missing drawer child frame during close-tab undo is `deferred`, not permission to delete the restored drawer child.
- Missing parent pane, missing drawer child pane, missing `DrawerView` for an otherwise required drawer view, or drawer-only tab after parent pruning is an invalid repair case.
- A failed renderer path is cleanup-worthy only when the failure is explicitly non-retryable or the pane model is invalid; `nil` view creation alone is not enough.

## Non-Goals

- No broad focus ownership rewrite.
- No schema migration unless a red repository test proves the current schema cannot represent required state.
- No backward-compatibility shim or dual restore path.
- No change to zmx session identity semantics unless zmx-specific tests prove the stored-anchor contract is wrong.
- No assertion that every hidden drawer child must mount immediately on restart. The contract is model correctness first, then visible/runtime reconnect when gates are satisfied.
- No stale-local-sidecar recovery redesign in this bugfix. Token mismatch and unreadable local sidecars remain explicit negative-path fallback cases.
- No drawer-only-tab validity redesign in this bugfix. Current repair-away behavior remains authoritative unless a later spec changes tab liveness semantics.

## Accepted Current-State Findings

1. Core graph and local cursor are intentionally separate persistence domains.
2. Restart can reset drawer expansion and active child without losing graph rows if local cursor state falls back to defaults.
3. Repair can remove drawer views when parent or child pane references are invalid.
4. Runtime visible restore depends on active tab, expansion, drawer view, child layout membership, non-minimized state, and geometry.
5. Zmx reconnect uses pane-owned stored anchors, not active drawer child selection.
6. The existing test suite has strong slice coverage but lacks the full cross-boundary bug path.

## Product/Architecture Decisions For This Goal

1. Drawer-only tabs remain invalid repair cases. This goal does not change tab liveness semantics.
2. Stale or unreadable local-sidecar recovery is out of scope. Matched-token local cursor preservation is in scope; stale-token fallback is covered as a negative path.
3. Deferred view restore is a non-destructive state. Hard cleanup requires a named invalid model/repair condition or a named non-retryable renderer/surface failure.
4. The minimum proof floor is unit plus SQLite/store integration plus runtime/app integration for the restored drawer path. Native smoke, zmx E2E, and marker-scoped observability become required when the implementation changes the corresponding live user path, zmx startup/session behavior, or runtime startup instrumentation, or when lower layers cannot prove the user-visible claim.

## Proof Expectations

The implementation plan must operationalize these proof expectations without weakening existing coverage.

### Unit Layer

- Snapshot uniqueness for tab-close with drawer children.
- Model restore preserves drawer graph, drawer views, drawer-view layout panes, dividers, minimized children, and active child facts.
- Local cursor hydrate/compose preserves drawer expansion and active child.
- Zmx planner preserves valid stored anchors and repairs only same-kind invalid/missing anchors.
- Restore failure classification distinguishes restored, deferred, and hard-failure outcomes without requiring view creation to succeed for valid model preservation.

### Integration Layer

- close tab with drawers -> undo -> flush SQLite -> fresh `WorkspaceStore.restoreAsync()` -> assert:
  - parent pane exists;
  - drawer children exist;
  - drawer membership/order exists;
  - `DrawerView` exists;
  - drawer-view layout contains child panes;
  - drawer-view dividers survive when present;
  - minimized drawer children survive when present;
  - expansion cursor survives for matched local token;
  - active drawer child survives for matched local token.
- cold backend restore with matched local token preserves drawer expansion and active child.
- negative-path tests cover stale local token fallback, missing parent pane, missing child pane, missing drawer view, topology/worktree filtering, and drawer-only tab repair-away semantics.
- deferred restore proof covers close/undo with retryable geometry or placeholder deferral and asserts valid drawer graph/cursor state is not removed before persistence.

### Runtime/App Layer

- restored expanded drawer child gets visible restore when the full visibility tuple and geometry are present.
- deferred placeholder restore does not delete valid restored model state.
- reopening or selecting a restored drawer child triggers surface/view restoration when gates become true.
- runtime/app integration is required for any implementation that changes close/undo view restore, launch restore, placeholder retry, visible restore, or drawer selection behavior.

### Zmx/E2E/Observability Layer

- stored zmx anchor survives restart and attaches for drawer panes when a live session exists.
- hidden drawer child reconnect is proven separately from parent-pane visibility.
- if final fix changes runtime startup behavior, marker-scoped observability should prove reconciliation and restore milestones in a debug app run.
- if final fix changes actual user interaction, native smoke should prove close tab -> Cmd-Shift-T -> drawer visible/selectable, and restart if persistence changed.
- live native, zmx, or observability proof must use an isolated debug/beta harness and explicit app/zmx/data-root identity so proof cannot attach to unrelated sessions or mutate stable user state.

## Related Evidence

- Research ledger: `tmp/research-workflows/2026-06-29-drawer-restore-restart-research/research-ledger.md`
- Debug packet: `tmp/debug-workflows/2026-06-29-agent-studio-restore-tab-drawer-loss/debug-investigation.md`
- Goal workflow state: `tmp/workflow-state/2026-06-29-drawer-restore/details.md`
