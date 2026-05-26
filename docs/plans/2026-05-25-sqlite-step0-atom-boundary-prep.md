# SQLite Step 0 Atom Boundary Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split lifecycle-mixed atoms and mixed domain types before SQLite repositories land, so later core/local/settings persistence work has clear write owners, derived read models, row projections, and legacy import DTOs.

**Architecture:** Step 0 keeps atoms writer-owned, not table-shaped. SQLite will normalize storage later, but this checkpoint makes the Swift state graph honest first: write-owner atoms own semantic mutation state, derived readers expose UI/validator read models, row projections are repository-only, and legacy Codable payloads are import-only. The first huge checkpoint is complete only when all atom splits, type classification, docs, and focused tests land together.

Step 0 surveys every atom-backed state surface, but surveying is not the same as
persisting. Each field must land in exactly one lifecycle lane:

```text
core graph
  -> durable workspace structure and validated semantic state

local UX memory
  -> per-workspace focus, selection, window/sidebar memory, and caches that can
     reset without corrupting the workspace graph

settings
  -> user preferences that are not scoped to one workspace graph

runtime / presentation
  -> transient UI, focus, keyboard, health, pending-request, and display facts
  -> never imported from legacy workspace JSON and never written to SQLite in
     Step 1

derived read model
  -> composed UI/validator shape built from the lanes above
  -> not a persistence owner
```

**Tech Stack:** Swift 6.2, Swift Testing, Observation `@Observable`, existing `AtomRegistry` / `AtomReader` / `Derived` helpers, `mise` build and test tasks.

---

## Source Specs

Read these before editing code:

- `docs/superpowers/specs/2026-05-22-sqlite-current-data-design.md`
- `docs/superpowers/specs/sqlite/00-persistence-boundaries.md`
- `docs/superpowers/specs/sqlite/01-core-workspace-schema.md`
- `docs/superpowers/specs/sqlite/02-local-ux-and-cache-schema.md`
- `docs/superpowers/specs/sqlite/04-migration-and-recovery.md`
- `docs/superpowers/specs/sqlite/05-write-paths-and-actors.md`
- `docs/superpowers/specs/sqlite/06-test-checkpoints.md`
- `AGENTS.md`

## Non-Goals

- Do not implement GRDB repositories.
- Do not create SQLite migrations.
- Do not change legacy JSON file locations.
- Do not add workspace-switching UI.
- Do not replace the full persistence stack in this checkpoint.

## Role Vocabulary

Every affected state field must be classified into one lifecycle lane. A Swift
type may participate in more than one role only when those roles are explicit
and separated by name/context:

```text
write-owner atom state
  mutable MainActor state with one lifecycle and one write path

derived read model
  composed value for UI, validators, command snapshots, and tests

SQLite row projection
  repository-facing table shape used by later SQLite code

legacy import DTO
  Codable shape for old JSON files only
```

No type may remain ambiguously both a legacy Codable payload and the live SQLite write model.

Concrete naming policy for Step 0:

```text
Pane / Drawer / Tab / PaneArrangement / DrawerView
  -> derived read-model names only after the split
  -> never stored directly inside write-owner atoms

LegacyPanePayload / LegacyDrawerPayload / LegacyTabPayload /
LegacyPaneArrangementPayload / LegacyDrawerViewPayload
  -> Codable legacy JSON import/export compatibility only
  -> live under Persistence or an import DTO namespace

PaneGraphState / DrawerGraphState / TabGraphState /
ArrangementGraphState / DrawerViewGraphState
  -> write-owner atom state
  -> no embedded cursor, presentation, or cache/display fields

PaneRow / DrawerRow / TabShellRow / ArrangementRow / ...
  -> future SQLite row projection names
  -> repository-facing only
```

If keeping `Pane` or `Tab` as public names is cheaper for UI compatibility,
they must be returned by derived readers only. Write-owner atoms should expose
their explicit graph/cursor state, not the rich read model.

## Atomic Write Boundary Matrix

Step 0 is acceptable only if these semantic commands remain atomic at the
MainActor read boundary. "Atomic" means SwiftUI, validators, and command
snapshots never observe a half-updated composed read model. One command may
sequence multiple write-owner atoms, but each listed owner must update through
one explicit method and the coordinator must repair dependent cursors before it
returns.

