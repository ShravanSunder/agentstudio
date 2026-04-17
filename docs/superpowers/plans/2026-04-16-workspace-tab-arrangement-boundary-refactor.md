# Tab/Arrangement Atom Split And Sidebar Boundary Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the stale minimize-persistence plan with a forward-looking refactor plan that (1) fixes the remaining correctness gaps, (2) removes business logic from `WorkspaceTabLayoutAtom`, (3) splits tab shell state from arrangement/layout state while preserving `Tab` as the main read model, and (4) removes the `Core -> Features` sidebar dependency with a clean shared presentation boundary.

**Architecture:** Keep canonical state in atoms, but stop using one atom as state store plus rule engine. Split tab shell state into one atom and arrangement/layout state into another, move mutation/repair/selection logic into pure helper types, and assemble `Tab` through a derived read layer so most callers still read one coherent model. Treat sidebar filtering as sidebar feature logic, while moving the shared "sidebar" presentation/grouping/coloring types to a neutral Core boundary that can be used by Core, App, and Features without reverse imports.

**Tech Stack:** Swift 6.2, SwiftUI, `@MainActor` atoms, Swift Testing, existing `WorkspaceStore` persistence wrapper, existing coordinator pattern

---

## Summary

### Why the previous plan is stale

The old `2026-04-16-arrangement-scoped-minimize-persistence.md` plan described work that has already landed. It was useful as an implementation guide once, but it is no longer decision-complete for the current branch because:
- the arrangement-scoped minimize work is already in code
- follow-up review comments now target the remaining architecture debt and one persistence bug
- the next pass is no longer "implement arrangement-scoped minimize," it is "stabilize what landed and refactor the tab/arrangement boundary correctly"

This plan replaces that older one as the branch's forward implementation plan.

### Current tab/arrangement organization

```text
Current

WorkspaceTabLayoutAtom
├─ tab ordering
├─ activeTabId
├─ tab naming
├─ allPaneIds
├─ arrangements
├─ activeArrangementId
├─ activePaneId
├─ zoomedPaneId
├─ minimize / expand
├─ insert / remove / merge / extract / break up
├─ selection fallback rules
├─ prune / repair rules
└─ invariant validation
```

That means one atom currently owns:

```text
canonical state
+ mutation entrypoints
+ repair logic
+ selection logic
+ invariant logic
```

That is exactly the "atoms are not for business logic" smell this refactor is meant to remove.

### Current sidebar dependency problem

```text
Current

Core/Models/SidebarRepoColoring.swift
└─ SidebarRepo : SidebarFilterableRepository

Features/Sidebar/SidebarFilter.swift
└─ protocol SidebarFilterableRepository
```

So the dependency direction is:

```text
Core ─────▶ Features   ❌
```

But the repo rule is:

```text
Features ─▶ Core       ✅
Core     ─▶ Infrastructure only
```

### What we want

```text
Target

Core
├─ WorkspaceTabShellAtom
├─ WorkspaceTabArrangementAtom
├─ WorkspaceTabDerived
├─ pure tab/arrangement rule helpers
└─ neutral shared repo presentation models

Features/Sidebar
└─ concrete sidebar filter logic over shared repo presentation items
```

## Organization Diagram

### Current dependency tree

```text
Sources/AgentStudio
├─ Core
│  ├─ Models
│  │  └─ SidebarRepoColoring.swift
│  │     ├─ SidebarRepo
│  │     ├─ SidebarRepoGroup
│  │     ├─ SidebarRepoGrouping
│  │     └─ SidebarRepoColoring
│  └─ State/MainActor/Atoms
│     ├─ WorkspaceTabLayoutAtom.swift
│     └─ PaneDisplayDerived.swift
│        └─ uses SidebarRepo* for accent color logic
├─ App
│  └─ Panes/WorkspaceLauncherProjector.swift
│     └─ uses SidebarRepo* for grouping/coloring
└─ Features
   └─ Sidebar
      ├─ SidebarFilter.swift
      │  ├─ protocol SidebarFilterableRepository
      │  └─ SidebarFilter.filter(...)
      └─ RepoSidebarContentView.swift
         ├─ uses SidebarFilter
         └─ uses SidebarRepo* types
```

