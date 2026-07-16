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

## AtomLib Observation Primitives

`Infrastructure/AtomLib` owns generic observation primitives only. Product
state, registry fields, cache semantics, and feature-specific derived readers
stay in Core or Features.

Lint rule `agentstudio_atomlib_is_generic` enforces this boundary for
`Infrastructure/AtomLib`. Product atoms, feature imports, and concrete
`AtomRegistry` fields belong in the app's Core/Feature state tree or the root
registry, not in the generic primitive library.

Use the primitive that matches the read surface:

| Primitive | Use for | Rule |
| --- | --- | --- |
| `AtomValue<Value>` | one scalar or one cohesive content value | writes require an explicit content comparator except for trivial scalar allowlist types |
| `AtomEntityMap<Key, Value>` | keyed entity families such as repo enrichment, worktree enrichment, and PR counts | hot UI reads use `value(for:)`; dictionary snapshots are bridge surfaces |
| `DerivedValue<Value>` | registry-owned memoized read models | compute from declared input revisions; do not reach back into `AtomScope` or `atom(\...)` |
| `AtomMutationContext` | grouped mutations across primitive updates inside one owner | bump the aggregate revision once after accepted changes |

The derived-read contract is enforced by
`agentstudio_derived_value_declared_inputs`: a `DerivedValue` compute closure
must be a pure function of declared revisions/inputs, not a hidden atom read
through `AtomScope`, `AtomReader`, `atom(\...)`, or `@Atom`.

`AtomEntityMap` is the internal atom-family primitive. It stores a private
dictionary for snapshots, but each key has its own observable slot. A row that
reads `worktreeEnrichment(for: worktreeId)` should wake only when that
worktree's enrichment changes, or when it read an absent key and that same key
later appears. Surfaces that need both branch state and PR count use
`worktreeFacts(for:)`, which composes the two keyed lanes intentionally.
Membership changes are tracked separately from per-key value changes.

Do not expose raw observable dictionaries as hot UI contracts. Dictionary-shaped
APIs are allowed for persistence projections, legacy import/export, tests,
batch reconciliation, and explicitly measured cold paths. Production UI,
command-bar, tab-bar, and sidebar rows should prefer keyed readers or a derived
read model that uses keyed readers internally.

Lint rule `agentstudio_repo_cache_keyed_reads` rejects hot
`repoEnrichmentByRepoId`, `worktreeEnrichmentByWorktreeId`, and
`pullRequestCountByWorktreeId` dictionary reads outside the allowed cold-path
surfaces.

`RepoEnrichmentCacheAtom` is the reference implementation: repo enrichment,
worktree enrichment, and PR counts are owned as separate `AtomEntityMap`
instances; `RepoCacheAtom` exposes keyed reads for hot consumers and snapshot
methods for persistence/cold bulk bridges.

Worktree enrichment diffing must use the narrow comparator helpers rather than
raw `WorktreeEnrichment` equality. Lint rule
`agentstudio_worktree_enrichment_comparator` protects that performance boundary
so non-rendering metadata changes do not wake hot rows.

## Atom And Actor Placement

AtomLib is not a cross-actor state runtime. Canonical UI-observed facts remain
in `@MainActor` atoms. External or fleet-scale work belongs behind actor or
store boundaries and should cross back to the main actor as compact, Sendable
facts, snapshots, deltas, or intents.

| Question | Placement |
| --- | --- |
| Is this canonical UI-observed state? | `@MainActor` atom |
| Does a SwiftUI row need to wake for one key? | `AtomEntityMap` slot in the owning atom |
| Does it perform git, filesystem, SQLite, network, or process work? | runtime/store/off-main actor |
| Does it canonicalize many paths or diff many repos/worktrees/panes/tabs? | actor or measured MainActor exception |
| Is it final application of compact actor output? | owning `@MainActor` atom or coordinator |
| Is it a snapshot for persistence or batch reconciliation? | snapshot bridge, not hot UI observation |

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
| `EditorChooserState` (`EditorChooserAtom` source before Step 0 split) | `EditorPreferenceAtom`, `EditorChooserRuntimeAtom` | editor chooser read model |
| `InboxSidebarState` (`InboxSidebarStateAtom` source before Step 0 split) | `InboxSidebarMemoryAtom`, `InboxSidebarRuntimeAtom` | inbox sidebar read model |

## Domain Type Role Matrix

| Type or field | Write-owner state | Derived reader | Legacy DTO | Future row projection |
| --- | --- | --- | --- | --- |
| `Pane` | `PaneGraphState` in `WorkspacePaneGraphAtom` | `Pane` from `WorkspacePaneDerived` | `LegacyPanePayload` | `pane`, `pane_content_*`, `pane_tag` |
| `Drawer` identity and membership | `DrawerGraphState` in `WorkspacePaneGraphAtom` | `Drawer` from `WorkspacePaneDerived` | `LegacyDrawerPayload` | `drawer`, `drawer_pane` |
| `Drawer.isExpanded` | `WorkspaceDrawerCursorAtom` | `Drawer` from `WorkspacePaneDerived` | `LegacyDrawerPayload` | `local_drawer_cursor.is_expanded` |
| `PaneMetadata` durable fields | `PaneGraphState.metadata` | `Pane` from `WorkspacePaneDerived` | `LegacyPaneMetadataPayload` | pane launch directory, title, checkout, note, and tag columns |
| `PaneContextFacets` durable fields | `PaneGraphState.metadata` | `Pane` from `WorkspacePaneDerived` | `LegacyPaneContextFacetsPayload` | `facet_repo_id`, `facet_worktree_id`, cwd, tags |
| `TerminalState.zmxSessionId` | `PaneGraphState.content` | `Pane` from `WorkspacePaneDerived` | strong non-optional opaque value; existing nonempty text restores verbatim; new values use UUIDv7 | existing `pane_content_terminal.zmx_session_id` text column |
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
3. Choose the observation surface: scalar value, keyed `AtomEntityMap`,
   derived read model, or snapshot bridge.
4. Define the content comparator so equal data does not fire atom invalidation.
5. If persisted, identify the owning store/repository and reset semantics.
6. If runtime-only, document that it is never imported from legacy JSON and not
   written to SQLite in Step 1.
7. Apply the actor-placement gate above before putting expensive work on the
   main actor.
8. Add or update focused tests when the classification changes command
   routing, persistence, or derived reader behavior.