| Semantic command | Write owners | Synchronous repair / projection rule | Forbidden implementation | Required verification |
| --- | --- | --- | --- | --- |
| Select tab | `WorkspaceTabCursorAtom` | selected id must exist in `WorkspaceTabShellAtom`; derived tab layout reflects the new active tab immediately | write active tab through tab shell or tab graph | `WorkspaceTabCursorAtomTests.selectTabRejectsMissingTab` |
| Create tab | `WorkspaceTabShellAtom`, `WorkspaceTabGraphAtom`, optional `WorkspaceTabCursorAtom` | shell row, default arrangement graph, pane membership, and active tab selection project as one composed tab layout | merge shell identity into tab graph just to avoid a two-owner command | `WorkspaceTabCreationAtomicityTests.createTabProjectsShellGraphAndCursorTogether` |
| Rename/reorder tab | `WorkspaceTabShellAtom` | graph and cursor atoms do not mutate | route tab shell edits through arrangement graph | `WorkspaceTabShellAtomTests.renameAndReorderDoNotTouchTabGraph` |
| Insert pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | pane graph, tab membership/layout, active pane cursor, and zoom reset project together; validator snapshot sees inserted+focused pane | store rich `Pane` or `Tab` directly in graph atoms, let validator read three owners separately, or leave stale zoom | `WorkspacePaneInsertionAtomicityTests.insertPaneProjectsGraphCursorAndZoomResetTogether` |
| Reactivate pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | backgrounded pane residency, layout membership, active pane cursor, and zoom reset project together | treat residency as unrelated to insertion or leave zoom stale | `WorkspacePaneResidencyAtomicityTests.reactivatePaneProjectsResidencyLayoutCursorAndZoomTogether` |
| Background pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, sometimes `WorkspaceDrawerCursorAtom`, sometimes `WorkspaceTabShellAtom`, sometimes `WorkspaceTabCursorAtom` | pane residency changes to backgrounded, layout references are removed, affected cursors repair, and empty-tab shell/cursor cleanup happens before observation | model this as pane-only residency or rely on local reconciliation for cursor/tab cleanup | `WorkspacePaneResidencyAtomicityTests.backgroundPaneRepairsGraphCursorAndEmptyTabTogether` |
| Close pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, sometimes `WorkspaceDrawerCursorAtom`, sometimes `WorkspaceTabShellAtom`, sometimes `WorkspaceTabCursorAtom` | active pane, active drawer child, drawer expansion, tab membership, and last-pane tab shell/cursor cleanup are repaired before UI observes deleted ids | rely only on local DB reconciliation after a core delete or forget the last-pane tab cleanup path | `WorkspacePaneDeletionAtomicityTests.closePaneClearsDanglingPaneAndTabCursorIdsSynchronously` |
| Close tab | `WorkspacePaneGraphAtom`, `WorkspaceTabShellAtom`, `WorkspaceTabGraphAtom`, `WorkspaceTabCursorAtom`, `WorkspaceArrangementCursorAtom`, `WorkspaceDrawerCursorAtom`, `WorkspacePanePresentationAtom` | all panes and drawer cursors for the tab are removed, active tab moves to next/default/nil, arrangement cursor and zoom state clear before observation | implement as shell-only tab removal or leave pane/cursor/presentation state behind | `WorkspaceTabDeletionAtomicityTests.closeTabClearsPaneGraphCursorsAndPresentationTogether` |
| Move pane across tabs | `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `WorkspacePanePresentationAtom` | source and destination tab graphs update together; source/destination active pane cursors are repaired in memory; source/destination zoom clears as needed | update source tab and destination tab as separate visible projections or leave stale zoom | `WorkspacePaneMoveAtomicityTests.crossTabMoveRepairsCursorsAndZoomTogether` |
| Attach drawer pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom` | drawer membership/layout and active drawer child projection update together | make drawer membership a table-shaped atom separate from pane graph | `WorkspaceDrawerMutationAtomicityTests.attachDrawerPaneProjectsMembershipAndCursorTogether` |
| Detach last drawer pane | `WorkspacePaneGraphAtom`, `WorkspaceTabGraphAtom`, `WorkspaceDrawerCursorAtom`, `WorkspaceArrangementCursorAtom` | drawer-view graph removes the child, reconstituted drawer preserves prior expansion, and active child resets to nil/default synchronously | lose expansion because graph and drawer cursor are treated as one core type, or forget drawer-view graph cleanup | `WorkspaceDrawerMutationAtomicityTests.detachLastChildUpdatesDrawerViewGraphPreservesExpansionAndClearsActiveChild` |
| Expand drawer | `WorkspaceDrawerCursorAtom` | one atom method collapses all other drawers and toggles target before observation; `WorkspacePaneDerived` reflects target true and others false in the same MainActor tick | single-row cursor writes that allow two expanded drawers in memory, or cursor changes that are not reflected by the derived pane value | `WorkspaceDrawerCursorAtomTests.expandDrawerCollapsesOtherDrawersAndDerivedPaneReflectsItAtomically` |
| Switch arrangement | `WorkspaceArrangementCursorAtom` | exposes the new arrangement's remembered active pane and active child, or deterministic defaults; derived `Tab.activeArrangement` reflects the switch immediately | store active arrangement on `TabGraphState` or leave old arrangement cursor values visible | `WorkspaceArrangementCursorAtomTests.switchArrangementRestoresRememberedPaneAndDrawerCursor` |
| Toggle zoom/presentation | `WorkspacePanePresentationAtom` | runtime presentation changes do not write graph/cursor/local persistence | persist `zoomedPaneId` or place it in arrangement cursor | `WorkspacePanePresentationAtomTests.zoomDoesNotMutatePersistedOwners` |
| Topology prune / hard delete | `WorkspaceRepositoryTopologyAtom`, affected pane/tab graph owners, affected cursor owners | dangling pane/worktree/repo references are synchronously removed or cleared from in-memory read models | wait for next boot/local reconciliation to clear invalid ids | `WorkspaceTopologyPruneAtomicityTests.pruneClearsGraphAndCursorReferencesBeforeReturn` |
| Repo reassociation | `WorkspaceRepositoryTopologyAtom`, `WorkspacePaneGraphAtom` | topology update and orphaned-pane residency restoration project together before the command returns | update repo/worktree topology while leaving pane residency visibly orphaned | `WorkspaceTopologyReassociationAtomicityTests.reassociateRepoRestoresPaneResidencyBeforeReturn` |
| Restore tab/pane from undo snapshot | `WorkspacePaneGraphAtom`, `WorkspaceTabShellAtom`, `WorkspaceTabGraphAtom`, `WorkspaceTabCursorAtom`, `WorkspaceArrangementCursorAtom`, `WorkspaceDrawerCursorAtom`, `WorkspacePanePresentationAtom` as applicable | undo restore follows the same atomicity contract as create tab, insert/reactivate pane, and drawer attach; restored panes, tab shell/graph, cursors, and presentation project together | restore rich snapshot values into mixed atoms or show restored shell without pane/arrangement graph | `WorkspaceUndoRestoreAtomicityTests.restoreSnapshotProjectsGraphCursorsAndPresentationTogether` |
| Build validation snapshot | derived readers only | `ActionStateSnapshot` is built at every production call site from `WorkspaceTabLayoutDerived`, `WorkspacePaneDerived`, topology/cache read models, and runtime shortcut read models | snapshot constructors at any call site reach into graph/cursor atoms directly instead of derived readers | `ActionStateSnapshotBoundaryTests.snapshotCallSitesUseDerivedReadersAfterAtomSplit` |