### Target dependency tree

```text
Sources/AgentStudio
├─ Core
│  ├─ Models
│  │  ├─ TabShell.swift
│  │  ├─ TabArrangementState.swift
│  │  └─ RepoPresentation.swift
│  │     ├─ RepoPresentationItem
│  │     ├─ RepoPresentationGroup
│  │     ├─ RepoPresentationGrouping
│  │     └─ RepoPresentationColoring
│  └─ State/MainActor/Atoms
│     ├─ WorkspaceTabShellAtom.swift
│     ├─ WorkspaceTabArrangementAtom.swift
│     ├─ WorkspaceTabDerived.swift
│     └─ TabLayoutRules/
│        ├─ TabArrangementMutationRules.swift
│        ├─ TabArrangementSelectionRules.swift
│        ├─ TabArrangementRepairRules.swift
│        └─ TabArrangementValidation.swift
├─ App
│  ├─ Panes/WorkspaceLauncherProjector.swift
│  │  └─ uses RepoPresentation*
│  └─ Coordination/...
│     └─ reads WorkspaceTabDerived, mutates shell/arrangement atoms
└─ Features
   └─ Sidebar
      ├─ SidebarFilter.swift
      │  └─ concrete filter over [RepoPresentationItem]
      └─ RepoSidebarContentView.swift
         └─ uses SidebarFilter + RepoPresentation*
```

### Read model preservation

```text
Canonical state
├─ WorkspaceTabShellAtom
└─ WorkspaceTabArrangementAtom

Derived read layer
└─ WorkspaceTabDerived
   ├─ tabs
   ├─ activeTab
   ├─ tab(id:)
   └─ tabContaining(paneId:)

Caller experience
└─ still reads Tab
```

This preserves the existing `Tab`-based UI/read surface while removing business logic from atoms.

### Intentional asymmetry

`WorkspaceTabShellAtom` is intentionally thin.

```text
WorkspaceTabShellAtom
├─ ordered tab identity
├─ tab names
└─ activeTabId
```

That is expected. The split is about separating workspace-level tab shell state from per-tab content/layout state, not equalizing code size between atoms.

`activeTabId` belongs in shell state because it is workspace-global tab selection. Switching arrangements inside a tab does not change which tab is active.

## Implementation Changes

### Task 1: Stabilize the current arrangement/minimize implementation before the atom split

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`
- Modify: `Tests/AgentStudioTests/App/ActionExecutorTests.swift`

- [ ] **Step 1: Write the failing transformer pruning test**

Add a test to `WorkspacePersistenceTransformerTests` that:
- creates one persistent pane and one temporary pane
- marks both as minimized inside the active arrangement
- calls `makePersistableState(...)`
- asserts the temporary pane is pruned from `layout`, `visiblePaneIds`, and `minimizedPaneIds`

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspacePersistenceTransformerTests"
```

Expected: fail because `WorkspacePersistenceTransformer.pruneInvalidPanes(...)` currently removes invalid panes from `layout` and `visiblePaneIds` but not `minimizedPaneIds`.

- [ ] **Step 2: Write the failing all-target-minimized switch test**

Add a test to `WorkspaceStoreArrangementTests` that:
- creates a second arrangement containing two panes
- minimizes both panes in that target arrangement
- switches back to default
- switches into the all-minimized target arrangement
- asserts `activePaneId == nil`

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspaceStoreArrangementTests"
```

Expected: fail if the target arrangement still leaves an invalid active-pane choice.

- [ ] **Step 3: Implement the transformer pruning fix**

In `WorkspacePersistenceTransformer.pruneInvalidPanes(...)`, remove invalid pane ids from:
- `layout`
- `visiblePaneIds`
- `minimizedPaneIds`

Do this inline in the same loop where invalid pane ids are already removed from layout membership.

- [ ] **Step 4: Update the arrangement-switch helper coverage**

Extend `ActionExecutorTests` so `computeSwitchArrangementTransitions(...)` also covers:
- `newMinimizedPaneIds` non-empty
- target arrangement fully minimized
- target arrangement visible members that should stay detached

- [ ] **Step 5: Run the focused stabilization suite**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspacePersistenceTransformerTests|WorkspaceStoreArrangementTests|ActionExecutorTests"
```

