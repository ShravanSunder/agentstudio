# Foreground and Background Drawer Restore — Specification

Specification identity: `SPEC-2026-08-29-DRAWER-RESTORE`
Requirements: `REQ-2026-08-29-DRAWER-RESTORE`

## Observable contract

1. On launch, the selected tab MUST admit its active main-layout panes before
   admitting its eligible drawer panes. Inactive/background panes MUST NOT delay
   the selected tab becoming interactive.
2. Eligible drawer panes are children in the selected tab's expanded drawer
   layouts that are not minimized. The active drawer child MUST be attempted
   before other eligible drawer children.
3. Deferred panes MUST remain in canonical state and become mountable when the
   tab, drawer, geometry, or host precondition becomes ready.
4. A backgrounded pane with drawer children MUST survive save, process restart,
   and reactivation as one family with identical child membership and identity.
   The tab and arrangement references remain recoverable while the family is
   backgrounded.
5. Reactivation MUST preserve each saved arrangement's drawer order, split and
   divider structure, minimized set, and active child. It MUST NOT synthesize a
   default arrangement when valid saved data exists.
6. Invalid persisted compositions MUST continue to use existing strict restore
   rejection behavior.

## Journey and proof

Startup journey: load canonical state → admit foreground main panes → admit
foreground drawer panes → settle selected tab → defer remaining panes.

Restart journey: background family → persist → create fresh store/coordinator →
reactivate parent → restore exact drawer arrangements → mount on demand.

Proof MUST include unit ordering/state tests, persistence integration across a
fresh store boundary, deferred retry integration, and a bounded debug-startup
smoke.

## Scope

This specification covers one PR implementing the above behavior. It excludes
new drawer models, command/IPC changes, session identity changes, malformed-data
repair, eager hidden-pane mounting, and unrelated lifecycle behavior.
