# Foreground and Background Drawer Restore — Program Design

Program Design identity: `PD-2026-08-29-DRAWER-RESTORE`
Requirements: `REQ-2026-08-29-DRAWER-RESTORE`
Specification: `SPEC-2026-08-29-DRAWER-RESTORE`

## Restore pipeline

`WorkspaceCompositionPreparation` will produce four explicit cohorts:
foreground main panes, foreground drawer panes, deferred foreground panes, and
background panes. Within the first cohort, the active main pane is first; within
the second, the active drawer child is first. `WorkspacePreparedContentMountCoordinator`
will expose a phase barrier: it fully settles the foreground-main cohort before
admitting the foreground-drawer cohort. Only after both settle may
deferred/background work start. The existing visibility resolver supplies
eligibility; partitioning, not incidental source order, enforces the ordering.

Terminal and nonterminal owners are instantiated and awaited per cohort, not
given one mixed visible list. `TerminalRestoreScheduler.order` therefore orders
only within the currently admitted cohort and cannot promote a drawer child
ahead of a main pane. The actual mount entry point proves this barrier with a
mixed terminal fixture.

The foreground cohorts are built only from active-residency panes. All active
tab/arrangement projections used by `WorkspaceTabLayoutDerived`, arrangement
views, and startup admission apply the same residency predicate, so retaining
backgrounded references in the durable graph cannot render or mount them early.

`WorkspaceSurfaceCoordinator` will use the same drawer-aware visible-pane
projection for pending restore signals and arrangement transitions. A failed or
deferred drawer mount remains represented by its registry slot and is retried
when geometry or visibility becomes valid. A non-nil registry host is
load-bearing truth: it must still own valid mounted content even when its AppKit
container is temporarily absent. SwiftUI dismantle caused by residency,
arrangement, or drawer projection changes therefore detaches the host from its
container without unmounting content; reveal re-installs that same host.

## Background persistence

`WorkspaceMutationCoordinator` remains the owner of background/foreground
transitions. Backgrounding will retain the parent and drawer-child references
in the tab/arrangement graph while changing their residency to backgrounded;
visibility resolution therefore defers them without removing their durable
drawer views. `WorkspaceSQLiteSaveCoordinator` already serializes that graph,
so no new table or schema migration is required. Reactivation changes
residency back to active and reuses the persisted arrangement directly; the
default seed is used only for genuinely absent drawer data.

The retained graph is canonical persistence state. Active UI/layout
projections derive an active-residency-only view without mutating canonical
membership. Reactivation changes residency at the retained saved location and
does not call `insertPane` or `restoreDrawerPaneViews`, preventing duplicate
membership. A separate explicit move may use the existing move command;
reactivation itself does not reinterpret target or anchor parameters.

Runtime host identity remains owned separately by `ViewRegistry`. Backgrounding
does not unregister or permanently retire parent or drawer-child hosts. When an
active-residency projection removes their SwiftUI leaves, the representable
performs temporary AppKit detach only: mounted content and the registry host
survive. When residency becomes active again, `makeNSView` re-installs the exact
host in its stable container. Explicit pane/tab close remains the only path that
unregisters and permanently unmounts an exact host. This keeps the invariant
`slot.host != nil` ⇒ valid mounted content, so existing repair guards cannot
mistake an empty host for a successful mount.

The call path is:

```text
background command
  → WorkspaceMutationCoordinator.backgroundPane
    → residency = backgrounded (parent + children)
    → existing tab/arrangement graph remains intact
    → WorkspaceSQLiteSaveCoordinator captures graph
    → active projection removes parent/drawer leaves
      → PaneViewRepresentable temporary-detaches exact hosts
      → mounted content + registry hosts remain live

foreground command
  → WorkspaceMutationCoordinator.reactivatePane
    → residency = active (parent + children)
    → persisted drawer views remain selected
    → SwiftUI makeNSView re-installs retained hosts
    → WorkspaceSurfaceCoordinator mounts on demand only for genuinely nil hosts
```

No schema migration or new command is required; use existing graph and
arrangement persistence boundaries and extend their capture/restore payload.

## Proof seams

- Pure partition/order tests prove foreground main-before-drawer ordering.
- Coordinator integration tests prove pending drawer retry and arrangement
  transition repair. The realized-host variant backgrounds a parent with
  drawer children, observes temporary dismantle, reactivates it, and asserts
  the exact parent/child mounted contents remain present once each.
- SQLite integration creates a fresh store/coordinator before reactivation and
  asserts exact-once parent/child identities, same parent and tab association,
  and every saved arrangement's order, split/divider state, minimized IDs, and
  active child.
- Debug startup smoke verifies the selected tab is interactive before deferred
  panes finish mounting.

## Failure and concurrency

Canonical graph validation remains strict. Geometry/host unavailability is
retryable and must not delete or rewrite drawer state. Retryable failures are
`trusted_initial_frame_unavailable` and transient attachment failure; they keep
the canonical state unchanged and re-enter through
`WorkspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(forceWhenBoundsExist:)`.
Trusted-frame unavailability retries when non-empty container bounds settle;
attachment failure retries on explicit pane selection/foregrounding or the
existing user retry action. The prepared ledger settles the failed attempt; the
steady-state repair path creates a fresh host admission rather than inventing a
new registry state. Invalid content, stale generation, and
unsupported pane types are terminal failures and settle the ledger without
retry. MainActor owners perform publication and mounting; off-main persistence
preparation remains immutable and `@concurrent` as required by the existing save
pipeline.

A non-nil registry host with missing mounted content is illegal rather than a
retryable geometry condition: it means temporary detach was incorrectly
implemented as permanent retirement. The integration proof detects it before
the normal `viewRegistry.view(for:) != nil` guard can suppress repair. Temporary
detach, residency publication, remount, unregister, and permanent retirement
are MainActor-serialized; exact host identity prevents a late dismantle from
retiring a same-pane replacement.

## Current-to-proposed call-path delta

```text
Preserved:
  AppDelegate.finishLaunchRestore
    → WorkspacePreparedContentMountCoordinator.mount
    → terminal/nonterminal admission owners

Changed:
  composition preparation
    → explicit foreground-main cohort
    → explicit foreground-drawer cohort
    → deferred/background cohorts

Changed:
  backgroundPane
    → retain durable graph references
    → update residency only

Added:
  active projections/admission
    → filter backgrounded residency

Changed host edge:
  projection removes valid pane leaf
    → temporary AppKit detach; preserve mounted content + registry host
  projection restores pane leaf
    → reinstall same exact host before display

Preserved permanent edge:
  explicit pane/tab close
    → unregister exact host → permanent unmount/retirement

Preserved repair edge:
  bounds/visibility signal
    → restoreVisiblePaneIfNeeded(forceWhenBoundsExist:)
```
