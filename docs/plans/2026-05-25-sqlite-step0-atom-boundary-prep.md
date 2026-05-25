# SQLite Step 0 Atom Boundary Prep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split lifecycle-mixed atoms and mixed domain types before SQLite repositories land, so later core/local/settings persistence work has clear write owners, derived read models, row projections, and legacy import DTOs.

**Architecture:** Step 0 keeps atoms writer-owned, not table-shaped. SQLite will normalize storage later, but this checkpoint makes the Swift state graph honest first: write-owner atoms own semantic mutation state, derived readers expose UI/validator read models, row projections are repository-only, and legacy Codable payloads are import-only. The first huge checkpoint is complete only when all atom splits, type classification, docs, and focused tests land together.

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

Every affected type must be classified into one role:

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

## Subagent Plan

Use subagents for read-only surveys and review, not concurrent code edits.

- Analyst A: map all `WorkspacePaneAtom`, `WorkspaceTabShellAtom`, `WorkspaceTabArrangementAtom`, and `WorkspaceTabLayoutAtom` consumers.
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

## Rule

Atoms are writer-owned lifecycle groups, not SQL table models. A write-owner atom may project to multiple SQL tables when one validated user command must update those rows coherently.

## Step 0 Boundary Map

| Current surface | Step 0 write owners | Derived/read surface |
| --- | --- | --- |
| WorkspaceMetadataAtom | WorkspaceIdentityAtom, WorkspaceWindowMemoryAtom | workspace metadata read model |
| WorkspacePaneAtom | WorkspacePaneGraphAtom, WorkspaceDrawerCursorAtom | WorkspacePaneDerived |
| WorkspaceTabShellAtom | WorkspaceTabShellAtom, WorkspaceCursorAtom | WorkspaceTabLayoutDerived |
| WorkspaceTabArrangementAtom | WorkspaceTabGraphAtom, WorkspaceArrangementCursorAtom, WorkspacePanePresentationAtom | WorkspaceTabLayoutDerived |
| RepoCacheAtom | RepoEnrichmentCacheAtom, RecentWorkspaceTargetAtom | repo/sidebar read models |
| UIStateAtom | WorkspaceSidebarMemoryAtom, SidebarFocusRuntimeAtom | sidebar shell read model |
| SidebarCacheAtom | SidebarExpandedGroupAtom, SidebarCheckoutColorAtom | sidebar shell read model |
| EditorChooserAtom | EditorPreferenceAtom, EditorChooserRuntimeAtom | editor chooser read model |
| InboxSidebarStateAtom | InboxSidebarMemoryAtom, InboxSidebarRuntimeAtom | inbox sidebar read model |
```

- [ ] **Step 2: Link the doc from the architecture index**

Update `docs/architecture/README.md` so the new document appears in the architecture doc table.

- [ ] **Step 3: Update component and data architecture docs**

Update `docs/architecture/component_architecture.md` and `docs/architecture/workspace_data_architecture.md` so they no longer describe SQLite-bound state as a single mixed `WorkspaceStore` snapshot path.

- [ ] **Step 4: Re-run doc scans**

Run:

```bash
rg -n "one atom per SQL|WorkspaceArrangementGraphAtom|whole-workspace JSON snapshot" AGENTS.md docs/architecture docs/superpowers/specs
```

Expected: no stale `WorkspaceArrangementGraphAtom`; any `whole-workspace JSON snapshot` references are explicitly marked current/pre-Step-0 or legacy.

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
Pane / Drawer graph state
  -> write-owner graph state

drawer.isExpanded
  -> drawer cursor state

rich pane value used by UI
  -> derived read model

legacy Pane / Drawer Codable payload
  -> legacy import DTO if Codable remains mixed
```

Rename or split any type whose name hides that role.

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

Create `WorkspacePaneDerived` so existing UI/validator needs can still read a composed pane shape from graph + cursor + topology/cache facts.

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
- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabDerived.swift`
- Modify/Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- Modify/Create: `Sources/AgentStudio/Core/Models/Tab.swift`
- Modify/Create: `Sources/AgentStudio/Core/Models/PaneArrangement.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/State/WorkspaceTabShellAtomTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/WorkspaceTabDerivedTests.swift`
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
  -> WorkspaceCursorAtom

tab membership + arrangements + layout rows
  -> WorkspaceTabGraphAtom

active arrangement, active pane, active drawer child
  -> WorkspaceArrangementCursorAtom

zoomed pane / transient presentation
  -> WorkspacePanePresentationAtom

rich tab layout value used by UI and validators
  -> WorkspaceTabLayoutDerived read model

legacy Tab / PaneArrangement / DrawerView Codable payload
  -> legacy import DTO if Codable remains mixed
```

Rename or split `Tab`, `PaneArrangement`, and `DrawerView` if their current names hide their live role.

- [ ] **Step 2: Split write owners**

Create or rename the write-owner atoms listed above. `WorkspaceTabGraphAtom` owns tab membership and arrangement/layout graph state. It does not own active cursor state.

- [ ] **Step 3: Rebuild `WorkspaceTabLayoutDerived`**

Expose the rich tab/arrangement shape through a derived reader composed from shell, cursor, graph, arrangement cursor, and presentation atoms.

- [ ] **Step 4: Update coordinator and validators**

Update `WorkspaceMutationCoordinator`, `ActionStateSnapshot`, and tab arrangement validation/mutation helpers so validated commands mutate write owners and read composed values only through derived readers.

- [ ] **Step 5: Verify tab behavior**

Run:

```bash
mise run test -- --filter "WorkspaceTabShellAtomTests|WorkspaceTabDerivedTests|ArrangementDerivedTests|TabArrangementMutationRulesTests|TabArrangementSelectionRulesTests|TabArrangementRepairRulesTests|TabReorderTests|CrossTabPaneMoveTests"
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
rg -n "WorkspaceArrangementGraphAtom|one atom per table|atom.*SQL table|Codable.*live persistence contract" AGENTS.md docs Sources Tests
```

Expected: no stale names; any `Codable` persistence references are explicitly legacy/current-pre-SQLite.

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

## Definition Of Done

- All Step 0 atom splits are implemented, including feature atoms.
- Mixed domain structs are classified, renamed, or split.
- UI and command validation read through derived read models.
- Legacy Codable payloads are import/export compatibility shapes only.
- AGENTS.md and architecture docs disclose the atom-to-SQLite mental model.
- `mise run setup`, `mise run lint`, and `mise run test` have current evidence.
- The code is committed in coherent checkpoints.

## Reviewer Focus Blurb

Please review the first SQLite checkpoint as a boundary-model change, not as SQLite repository work. The core question is whether Step 0 cleanly separates writer-owned atoms, derived read models, legacy import DTOs, and future SQLite row projections before migrations land. Focus especially on the pane/tab/domain split: `WorkspacePaneGraphAtom` vs drawer cursor, `WorkspaceTabGraphAtom` vs tab/arrangement cursors vs runtime presentation, and whether the renamed/split `Pane`, `Drawer`, `Tab`, `PaneArrangement`, and `DrawerView` roles make the mental model clearer. Push hard on any place where a type still secretly means "Codable payload plus live state plus UI read model," or where the coordinator starts manipulating table-shaped fragments instead of semantic write owners.