Expected: pass.

### Task 2: Extract tab/arrangement business logic out of the atom

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementSelectionRules.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementRepairRules.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementValidation.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
- Test: add focused tests beside the existing `WorkspaceStoreArrangementTests` and `WorkspaceStoreTests`

- [ ] **Step 1: Write failing helper-focused tests**

Create direct tests for pure rules:
- selection fallback chooses the first unminimized pane
- all panes minimized yields `nil` active pane
- create-arrangement inheritance intersects minimized state with included panes
- pane removal/extract/prune remove stale minimized ids
- duplicate pane cleanup and validation preserve minimized ids only for remaining layout members

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspaceStoreArrangementTests|WorkspaceStoreTests"
```

Expected: at least the new direct helper expectations fail before extraction.

- [ ] **Step 2: Move policy into pure helpers**

Extract from `WorkspaceTabLayoutAtom`:
- active-pane fallback rules
- arrangement switch selection rules
- pane removal/extract/prune cleanup rules
- invariant validation rules

`WorkspaceTabLayoutAtom` should become:
- input validation
- fetch owned state
- call helper
- assign result

No helper should mutate atoms directly.

- [ ] **Step 3: Keep behavior identical while shrinking the atom**

Do not change public behavior in this step. The goal is to make the current `WorkspaceTabLayoutAtom` thinner before state is split.

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspaceStoreArrangementTests|WorkspaceStoreTests|ActionExecutorTests|MinimizeLayoutIntegrationTests"
```

Expected: pass with no behavior regressions.

### Task 3: Split `WorkspaceTabLayoutAtom` into shell state + arrangement state + derived read model

**Files:**
- Create: `Sources/AgentStudio/Core/Models/TabShell.swift`
- Create: `Sources/AgentStudio/Core/Models/TabArrangementState.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabShellAtom.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabDerived.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift`
- Modify: `Tests/AgentStudioTests/Helpers/WorkspaceStoreTestAccess.swift`

**State split definition:**

```text
TabShell
├─ id
└─ name
```

```text
TabArrangementState
├─ tabId
├─ allPaneIds
├─ arrangements
├─ activeArrangementId
├─ activePaneId
└─ zoomedPaneId
```

This split is intentionally asymmetric:
- `TabShell` is the thin workspace-level shell
- `TabArrangementState` owns the heavy per-tab content state
- the asymmetry is expected and not a sign that the split is wrong

- [ ] **Step 1: Write failing read-model parity tests**