## Subagent Plan

Use subagents for read-only surveys and review, not concurrent code edits.

- Analyst A: after the `pane-shortcuts` PR has merged into `main`, map all `WorkspacePaneAtom`, `WorkspaceTabShellAtom`, `WorkspaceTabArrangementAtom`, `WorkspaceTabLayoutAtom`, keyboard-surface atoms, and action snapshot/validator consumers.
- Analyst B: map current tests that cover pane, drawer, tab, arrangement, metadata, UI/sidebar, repo cache, editor chooser, and inbox sidebar state.
- Reviewer: after the Step 0 diff, review boundary drift, stale docs, over-fragmented atoms, missed domain-type roles, and unchanged behavior.

Keep implementation edits centralized in one worker because these splits touch overlapping registry, coordinator, persistence, and test files.

## Preflight

- [ ] **Step 1: Check worktree state**

Run:

```bash
git status --short
```

Expected: only the plan/spec/doc files from the current doc checkpoint are modified before code begins.

- [ ] **Step 2: Restore local binary artifacts**

Run:

```bash
mise run setup
```

Expected: `Frameworks/GhosttyKit.xcframework` contains a usable binary artifact and the task exits 0.

- [ ] **Step 3: Capture baseline verification**

Run:

```bash
mise run lint
mise run test
```

Expected: lint exits 0. Full tests either exit 0 or fail with a clearly named pre-existing blocker that is recorded before Step 0 code begins.

- [ ] **Step 4: Commit this implementation plan and spec alignment**

Run:

```bash
git add AGENTS.md docs/plans/2026-05-25-sqlite-step0-atom-boundary-prep.md docs/superpowers/specs
git commit -m "Document SQLite Step 0 atom boundary prep"
```

Expected: a doc-only commit exists before code changes begin.

- [x] **Step 5: Rebase after the `pane-shortcuts` PR merges**

Do not execute Step 0 code from a pre-merge shortcut surface. The
`pane-shortcuts` PR landed on `main` as squash commit `6830954a`, and this
worktree has merged `origin/main` before Step 0 code begins. Re-run the
atom/action survey after any later main refresh.

Run:

```bash
git fetch origin
git log --oneline --decorate --max-count=20 origin/main
git merge origin/main
git diff --name-only HEAD@{1}..HEAD -- Sources/AgentStudio Tests/AgentStudioTests docs/architecture
```

Expected: the merged main includes the pane-shortcuts atom/action changes before
Step 0 implementation starts. If the merge introduces conflicts in the current
docs-only checkpoint, resolve only the docs/spec conflicts here; do not begin
atom code edits until the survey below is complete.

- [x] **Step 6: Re-survey pane-shortcuts atom and action surfaces**

Run:

```bash
rg -n "ArrangementPanelPresentationAtom|CommandBarSurfaceAtom|TransientKeyboardSurfaceAtom|ActionStateSnapshot|KeyboardRoutingContext|ActiveKeyboardSurface|PaneOrdinalMap" Sources/AgentStudio Tests/AgentStudioTests docs/architecture
```

Expected: record the post-merge owners before editing Step 0 code. The
post-merge survey found `ArrangementPanelPresentationAtom`,
`CommandBarSurfaceAtom`, `TransientKeyboardSurfaceAtom`,
`KeyboardRoutingContext`, `ActiveKeyboardSurface`, `PaneOrdinalMap`, and the
expanded `ActionStateSnapshot`/validator path. None of these adds SQLite write
ownership; they add runtime/presentation atoms and derived validation inputs
that Step 0 must preserve.

