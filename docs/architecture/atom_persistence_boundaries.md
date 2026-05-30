# Atom Persistence Boundaries

This document defines how Agent Studio classifies atom-backed state before the
SQLite cutover. It is the bridge between the current Observation atom model and
the future normalized SQLite repositories.

## Roles

Every affected type or field must have an explicit role:

- **Write-owner atom state**: mutable `@MainActor` state with one lifecycle and
  one semantic write path.
- **Derived read model**: composed values for UI, command snapshots, validators,
  and tests. Derived readers are never persistence owners.
- **SQLite row projection**: repository-facing table shape used by future
  SQLite code only.
- **Legacy import DTO**: `Codable` shape for old JSON files only.

No type may quietly mean "legacy Codable payload", "live atom state", and
"SQLite row" at the same time.

## Lifecycle Lanes

```text
core graph
  Durable workspace structure and validated semantic state.

local UX memory
  Per-workspace focus, selection, window/sidebar memory, and resettable local
  cache facts.

settings
  User preferences that are not scoped to one workspace graph.

runtime / presentation
  Transient UI, keyboard, focus, health, pending-request, and display facts.
  Surveyed in Step 0, not persisted in Step 1.

derived read model
  Composed UI/validator values built from the lanes above. Never a write owner.
```

Surveying a field does not mean persisting it. Only core graph, local UX memory,
settings, and cache lanes get storage in Step 1.

## Writer-Owned Atoms

Atoms are writer-owned lifecycle groups, not SQL table models. A write-owner
atom may project to several normalized SQLite tables when one validated user
command must update those rows coherently.

The rejected alternative is "one atom per SQL table." That would split ordinary
commands such as pane insertion or drawer attach across table-shaped fragments
like `pane`, `drawer_pane`, `tab_pane`, and `arrangement_layout_pane`. The
coordinator would then need to orchestrate many low-level atoms for one semantic
mutation, and SwiftUI/validator readers would have more opportunities to observe
half-updated state. Keep normalized storage in repositories; keep atom writes
cohesive by lifecycle.

## Step 0 Boundary Map