Add tests for `WorkspaceTabDerived`:
- assembled `tabs` preserve shell ordering
- `activeTab` still returns a full `Tab`
- `tab(id:)` and `tabContaining(paneId:)` still work exactly like today
- `allPaneIds` and `activePaneIds` still match the assembled `Tab` view

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspaceTabDerived|WorkspaceStoreTests"
```

Expected: fail until the derived layer exists.

- [ ] **Step 2: Introduce new models and atoms**

Implement:
- `TabShell`
- `TabArrangementState`
- `WorkspaceTabShellAtom`
- `WorkspaceTabArrangementAtom`

Ownership:
- `WorkspaceTabShellAtom`
  - ordered tab shells
  - `activeTabId`
  - tab insert/remove/move/rename
- `WorkspaceTabArrangementAtom`
  - per-tab arrangement state
  - pane insertion/removal/extract/merge/break-up
  - arrangement create/remove/switch/rename
  - minimize/expand
  - zoom
  - active pane

- [ ] **Step 3: Introduce `WorkspaceTabDerived`**

`WorkspaceTabDerived` assembles `Tab` from shell + arrangement state and becomes the primary read layer.

It should follow the existing derived pattern used by `WorkspaceLookupDerived`, `WorkspaceFocusDerived`, and `ArrangementDerived`:
- `@MainActor`
- `struct`
- read-only methods over atoms
- no cached observable store

It must provide:
- `tabs`
- `activeTab`
- `tab(_:)`
- `tabContaining(paneId:)`
- `allPaneIds`
- `activePaneIds`

- [ ] **Step 4: Preserve on-disk tab format**

Do not change persisted JSON shape if it can be avoided.
At persistence boundaries:
- on save: derive `[Tab]` from shell + arrangement atoms
- on restore: decode `[Tab]` and fan out into shell + arrangement state

Be explicit about the restore path:
- `Tab` remains the persisted `Codable` format
- add one pure fan-out function that converts `[Tab]` into `([TabShell], [TabArrangementState])`
- run validation and repair in that pure fan-out layer before hydrating atoms
- hydrate atoms only from the already-validated split state

This avoids schema churn and avoids partially-hydrated shell/arrangement atoms from invalid decoded input.

- [ ] **Step 5: Update `AtomRegistry`, `WorkspaceStore`, and `WorkspaceMutationCoordinator`**

`AtomRegistry` should expose:
- `workspaceTabShell`
- `workspaceTabArrangement`
- `workspaceTab` (derived accessor)

`WorkspaceStore` remains only the persistence wrapper around atoms. It should not become the new query facade.

`WorkspaceMutationCoordinator` should receive the two concrete tab atoms it truly needs, not the derived layer.

Constructor propagation that must be updated in one pass:
- `AtomRegistry.init()`
- `WorkspaceStore.init()`
- `WorkspaceStoreTestAccess.swift`
- `WorkspaceMutationCoordinatorTests.swift`
- any App boot wiring that currently builds or passes the old single tab-layout atom

- [ ] **Step 6: Migrate callers while preserving `Tab` reads**

Before editing callers, do a full caller audit and group them by access pattern.

Read-only callers -> migrate to `WorkspaceTabDerived`:
- `PaneTabViewController`
- `PaneCoordinator+ActionExecution`
- `PaneCoordinator+ViewLifecycle`
- `SingleTabContent`
- `ActiveTabContent`
- `TerminalRestoreScheduler`
- `CommandBarDataSource`
- `CommandBarDataSource+WorktreeRows`
- `CommandBarView`
- `CommandBarPanelController`
- `ArrangementDerived`
- `TabDisplayDerived`
- `WorkspaceLookupDerived`
- `WorkspaceFocusDerived`
- `RuntimeTargetResolver`
- test helpers

Mutation callers -> route to concrete atoms:
- `PaneTabViewController`
- `PaneCoordinator+ActionExecution`
- `WorkspaceMutationCoordinator`
- `WorkspaceStoreTestAccess`

Infrastructure / construction sites:
- `AtomRegistry`
- `WorkspaceStore`
- `WorkspacePersistenceTransformer`
- `AppDelegate` / boot wiring
- `WorkspaceMutationCoordinator` tests and fixtures

Rules:
- shell mutations -> `WorkspaceTabShellAtom`
- arrangement/layout mutations -> `WorkspaceTabArrangementAtom`
- no new query facade on `WorkspaceStore`
- no caller should assemble `Tab` ad hoc; use `WorkspaceTabDerived`

- [ ] **Step 7: Delete or reduce the old monolith**

Once callers are migrated:
- either delete `WorkspaceTabLayoutAtom`
- or reduce it to a tiny compatibility shim during the same changeset, then delete it before completion

The preferred end state is deletion.

- [ ] **Step 8: Run focused tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspaceStoreTests|WorkspaceStoreArrangementTests|PaneCoordinatorTests|ActionExecutorTests|PaneTabViewControllerCommandTests|TabBarAdapterTests|CommandBarDataSourceTests|CommandBarStateTests|WorkspaceLookupDerivedTests|WorkspaceFocusDerivedTests"
```