- [x] **Step 7: Amend this plan if pane-shortcuts changed atom boundaries**

If the merged shortcut work adds a new atom, changes a runtime/presentation
owner, or changes `ActionStateSnapshot`, update this implementation plan and
`docs/architecture/atom_persistence_boundaries.md` before code changes begin.
The expected current classification is:

```text
ArrangementPanelPresentationAtom
  -> runtime/presentation atom
  -> owns only pending presentation requests
  -> no SQLite persistence in Step 0

CommandBarSurfaceAtom
TransientKeyboardSurfaceAtom
  -> runtime shortcut/surface ownership
  -> preserve as runtime atoms unless merged code adds persisted fields

KeyboardRoutingContext / ActiveKeyboardSurface
  -> runtime read model for shortcut routing
  -> derived from stable keyboard owner + command/transient surface atoms

PaneOrdinalMap
  -> pure derived helper from ordered pane IDs
  -> not an atom, not persisted

ActionStateSnapshot / ActionValidator
  -> read composed values through derived readers after Step 0
  -> must not reach into graph/cursor atoms independently
```

---

## Task 1: Add Atom Persistence Boundary Docs

**Files:**

- Create: `docs/architecture/atom_persistence_boundaries.md`
- Modify: `docs/architecture/README.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Create the role-disclosure architecture doc**

Create `docs/architecture/atom_persistence_boundaries.md` with these sections:

```markdown
# Atom Persistence Boundaries

## Roles

- Write-owner atom state
- Derived read model
- SQLite row projection
- Legacy import DTO

## Lifecycle Lanes

- Core graph: durable workspace structure.
- Local UX memory: per-workspace cursor, window/sidebar, and cache memory.
- Settings: user preferences.
- Runtime / presentation: transient UI, keyboard, focus, health, and
  pending-request state. Surveyed in Step 0, not persisted in Step 1.
- Derived read model: composed UI/validator values. Never a write owner.

## Rule

Atoms are writer-owned lifecycle groups, not SQL table models. A write-owner atom may project to multiple SQL tables when one validated user command must update those rows coherently.

## Step 0 Boundary Map

| Current surface | Step 0 write owners | Derived/read surface |
| --- | --- | --- |
| WorkspaceMetadataAtom | WorkspaceIdentityAtom, WorkspaceWindowMemoryAtom | workspace metadata read model |
| WorkspacePaneAtom | WorkspacePaneGraphAtom, WorkspaceDrawerCursorAtom | WorkspacePaneDerived |
| WorkspaceTabShellAtom | WorkspaceTabShellAtom, WorkspaceTabCursorAtom | WorkspaceTabLayoutDerived |
| WorkspaceTabArrangementAtom | WorkspaceTabGraphAtom, WorkspaceArrangementCursorAtom, WorkspacePanePresentationAtom | WorkspaceTabLayoutDerived |
| RepoCacheAtom | RepoEnrichmentCacheAtom, RecentWorkspaceTargetAtom | repo/sidebar read models |
| UIStateAtom | WorkspaceSidebarMemoryAtom, SidebarFocusRuntimeAtom | sidebar shell read model |
| SidebarCacheAtom | SidebarExpandedGroupAtom, SidebarCheckoutColorAtom | sidebar shell read model |
| EditorChooserAtom | EditorPreferenceAtom, EditorChooserRuntimeAtom | editor chooser read model |
| InboxSidebarStateAtom | InboxSidebarMemoryAtom, InboxSidebarRuntimeAtom | inbox sidebar read model |

## Domain Type Role Matrix