| Current surface | Step 0 write owners | Derived/read surface |
| --- | --- | --- |
| `WorkspaceMetadataAtom` | `WorkspaceIdentityAtom`, `WorkspaceWindowMemoryAtom` | workspace metadata read model |
| `WorkspacePaneAtom` | `WorkspacePaneGraphAtom`, `WorkspaceDrawerCursorAtom` | `WorkspacePaneDerived` |
| `WorkspaceTabShellAtom` | `WorkspaceTabShellAtom`, `WorkspaceTabCursorAtom` | `WorkspaceTabLayoutDerived` |
| `WorkspaceTabArrangementAtom` | `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | `WorkspaceTabLayoutDerived` |
| `RepoCacheAtom` | `RepoEnrichmentCacheAtom`, `RecentWorkspaceTargetAtom` | repo/sidebar read models |
| `UIStateAtom` source before Step 0 split | `WorkspaceSidebarMemoryAtom`, `SidebarFocusRuntimeAtom` | `WorkspaceSidebarState` |
| `SidebarCacheState` (`SidebarCacheAtom` source before Step 0 split) | `SidebarExpandedGroupAtom`, `SidebarCheckoutColorAtom` | sidebar shell read model |
| `EditorChooserAtom` | `EditorPreferenceAtom`, `EditorChooserRuntimeAtom` | editor chooser read model |
| `InboxSidebarStateAtom` | `InboxSidebarMemoryAtom`, `InboxSidebarRuntimeAtom` | inbox sidebar read model |

## Domain Type Role Matrix

| Type or field | Write-owner state | Derived reader | Legacy DTO | Future row projection |
| --- | --- | --- | --- | --- |
| `Pane` | `PaneGraphState` in `WorkspacePaneGraphAtom` | `Pane` from `WorkspacePaneDerived` | `LegacyPanePayload` | `pane`, `pane_content_*`, `pane_tag` |
| `Drawer` identity and membership | `DrawerGraphState` in `WorkspacePaneGraphAtom` | `Drawer` from `WorkspacePaneDerived` | `LegacyDrawerPayload` | `drawer`, `drawer_pane` |
| `Drawer.isExpanded` | `WorkspaceDrawerCursorAtom` | `Drawer` from `WorkspacePaneDerived` | `LegacyDrawerPayload` | `local_drawer_cursor.is_expanded` |
| `PaneMetadata` durable fields | `PaneGraphState.metadata` | `Pane` from `WorkspacePaneDerived` | `LegacyPaneMetadataPayload` | pane source, cwd, checkout, title, note, tag columns |
| `PaneContextFacets` durable fields | `PaneGraphState.metadata` | `Pane` from `WorkspacePaneDerived` | `LegacyPaneContextFacetsPayload` | repo id, worktree id, cwd, tags |
| `PaneContextFacets` display fields | none | `WorkspacePaneDerived` from topology plus `RepoEnrichmentCacheAtom` | decoded only for legacy compatibility; cache import/rebuild supplies live values | `cache_repo_enrichment`, `cache_worktree_enrichment` |
| `Tab` shell | `WorkspaceTabShellAtom` | `Tab` from `WorkspaceTabLayoutDerived` | `LegacyTabPayload` | `tab_shell` |
| `Tab.activeArrangementId` | `WorkspaceArrangementCursorAtom` | `Tab` from `WorkspaceTabLayoutDerived` | `LegacyTabPayload` | `local_tab_cursor.active_arrangement_id` |
| `Tab.zoomedPaneId` | `WorkspacePanePresentationAtom` | `Tab` from `WorkspaceTabLayoutDerived` | not persisted | none |
| `PaneArrangement` graph | `ArrangementGraphState` in `WorkspaceTabGraphAtom` | `PaneArrangement` from `WorkspaceTabLayoutDerived` | `LegacyPaneArrangementPayload` | `tab_arrangement`, `arrangement_layout_*`, `arrangement_minimized_pane`, `arrangement_drawer_view` |
| `PaneArrangement.activePaneId` | `WorkspaceArrangementCursorAtom` | `PaneArrangement` from `WorkspaceTabLayoutDerived` | `LegacyPaneArrangementPayload` | `local_arrangement_cursor.active_pane_id` |
| `DrawerView` graph | `DrawerViewGraphState` in `WorkspaceTabGraphAtom` | `DrawerView` from `WorkspaceTabLayoutDerived` | `LegacyDrawerViewPayload` | `drawer_view_layout_*`, `drawer_view_minimized_pane` |
| `DrawerView.activeChildId` | `WorkspaceArrangementCursorAtom` | `DrawerView` from `WorkspaceTabLayoutDerived` | `LegacyDrawerViewPayload` | `local_arrangement_drawer_cursor.active_child_id` |

## Runtime And Shortcut Surfaces

The pane-shortcuts and command-bar work added or expanded several runtime
surfaces. These are classified, but not persisted:

| Surface | Lane | Persistence decision |
| --- | --- | --- |
| `ArrangementPanelPresentationAtom.pendingRequest` | runtime / presentation | no SQLite table; pending one-shot presentation request |
| `ArrangementPanelPresentationPlacement` | runtime / presentation | no SQLite table; placement is display intent |
| `CommandBarSurfaceAtom.activeSurface` | runtime / presentation | no SQLite table; command bar scope is transient |
| `TransientKeyboardSurfaceAtom.surfaces` | runtime / presentation | no SQLite table; token-scoped shortcut surface stack |
| `TransientKeyboardSurfaceKind.paneNote` | runtime / presentation | no SQLite table; pane-note editor surface only |
| `PaneNotePresentation` and `PaneNotePopoverDraft` | runtime / presentation | no SQLite table; draft is local UI state |
| `KeyboardRoutingContext` and `ActiveKeyboardSurface` | derived read model | no SQLite table; derived from stable owner plus runtime surfaces |
| `PaneOrdinalMap` | derived helper | no SQLite table; derived from ordered pane ids |

Pane note text itself is different: `PaneMetadata.note` is durable pane graph
metadata and belongs with the future `pane.note` column.

## Validation Boundary

Command validators and `ActionStateSnapshot` must consume rich composed values
through derived readers after atom splits. They must not independently reach
into graph, cursor, cache, and presentation atoms to recreate UI/domain state at
each call site.

## Update Rule

When a new atom, state surface, or persisted field is added:

1. Classify the field into one lifecycle lane.
2. Name its role: write-owner state, derived read model, row projection, or
   legacy DTO.
3. If persisted, identify the owning store/repository and reset semantics.
4. If runtime-only, document that it is never imported from legacy JSON and not
   written to SQLite in Step 1.
5. Add or update focused tests when the classification changes command
   routing, persistence, or derived reader behavior.