Expected: pass.

### Task 4: Fix the sidebar boundary with real cleanup, not just a protocol patch

**Files:**
- Create: `Sources/AgentStudio/Core/Models/RepoPresentation.swift`
- Delete or replace: `Sources/AgentStudio/Core/Models/SidebarRepoColoring.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/SidebarFilter.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/SidebarWorktreeRow.swift`
- Modify tests under `Tests/AgentStudioTests/Features/Sidebar/`, `Tests/AgentStudioTests/Integration/FilesystemToPrimarySidebarIntegrationTests.swift`, `Tests/AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift`, `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift`, and any Core tests touching accent color

**Target model names:**
- `RepoPresentationItem`
- `RepoPresentationGroup`
- `RepoPresentationGrouping`
- `RepoPresentationColoring`
- `RepoIdentityMetadata`

- [ ] **Step 1: Write failing boundary tests**

Add or update tests to prove:
- the sidebar filter still filters repo/worktree rows correctly
- `PaneDisplayDerived.accentColorHex(for:)` still returns the same color for the same repo/worktree state
- `WorkspaceLauncherProjector` still derives card colors/grouping correctly

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SidebarFilterTests|RepoSidebarContentViewTests|WorkspaceLauncherProjectorTests|PaneDisplayDerivedTests"
```

Expected: fail once the old types are removed or renamed.

- [ ] **Step 2: Move shared presentation/grouping/color logic to a neutral Core model file**

Create `RepoPresentation.swift` and move/rename:
- `SidebarRepo` -> `RepoPresentationItem`
- `SidebarRepoGroup` -> `RepoPresentationGroup`
- `SidebarRepoGrouping` -> `RepoPresentationGrouping`
- `SidebarRepoColoring` -> `RepoPresentationColoring`

- [ ] **Step 3: Make `SidebarFilter` concrete**

Change `SidebarFilter.filter(...)` to operate on `[RepoPresentationItem]`.
Delete:
- `SidebarFilterableRepository`
- `extension Repo: SidebarFilterableRepository`
- any conformance from Core types back to Features-owned protocols

This makes sidebar filtering clearly feature-local.

- [ ] **Step 4: Update all callers**

Replace old `SidebarRepo*` names in:
- sidebar projection
- launcher projector
- pane display accent color logic
- style/comment references in `AppStyles.swift`
- sidebar row/presentation references in `SidebarWorktreeRow.swift`
- tests

- [ ] **Step 5: Verify dependency direction**

Run:

```bash
rg -n "SidebarFilterableRepository" Sources/AgentStudio
rg -n "SidebarRepo\\b|SidebarRepoGroup\\b|SidebarRepoGrouping\\b|SidebarRepoColoring\\b" Sources/AgentStudio
```

Expected:
- no remaining `SidebarFilterableRepository`
- old sidebar-specific shared type names removed or intentionally typealiased only during migration
- no Core file depends on `Features/Sidebar`

### Task 5: Small cleanup pass that belongs with this refactor

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanelPopoverPlacement.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`

- [ ] **Step 1: Rename `WrappingHStack`**

Replace it with:
- a direct `HStack`
- or an honestly-named wrapper such as `ArrangementChipRow`

Current code shape to replace:

```swift
struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}
```

No misleading names.

- [ ] **Step 2: Simplify redundant popover placement if still identical**

This is already known, not something to rediscover during implementation:

```swift
enum ArrangementPanelPopoverPlacement {
    case tabBar
    case minimizedBar

    var sourceAttachmentPoint: UnitPoint { .center }
    var attachmentAnchor: PopoverAttachmentAnchor { .point(sourceAttachmentPoint) }
    var arrowEdge: Edge { .leading }
}
```

If behavior remains identical at implementation time, replace the enum with a simpler constant/configuration value.

- [ ] **Step 3: Make `collapsedLabel` zip-safe**