| Type or field | Write-owner state | Derived reader | Legacy DTO | Future row projection |
| --- | --- | --- | --- | --- |
| Pane | PaneGraphState in WorkspacePaneGraphAtom | Pane from WorkspacePaneDerived | LegacyPanePayload | pane, pane_content_*, pane_tag |
| Drawer identity/membership | DrawerGraphState in WorkspacePaneGraphAtom | Drawer from WorkspacePaneDerived | LegacyDrawerPayload | drawer, drawer_pane |
| Drawer.isExpanded | WorkspaceDrawerCursorAtom | Drawer from WorkspacePaneDerived | LegacyDrawerPayload | local_drawer_cursor.is_expanded |
| PaneMetadata durable fields | PaneGraphState.metadata | Pane from WorkspacePaneDerived | LegacyPaneMetadataPayload | pane source/cwd/checkout/title/tag columns |
| PaneContextFacets durable fields | PaneGraphState.metadata | Pane from WorkspacePaneDerived | LegacyPaneContextFacetsPayload | repo_id, worktree_id, cwd, tags |
| PaneContextFacets display fields | none | WorkspacePaneDerived from topology + RepoEnrichmentCacheAtom | decoded only as legacy compatibility; cache import/rebuild supplies live values | cache_repo_enrichment/cache_worktree_enrichment |
| Tab shell | WorkspaceTabShellAtom | Tab from WorkspaceTabLayoutDerived | LegacyTabPayload | tab_shell |
| Tab.activeArrangementId | WorkspaceArrangementCursorAtom | Tab from WorkspaceTabLayoutDerived | LegacyTabPayload | local_tab_cursor.active_arrangement_id |
| Tab.zoomedPaneId | WorkspacePanePresentationAtom | Tab from WorkspaceTabLayoutDerived | not persisted | none |
| PaneArrangement graph | ArrangementGraphState in WorkspaceTabGraphAtom | PaneArrangement from WorkspaceTabLayoutDerived | LegacyPaneArrangementPayload | tab_arrangement, arrangement_layout_*, arrangement_minimized_pane, arrangement_drawer_view |
| PaneArrangement.activePaneId | WorkspaceArrangementCursorAtom | PaneArrangement from WorkspaceTabLayoutDerived | LegacyPaneArrangementPayload | local_arrangement_cursor.active_pane_id |
| DrawerView graph | DrawerViewGraphState in WorkspaceTabGraphAtom | DrawerView from WorkspaceTabLayoutDerived | LegacyDrawerViewPayload | drawer_view_layout_*, drawer_view_minimized_pane |
| DrawerView.activeChildId | WorkspaceArrangementCursorAtom | DrawerView from WorkspaceTabLayoutDerived | LegacyDrawerViewPayload | local_arrangement_drawer_cursor.active_child_id |
```

- [ ] **Step 2: Link the doc from the architecture index**

Update `docs/architecture/README.md` so the new document appears in the architecture doc table.

- [ ] **Step 3: Update component and data architecture docs**

Update `docs/architecture/component_architecture.md` and `docs/architecture/workspace_data_architecture.md` so they no longer describe SQLite-bound state as a single mixed `WorkspaceStore` snapshot path.

- [ ] **Step 4: Re-run doc scans**

Run:

```bash
rg -n "one atom per SQL|Workspace(Cursor|ArrangementGraph)Atom|whole-workspace JSON snapshot" AGENTS.md docs/architecture docs/superpowers/specs
```

Expected: no stale old arrangement-graph atom name and no stale generic workspace-cursor atom name; any `whole-workspace JSON snapshot` references are explicitly marked current/pre-Step-0 or legacy.

---

## Task 2: Add ActiveWorkspaceSelectionAtom

**Files:**

- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/ActiveWorkspaceSelectionAtom.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/ActiveWorkspaceSelectionAtomTests.swift`

- [ ] **Step 1: Write the atom tests**

Create tests covering:

- initial active workspace id can be nil
- setting active workspace id does not require hydrating workspace identity
- clearing active workspace id is allowed for empty/welcome state

Run:

```bash
mise run test -- --filter "ActiveWorkspaceSelectionAtomTests"
```

Expected: fail because the atom does not exist.

- [ ] **Step 2: Add the atom**

Create `ActiveWorkspaceSelectionAtom` as `@MainActor @Observable final class` with private(set) `activeWorkspaceId: UUID?`, plus `selectWorkspace(_:)` and `clearSelection()` methods.

- [ ] **Step 3: Register it**

Add `activeWorkspaceSelection` to `AtomRegistry` with a default `.init()`.

- [ ] **Step 4: Verify**

Run:

```bash
mise run test -- --filter "ActiveWorkspaceSelectionAtomTests"
```

Expected: pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/AgentStudio/AtomRegistry.swift Sources/AgentStudio/Core/State/MainActor/Atoms/ActiveWorkspaceSelectionAtom.swift Tests/AgentStudioTests/Core/State/MainActor/Atoms/ActiveWorkspaceSelectionAtomTests.swift
git commit -m "Add active workspace selection atom"
```

---

## Task 3: Split Low-Risk Local, Settings, And Runtime Atoms

**Files:**

- Modify/Create under: `Sources/AgentStudio/Core/State/MainActor/Atoms/`
- Modify/Create under: `Sources/AgentStudio/Features/EditorChooser/State/MainActor/Atoms/`
- Modify/Create under: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Test under: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/`
- Test under: `Tests/AgentStudioTests/Features/InboxNotification/State/`

- [ ] **Step 1: Split workspace metadata**

Create or rename state so:

```text
WorkspaceIdentityAtom
  -> id, name, createdAt

WorkspaceWindowMemoryAtom
  -> sidebarWidth, windowFrame
```

Tests:

```bash
mise run test -- --filter "WorkspaceMetadataAtom|WorkspaceIdentity|WorkspaceWindowMemory"
```

Expected: identity mutation does not schedule window/sidebar memory writes; window memory mutation does not mutate identity.

- [ ] **Step 2: Split sidebar shell state**

Create or rename state so:

```text
WorkspaceSidebarMemoryAtom
  -> filterText, isFilterVisible, sidebarCollapsed, sidebarSurface

SidebarFocusRuntimeAtom
  -> sidebarHasFocus
```

Tests:

```bash
mise run test -- --filter "UIStateAtomCompositionTests|UIStateStoreCompositionTests"
```

Expected: persisted sidebar memory is independent from runtime focus.