Current fragile pattern:

```swift
let labelParts = ...
let allocatedTextWidths = ...

ForEach(Array(labelParts.enumerated()), id: \.offset) { index, part in
    ...
    width: allocatedTextWidths[index]
}
```

Replace parallel indexing between `labelParts` and allocated widths with `zip(...)` so the code cannot drift if one side changes shape.

- [ ] **Step 4: Improve missing-pane logging in `accentColorHex(for:)`**

If pane lookup fails, log it before returning `nil`. This is observability cleanup, not a behavior change.

- [ ] **Step 5: Add the last coverage gap**

Add a test for:
- switching into an arrangement where all target panes are minimized
- assert `activePaneId == nil`

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "ArrangementPanel|ActionExecutorTests|WorkspaceStoreArrangementTests|PaneDisplayDerivedTests"
```

Expected: pass.

## Test Plan

### Must-pass behavior scenarios

1. **Arrangement minimize survives arrangement switching**

```text
Default
├─ pane B minimized
└─ switch away / switch back
   └─ pane B still minimized
```

2. **Arrangement minimize survives persistence**

```text
arrangement-local minimized state
├─ write workspace
└─ restore workspace
   └─ same minimized panes restored
```

3. **Create arrangement inherits minimized state only for included panes**

```text
active arrangement minimized = {B, C}
new arrangement panes       = {A, B}
result minimized            = {B}
```

4. **All target panes minimized**

```text
switch to arrangement
└─ every pane minimized
   └─ activePaneId == nil
```

5. **Pane removal / extract / prune cleanup**

```text
remove/extract/prune pane X
└─ X removed from
   ├─ layout
   ├─ visiblePaneIds
   └─ minimizedPaneIds
```

6. **Sidebar boundary**

```text
Features/Sidebar
└─ depends on Core shared presentation

Core
└─ never depends on Features/Sidebar
```

7. **Persistence round-trip through split state**

```text
save
├─ shell atom + arrangement atom
├─ assemble [Tab]
└─ write JSON

restore
├─ decode [Tab]
├─ pure fan-out + validation
├─ hydrate shell atom
├─ hydrate arrangement atom
└─ assembled derived Tab matches pre-save meaning
```

8. **Derived Tab assembly completeness**

```text
WorkspaceTabDerived
├─ preserves tab order
├─ preserves activeTab
├─ preserves activePaneId
├─ preserves activeArrangementId
└─ exposes complete Tab with no missing fields
```

9. **CommandBar survives the split**

```text
CommandBar
├─ reads derived tab state
├─ still builds rows/items correctly
└─ no direct dependency on deleted monolith remains
```

### Full verification

Run sequentially:

```bash
swift test --build-path ".build-agent-$PPID" --filter "WorkspacePersistenceTransformerTests|WorkspaceStoreArrangementTests|WorkspaceStoreTests|ActionExecutorTests|PaneCoordinatorTests|PaneDisplayDerivedTests|SidebarFilterTests|RepoSidebarContentViewTests|WorkspaceLauncherProjectorTests|CommandBarDataSourceTests|WorkspaceLookupDerivedTests|WorkspaceFocusDerivedTests"
mise run test
mise run lint
```

Expected:
- focused suites pass
- `mise run test` exit `0`
- `mise run lint` exit `0`

## Assumptions

- This plan **replaces** the stale `2026-04-16-arrangement-scoped-minimize-persistence.md` as the branch's forward implementation plan.
- `Tab` remains the main read model during this refactor; the implementer should not force the entire app onto new low-level shell/state structs in one pass.
- The tab split is a real state split:
  - shell state atom
  - arrangement/layout atom
  - derived `Tab` read layer
- Business logic belongs in pure helpers, not atoms.
- Sidebar filter stays a sidebar feature concern; shared repo presentation/grouping/coloring stays in Core under neutral names.
- E2E suites remain governed by existing env flags; no new E2E policy is introduced.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-16-workspace-tab-arrangement-boundary-refactor.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