- [ ] **Step 2a: Classify pane-shortcuts runtime atoms if present**

If the `pane-shortcuts` PR has landed, preserve its shortcut/presentation atoms
as runtime-only unless the merged code introduced explicit persisted fields.

Expected classification:

```text
ArrangementPanelPresentationAtom
  -> runtime/presentation
  -> owns pendingRequest only

CommandBarSurfaceAtom
  -> runtime command surface

TransientKeyboardSurfaceAtom
  -> runtime transient shortcut surface

KeyboardRoutingContext / ActiveKeyboardSurface
  -> runtime shortcut-routing read model

PaneOrdinalMap
  -> pure derived helper from tab or drawer pane order
```

Add or update tests only if Step 0 changes how these atoms are registered or
read by derived validators.

- [ ] **Step 3: Split sidebar cache**

Create or rename state so:

```text
SidebarExpandedGroupAtom
  -> expandedGroups

SidebarCheckoutColorAtom
  -> checkoutColors
```

Tests:

```bash
mise run test -- --filter "SidebarCacheAtomTests|SidebarCacheStoreTests"
```

Expected: expanded groups and checkout colors mutate independently.

- [ ] **Step 4: Split feature atoms**

Create or rename state so:

```text
EditorPreferenceAtom
  -> bookmarkedEditorId

EditorChooserRuntimeAtom
  -> openForPaneId, availableTargets

InboxSidebarMemoryAtom
  -> collapsedGroups

InboxSidebarRuntimeAtom
  -> pendingFilter
```

Tests:

```bash
mise run test -- --filter "EditorChooser|InboxSidebarStateAtomTests"
```

Expected: settings/local memory behavior remains stable; runtime-only fields do not persist.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/AgentStudio Tests/AgentStudioTests
git commit -m "Split low-risk local settings and runtime atoms"
```

---

## Task 4: Split Repo Cache Write Ownership

**Files:**

- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/RepoCacheStoreTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift`

- [ ] **Step 1: Split cache and local target history**

Create or rename state so:

```text
RepoEnrichmentCacheAtom
  -> repoEnrichmentByRepoId
  -> worktreeEnrichmentByWorktreeId
  -> pullRequestCountByWorktreeId
  -> notificationCountByWorktreeId
  -> sourceRevision
  -> lastRebuiltAt

RecentWorkspaceTargetAtom
  -> recentTargets
```

- [ ] **Step 2: Preserve current readers**

Update command bar, sidebar, and workspace cache coordinator consumers to read the split atoms directly or through a derived reader. Do not make `RepoEnrichmentCacheAtom` own recent targets.

- [ ] **Step 3: Verify focused cache tests**

Run:

```bash
mise run test -- --filter "RepoCacheStoreTests|WorkspaceRepoCacheTests|WorkspaceCacheCoordinator"
```

Expected: cache reset does not delete recent workspace targets.

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/AgentStudio Tests/AgentStudioTests
git commit -m "Split repo enrichment cache from recent targets"
```

---

## Task 5: Split Pane Graph, Drawer Cursor, And Pane Read Model

**Files:**

- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneDerived.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/Models/PaneTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/PaneArrangementInvariantTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/PaneRemovalCascadeTests.swift`

- [ ] **Step 1: Classify pane-related domain types**

Decide and document in code names:

```text
Pane / Drawer
  -> derived read-model names returned by WorkspacePaneDerived

PaneGraphState / DrawerGraphState
  -> write-owner state held by WorkspacePaneGraphAtom
  -> includes pane identity, content, residency, durable metadata,
     drawer identity, and drawer membership
  -> excludes drawer.isExpanded and display/cache facets

WorkspaceDrawerCursorAtom
  -> drawer.isExpanded by drawer id

LegacyPanePayload / LegacyDrawerPayload
  -> Codable import/export compatibility for current JSON only

PaneMetadata / PaneContextFacets
  -> split by field:
     durable routing fields are graph state
     display/cache fields are derived from topology + RepoEnrichmentCacheAtom
     legacy JSON fields are decoded through LegacyPaneMetadataPayload /
       LegacyPaneContextFacetsPayload
```

Do not leave the graph atom storing the rich `Pane` type directly. `Pane` may
remain as the composed UI/read-model value only if the graph atom stores
explicit graph-state structs and the legacy importer decodes explicit
`Legacy*Payload` structs.

- [ ] **Step 2: Split write owners**

Create or rename:

```text
WorkspacePaneGraphAtom
  -> panes, content, metadata, drawer identity, drawer membership

WorkspaceDrawerCursorAtom
  -> isExpanded by drawer id
```

`WorkspaceDrawerCursorAtom` must expose one semantic drawer expansion method that collapses all other drawers in memory before observers see the target drawer expand.

- [ ] **Step 3: Add derived read model**

Create `WorkspacePaneDerived` so existing UI/validator needs can still read a composed `Pane` shape from graph + cursor + topology/cache facts. It must derive `repoName`, `worktreeName`, `parentFolder`, `organizationName`, `origin`, and `upstream` from topology/cache, not from `WorkspacePaneGraphAtom`.

- [ ] **Step 4: Verify pane behavior**

Run:

```bash
mise run test -- --filter "PaneTests|PaneArrangementInvariantTests|PaneRemovalCascadeTests|WorkspacePaneFocusDerivedTests|PaneDisplayDerivedTests"
```

Expected: pane creation, drawer membership, drawer expansion mutual exclusion, and pane display derivation preserve current behavior.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/AgentStudio Tests/AgentStudioTests
git commit -m "Split pane graph and drawer cursor atoms"
```

---

## Task 6: Split Tab Shell, Tab Graph, Arrangement Cursor, Presentation, And Read Model

**Files:**

- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabShellAtom.swift`
- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- Rename/Delete: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
- Rename: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabDerived.swift` -> `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutDerived.swift`
- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- Modify/Create: `Sources/AgentStudio/Core/Models/Tab.swift`
- Modify/Create: `Sources/AgentStudio/Core/Models/PaneArrangement.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/State/WorkspaceTabShellAtomTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/WorkspaceTabLayoutDerivedTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/ArrangementDerivedTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/TabArrangementMutationRulesTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/TabArrangementSelectionRulesTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/TabArrangementRepairRulesTests.swift`

- [ ] **Step 1: Classify tab and arrangement domain types**

Decide and document in code names:

```text
tab shell identity/order
  -> WorkspaceTabShellAtom

active tab cursor
  -> WorkspaceTabCursorAtom

tab membership + arrangements + layout rows
  -> WorkspaceTabGraphAtom

active arrangement, active pane, active drawer child
  -> WorkspaceArrangementCursorAtom

zoomed pane / transient presentation
  -> WorkspacePanePresentationAtom

rich tab layout value used by UI and validators
  -> WorkspaceTabLayoutDerived read model

Tab / PaneArrangement / DrawerView
  -> derived read-model names returned by WorkspaceTabLayoutDerived

TabGraphState / ArrangementGraphState / DrawerViewGraphState
  -> write-owner state held by WorkspaceTabGraphAtom
  -> excludes activeArrangementId, activePaneId, activeChildId, and zoomedPaneId

LegacyTabPayload / LegacyPaneArrangementPayload / LegacyDrawerViewPayload
  -> Codable import/export compatibility for current JSON only
```

Do not leave `WorkspaceTabGraphAtom` storing the rich `Tab` type directly.
`Tab`, `PaneArrangement`, and `DrawerView` may remain as composed
UI/read-model names only if graph/cursor/presentation atoms store explicit
role-specific state and persistence code uses explicit `Legacy*Payload` DTOs.

- [ ] **Step 2: Split write owners**

Create or rename the write-owner atoms listed above. `WorkspaceTabGraphAtom` owns tab membership and arrangement/layout graph state. It does not own active cursor state.

Creating a new tab is intentionally a two-write-owner semantic command:

```text
new tab command
  -> WorkspaceTabShellAtom inserts the shell identity/order
  -> WorkspaceTabGraphAtom inserts tab membership + default arrangement graph
  -> WorkspaceTabCursorAtom selects the new active tab when the command requires focus
```

Do not merge tab shell back into tab graph just to make this command easier.

- [ ] **Step 3: Rebuild `WorkspaceTabLayoutDerived`**

Delete or rename the current `WorkspaceTabLayoutAtom` wrapper because it is not a write-owner atom after Step 0. The single read-only composed reader is `WorkspaceTabLayoutDerived`, built from shell, tab cursor, graph, arrangement cursor, and presentation atoms. `WorkspaceTabDerived` should not remain as a second overlapping reader unless it has a distinct documented job.

- [ ] **Step 4: Update coordinator and validators**

Update `WorkspaceMutationCoordinator`, `ActionStateSnapshot`, and tab arrangement validation/mutation helpers so validated commands mutate write owners and read composed values only through derived readers.

After the `pane-shortcuts` PR merge, `ActionStateSnapshot` and
`ActionValidator` are high-risk integration points. Re-read their merged
constructors before editing. The snapshot now carries owned/visible pane
membership, active arrangement, drawer parent/layout facts, and topology
existence sets. Build those values from `WorkspaceTabLayoutDerived`,
`WorkspacePaneDerived`, and topology/cache owners; do not reach independently
into graph/cursor atoms from validators. Keyboard-surface, arrangement-panel,
and ordinal-pane facts remain runtime or derived read inputs, not new
write-owner state.

Insertion and movement commands must preserve the expected cross-owner shape:

```text
insert pane command
  -> WorkspacePaneGraphAtom owns pane identity/content/metadata
  -> WorkspaceTabGraphAtom owns tab_pane + arrangement layout membership
  -> WorkspaceArrangementCursorAtom owns the active pane shift

move pane to another tab
  -> WorkspaceTabGraphAtom owns source/destination membership/layout changes
  -> WorkspaceArrangementCursorAtom repairs active pane / drawer child cursors
```

- [ ] **Step 5: Verify tab behavior**

Run:

```bash
mise run test -- --filter "WorkspaceTabShellAtomTests|WorkspaceTabLayoutDerivedTests|ArrangementDerivedTests|TabArrangementMutationRulesTests|TabArrangementSelectionRulesTests|TabArrangementRepairRulesTests|TabReorderTests|CrossTabPaneMoveTests"
```

Expected: tab shell ordering, tab membership, active selection, arrangement mutations, drawer child cursor, zoom reset, and cross-tab pane movement preserve current behavior.

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/AgentStudio Tests/AgentStudioTests
git commit -m "Split tab graph cursor presentation and read models"
```

---

## Task 7: Update Persistence Wrappers Without Adding SQLite

**Files:**

- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Persistence/InboxNotificationStore.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/SidebarCacheStoreTests.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/State/InboxNotificationStoreTests.swift`

- [ ] **Step 1: Keep legacy JSON stores working through the split**

Update current stores so they observe the new atoms or derived read models without reintroducing mixed write ownership.

- [ ] **Step 2: Keep legacy DTOs import/export-only**

If old Codable shapes remain, name them as legacy payloads or isolate them in persistence transformer code. They must not be passed around as live write-owner state.

- [ ] **Step 3: Verify persistence compatibility**

Run:

```bash
mise run test -- --filter "WorkspacePersistenceTransformerTests|UIStateStoreTests|SidebarCacheStoreTests|InboxNotificationStoreTests|PersistenceChaosTests"
```

Expected: current JSON persistence still round trips until SQLite repositories replace it.

- [ ] **Step 4: Commit**

Run:

```bash
git add Sources/AgentStudio Tests/AgentStudioTests
git commit -m "Route legacy persistence through split atom boundaries"
```

---

## Task 8: Final Docs, Best Practices, And Checkpoint Verification

**Files:**

- Modify: `AGENTS.md`
- Modify: `docs/architecture/atom_persistence_boundaries.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/superpowers/specs/sqlite/*.md`

- [ ] **Step 1: Update AGENTS.md component table**

Replace old mixed atom names with the implemented write-owner atoms and derived readers. Keep any compatibility names only if the code still exposes them.

- [ ] **Step 2: Update architecture docs**

Make sure architecture docs describe:

```text
write-owner atoms
derived read models
legacy import DTOs
future SQLite row projections
```

They must also say that atoms are not one-to-one SQL table models.

- [ ] **Step 3: Stale name scan**

Run:

```bash
rg -n "Workspace(Cursor|ArrangementGraph)Atom|one atom per table|atom.*SQL table|Codable.*live persistence contract" AGENTS.md docs Sources Tests
```

Expected: no stale old arrangement-graph atom name and no stale generic
workspace-cursor atom name; any `Codable` persistence references are explicitly
legacy/current-pre-SQLite.

- [ ] **Step 4: Full verification**

Run:

```bash
git diff --check
mise run lint
mise run test
```

Expected: diff check and lint exit 0. Full tests exit 0 before the Step 0 checkpoint is called complete.

- [ ] **Step 5: Commit**

Run:

```bash
git add AGENTS.md docs Sources Tests
git commit -m "Align docs with Step 0 atom boundary split"
```

---

## Stop And Reconverge Conditions

Stop implementation and return to design discussion if any of these happen:

- A derived read model requires a broad UI rewrite instead of preserving current UI/validator inputs.
- A domain type cannot be classified without changing product behavior.
- `WorkspaceMutationCoordinator` starts orchestrating table-shaped fragments instead of semantic write-owner atoms.
- Legacy JSON compatibility requires keeping mixed live write-owner state.
- Focused tests pass only by reintroducing a mixed atom or god read model.
- `Pane`, `Drawer`, `Tab`, `PaneArrangement`, or `DrawerView` must remain both
  live write-owner state and legacy Codable payload to keep tests passing.

## Definition Of Done

- All Step 0 atom splits are implemented, including feature atoms.
- Mixed domain structs are split by role: rich names are derived read models,
  `Legacy*Payload` names are Codable compatibility DTOs, graph/cursor names are
  write-owner state, and future `*Row` names are repository projections.
- UI and command validation read through derived read models.
- Legacy Codable payloads are import/export compatibility shapes only.
- AGENTS.md and architecture docs disclose the atom-to-SQLite mental model.
- `mise run setup`, `mise run lint`, and `mise run test` have current evidence.
- The code is committed in coherent checkpoints.

## Reviewer Focus Blurb

Please review the first SQLite checkpoint as a boundary-model change, not as SQLite repository work. The core question is whether Step 0 cleanly separates writer-owned atoms, derived read models, legacy import DTOs, and future SQLite row projections before migrations land. Focus especially on the pane/tab/domain split: `WorkspacePaneGraphAtom` vs drawer cursor, `WorkspaceTabGraphAtom` vs tab/arrangement cursors vs runtime presentation, and whether the renamed/split `Pane`, `Drawer`, `Tab`, `PaneArrangement`, and `DrawerView` roles make the mental model clearer. Push hard on any place where a type still secretly means "Codable payload plus live state plus UI read model," or where the coordinator starts manipulating table-shaped fragments instead of semantic write owners.
