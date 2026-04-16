# Architecture Documentation Drift Fix

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hard-cut all architecture docs to match the actual codebase, eliminating the session-centric naming, phantom types, stale file paths, and missing system documentation that has accumulated.

**Architecture:** Documentation-only changes. No code modifications. Read the ux-fixes-3 worktree (at `/Users/shravansunder/Documents/dev/project-dev/agent-studio.ux-fixes-3/`) as the source of truth for code state since it has the most complete implementation. Read command-bar-fixes worktree for CommandBar-specific additions. All edits happen in the command-bar-fixes worktree docs.

**Tech Stack:** Markdown documentation

**Source of truth worktrees:**
- Code reality: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.ux-fixes-3/Sources/AgentStudio/`
- CommandBar additions: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.command-bar-fixes/Sources/AgentStudio/Features/CommandBar/`
- Docs to edit: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.command-bar-fixes/docs/architecture/`

---

### Task 1: Fix `component_architecture.md` — Data Model (Sections 1-2)

This is the most stale doc. The entire data model section uses deleted types.

**Files:**
- Modify: `docs/architecture/component_architecture.md` (sections 1-2, lines 1-265)
- Read for truth: `Sources/AgentStudio/Core/Models/Pane.swift`, `Sources/AgentStudio/Core/Models/Tab.swift`, `Sources/AgentStudio/Core/Models/Layout.swift`, `Sources/AgentStudio/Core/Models/Repo.swift`, `Sources/AgentStudio/Core/Models/Worktree.swift`

**What to change:**

- [ ] **Step 1: Read the actual model files** from ux-fixes-3 worktree:
  - `Core/Models/Pane.swift` — actual fields, enums, content types
  - `Core/Models/Tab.swift` — actual fields (activePaneId, activePaneIds, arrangements, zoomedPaneId, minimizedPaneIds)
  - `Core/Models/Layout.swift` — verify the layout tree description is still accurate
  - `Core/Models/Repo.swift` and `Core/Models/Worktree.swift` — verify unchanged

- [ ] **Step 2: Rewrite Section 1.1 Architecture Principles**
  - Remove principle 1's reference to `TerminalSession` — `Pane` is the primary entity, period
  - Remove principle 6 — `ViewDefinition` does not exist. There is no multi-view system.
  - Update principle 5 — leaves reference **pane IDs**, not session IDs

- [ ] **Step 3: Rewrite Section 1.2 System Diagram**
  - Replace `WorkspaceStore` box content: remove `repos`, `sessions`, `views`, `activeViewId`. Replace with accurate atom-wrapper description
  - Replace `ViewRegistry` box: remove `sessionId → NSView` and `renderTree()`. Replace with slot model (`paneId → PaneViewSlot`)
  - The diagram should show `AtomStore` → `WorkspaceStore` (wrapper) → four atoms

- [ ] **Step 4: Rewrite Section 2.1 Entity Relationship diagram**
  - Remove `TerminalSession` and `ViewDefinition` entirely
  - Replace with: `WorkspaceStore` → `Repo`, `Pane`, `Tab`
  - `Tab` → `Layout`, `Pane` (via activePaneId)
  - `Layout` leaf → `Pane` (via paneId)
  - `Pane` → optional `Worktree` (via worktreeId), optional `Repo` (via repoId)

- [ ] **Step 5: Rewrite Section 2.3 — rename from "TerminalSession" to "Pane"**
  - Document `Pane` with its actual fields from the source: `id`, `content` (PaneContent), `metadata` (PaneMetadata), `provider`, `kind` (PaneKind), `residency`, `worktreeId`, `repoId`, `parentPaneId`, `drawer`
  - Document `PaneContent` enum: `.terminal`, `.webview(WebviewPaneState)`, `.codeViewer(CodeViewerState)`, `.bridgePanel(BridgePaneState)`, `.unsupported`
  - Remove the "Session → Pane Identity Reconciliation" subsection entirely — the migration is complete, there is no reconciliation

- [ ] **Step 6: Delete Section 2.4 "ViewDefinition & ViewKind" entirely**
  - This model does not exist

- [ ] **Step 7: Rewrite Section 2.5 "Tab"**
  - Update fields to match actual `Tab`: `id`, `layout`, `activePaneId`, `activePaneIds` (derived), `allPaneIds` (derived), `arrangements`, `zoomedPaneId`, `minimizedPaneIds`
  - Remove `activeSessionId`, `sessionIds`, `isSplit`

- [ ] **Step 8: Rewrite Section 2.6 "Layout"**
  - Replace all `sessionId` references with `paneId` in the tree structure and operation descriptions
  - `.leaf(paneId: UUID)` not `.leaf(sessionId: UUID)`

- [ ] **Step 9: Update Section 2.7 "Templates"**
  - Replace `TerminalTemplate` → verify if this still exists or has been renamed. If it references `TerminalSession`, update to `Pane`.

- [ ] **Step 10: Commit**
  ```
  git add docs/architecture/component_architecture.md
  git commit -m "docs: hard-cut component_architecture data model to match pane-centric codebase"
  ```

---

### Task 2: Fix `component_architecture.md` — Service Layer (Section 3)

**Files:**
- Modify: `docs/architecture/component_architecture.md` (section 3, lines 266-700)
- Read for truth: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`, `Sources/AgentStudio/App/Panes/ViewRegistry.swift`, `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`, `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`, `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`, `Sources/AgentStudio/Core/Actions/ActionResolver.swift`

**What to change:**

- [ ] **Step 1: Read actual service files** from ux-fixes-3:
  - `WorkspaceStore.swift` — actual public API, atom wrapper pattern
  - `ViewRegistry.swift` — slot model API
  - `PaneCoordinator.swift` and all extensions — actual method signatures
  - `ActionResolver.swift` — what `WorkspaceCommandResolver` actually does (builds `ActionStateSnapshot`, not resolves commands)

- [ ] **Step 2: Rewrite Section 3.1 Ownership Hierarchy**
  - Add missing services: `AtomStore`, `repoCacheStore`, `uiStateStore`, `workspaceCacheCoordinator`, `appLifecycleStore`, `windowLifecycleStore`, `applicationLifecycleMonitor`, `managementLayerMonitor`
  - Update `CommandBarPanelController` constructor to include `repoCache: RepoCacheAtom`
  - List PaneCoordinator extensions: `+ActionExecution`, `+FilesystemSource`, `+RuntimeDispatch`, `+TerminalPlaceholders`, `+Undo`, `+ViewLifecycle`

- [ ] **Step 3: Rewrite Section 3.2 WorkspaceStore**
  - Remove `repos: [Repo]`, `sessions: [TerminalSession]`, `views: [ViewDefinition]`, `activeViewId`
  - Replace with: WorkspaceStore is a **persistence wrapper** over four atoms: `metadataAtom: WorkspaceMetadataAtom`, `repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom`, `paneAtom: WorkspacePaneAtom`, `tabLayoutAtom: WorkspaceTabLayoutAtom`
  - Update mutation API categories to match actual atom methods
  - Remove Session/View categories. Update Tab/Layout/Repo categories to match pane-centric naming.

- [ ] **Step 4: Rewrite Section 3.4 ViewRegistry**
  - Remove `renderTree(for: Layout) -> PaneSplitTree?` — does not exist
  - Document slot model: `ensureSlot(for:)`, `slot(for:) -> PaneViewSlot`, `register(_, for:)`, `unregister(_)`, `removeSlot(for:)`
  - Reference the slot model description already in `appkit_swiftui_architecture.md`

- [ ] **Step 5: Rewrite Section 3.5 Dynamic View Resolution**
  - Remove reference to `TerminalSplitContainer` — does not exist
  - Remove reference to `SplitContainerDropDelegate` — actual file is `SplitContainerDropCaptureOverlay`
  - Update component names to match actual files

- [ ] **Step 6: Rewrite Section 3.6 PaneCoordinator**
  - Update operation list to match actual methods
  - Remove `openTerminal(for:in:)` if it no longer exists — check actual API
  - Add `createViewForContentUsingCurrentGeometry` for deferred restore
  - Add terminal placeholder registration
  - Remove LUNA-325 expansion note if those features are now implemented

- [ ] **Step 7: Update Section 3.9.1 Persistence Segregation**
  - Remove references to `WorkspaceBootstrapCoordinator` and `SidebarRefreshCoordinator` — neither exists
  - Replace with: `WorkspaceBootSequence` at `App/Boot/WorkspaceBootSequence.swift` with `orderedSteps: [WorkspaceBootStep]`

- [ ] **Step 8: Update Section 3.10 SurfaceManager**
  - Replace `SurfaceMetadata.sessionId` with `SurfaceMetadata.paneId`

- [ ] **Step 9: Update Section 3.12 Command Bar System**
  - Add `.repos` scope (fourth scope with `"# "` prefix)
  - Update `CommandBarPanelController` init to include `repoCache: RepoCacheAtom`
  - Add `CommandBarWorktreeActionResolver` and `WorktreePresence` in the command bar components
  - Add `CommandBarAction.worktreeAction(presence:)` enum case

- [ ] **Step 10: Fix Section 3.8/3.9 Command Metadata flow**
  - Fix the `WorkspaceCommandResolver` description: it builds `ActionStateSnapshot`, not maps `AppCommand → PaneActionCommand`
  - Update the flow diagram accordingly

- [ ] **Step 11: Commit**
  ```
  git add docs/architecture/component_architecture.md
  git commit -m "docs: hard-cut component_architecture service layer to match current codebase"
  ```

---

### Task 3: Fix `component_architecture.md` — Data Flow, Invariants, Key Files (Sections 4-8)

**Files:**
- Modify: `docs/architecture/component_architecture.md` (sections 4-8, lines 700-end)
- Read for truth: actual source files for Key Files table verification

**What to change:**

- [ ] **Step 1: Rewrite Section 4.1 Mutation Pipeline**
  - Replace `sessionId` with `paneId` in `VR: ViewRegistry` column
  - Remove `sessionId` parameter references

- [ ] **Step 2: Rewrite Section 4.2 Restore Flow**
  - Remove `filter temporary sessions` step (sessions don't exist)
  - Update sequence to show actual restore: `store.restore()` → `paneCoordinator.restoreAllViews()` → geometry gating → deferred placeholder retry
  - Add the `WindowRestoreBridge` and deferred launch restore gate as part of the flow

- [ ] **Step 3: Delete Section 4.3 View Switch Flow**
  - View switching (ViewDefinition-based) does not exist. The workspace has tabs, not views.

- [ ] **Step 4: Update Section 4.4 Undo Close Flow**
  - Replace `session`/`sessions` with `pane`/`panes`
  - Replace `sessionId` with `paneId`

- [ ] **Step 5: Rewrite Section 6 Invariants**
  - Replace all 12 `TerminalSession` references with `Pane`
  - Remove invariant about "Session ID uniqueness" → "Pane ID uniqueness"
  - Remove invariant about `ViewDefinition.activeTabId` and `activeViewId` — views don't exist
  - Remove invariant about "Main view always exists" — views don't exist
  - Remove invariant about "Source is metadata" referencing `TerminalSource` — use `Pane.worktreeId`/`repoId`
  - Remove invariant about "Session independence" — rewrite for pane independence
  - Add invariant about drawer pane parentPaneId consistency

- [ ] **Step 6: Rewrite Section 7 Key Files table**
  - Remove: `Core/Models/TerminalSource.swift` → verify if still exists, update name
  - Remove: `Core/RuntimeEventSystem/Contracts/RuntimeCommandEnvelope.swift` — does not exist
  - Remove: `Core/RuntimeEventSystem/Contracts/PaneLifecycle.swift` — does not exist
  - Remove: `Core/RuntimeEventSystem/Contracts/ActionPolicy.swift` — does not exist
  - Add: `Core/Models/Pane.swift` — primary pane entity
  - Add: `Core/State/MainActor/Atoms/WorkspaceMetadataAtom.swift`
  - Add: `Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift`
  - Add: `Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
  - Add: `Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
  - Add: `Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift`
  - Add: `Core/State/MainActor/Atoms/WorkspaceFocusContextAtom.swift`
  - Add: `Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift`
  - Add: `Features/Terminal/Restore/TerminalRestoreScheduler.swift`
  - Update `VisibilityTier` entry: "p0/p1 — two tiers: visible and hidden" (not p0-p3)
  - Verify every file path in the table actually exists

- [ ] **Step 7: Commit**
  ```
  git add docs/architecture/component_architecture.md
  git commit -m "docs: hard-cut component_architecture data flow, invariants, and key files"
  ```

---

### Task 4: Fix `CLAUDE.md` — Architecture at a Glance and Project Structure

**Files:**
- Modify: `CLAUDE.md` (root)
- Read for truth: `Sources/AgentStudio/Core/State/MainActor/Atoms/`, `Sources/AgentStudio/Infrastructure/AtomLib/AtomStore.swift`, `Sources/AgentStudio/App/Coordination/PaneCoordinator*.swift`

**What to change:**

- [ ] **Step 1: Read `AtomStore.swift`** to get the canonical atom list

- [ ] **Step 2: Add `WorkspaceFocusContextAtom` to the atom table** in "Architecture at a Glance"
  - Add row: `WorkspaceFocusContextAtom | shared app-wide focus context for command visibility | Core/State/MainActor/Atoms/WorkspaceFocusContextAtom.swift`

- [ ] **Step 3: Fix `AppDelegate` path** in Project Structure section
  - Change `AppDelegate.swift` location from `App/` to `App/Boot/`

- [ ] **Step 4: Update Mutation Flow in README section**
  - Fix `WorkspaceCommandResolver → WorkspaceCommandValidator` to clarify the resolver builds `ActionStateSnapshot`, not maps commands

- [ ] **Step 5: Update Component → Slice Map**
  - Add `PaneCoordinator+ActionExecution` extension to the map
  - Verify all coordinator extensions are listed

- [ ] **Step 6: Fix CommandBar references**
  - If `CommandBarPanelController` init is referenced, add `repoCache:` param
  - Add `.repos` scope mention if command bar scopes are listed

- [ ] **Step 7: Fix VisibilityTier reference**
  - If p0-p3 is mentioned anywhere, change to p0/p1

- [ ] **Step 8: Commit**
  ```
  git add CLAUDE.md
  git commit -m "docs: fix CLAUDE.md atom table, paths, and mutation flow"
  ```

---

### Task 5: Fix `README.md` (Architecture Overview)

**Files:**
- Modify: `docs/architecture/README.md`

**What to change:**

- [ ] **Step 1: Fix mutation flow summary**
  - Clarify `WorkspaceCommandResolver` builds `ActionStateSnapshot`, not maps commands

- [ ] **Step 2: Remove dead type references**
  - If `WorkspaceBootstrapCoordinator` or `SidebarRefreshCoordinator` appear, remove them

- [ ] **Step 3: Verify Document Index table**
  - All doc descriptions should be accurate. Check that no doc description references deleted concepts.

- [ ] **Step 4: Commit**
  ```
  git add docs/architecture/README.md
  git commit -m "docs: fix README.md mutation flow and dead type references"
  ```

---

### Task 6: Fix `directory_structure.md`

**Files:**
- Modify: `docs/architecture/directory_structure.md`
- Read for truth: actual directory listing from ux-fixes-3

**What to change:**

- [ ] **Step 1: Fix stale component names in "Component Placement Decisions"**
  - Replace `SplitContainerDropDelegate` → `SplitContainerDropCaptureOverlay`
  - Remove `TerminalSplitContainer` reference — does not exist

- [ ] **Step 2: Verify Target Structure tree**
  - Compare against actual `Sources/AgentStudio/` tree
  - Add any missing subdirectories or key files
  - Add `Features/Terminal/Restore/` if missing
  - Add `App/Lifecycle/ManagementLayerMonitor.swift` and `ManagementLayerToolbarButton.swift` if applicable
  - Ensure `Infrastructure/CWDNormalizer.swift` is listed correctly

- [ ] **Step 3: Add flat tab strip components to Core/Views/Splits or Core/Models**
  - Mention `FlatTabStripMetrics`, `FlatTabStripContainer`, `FlatPaneStripContent`, `CollapsedPaneBar` if they are significant

- [ ] **Step 4: Commit**
  ```
  git add docs/architecture/directory_structure.md
  git commit -m "docs: fix directory_structure stale names and add missing components"
  ```

---

### Task 7: Fix `ghostty_surface_architecture.md`

**Files:**
- Modify: `docs/architecture/ghostty_surface_architecture.md`

**What to change:**

- [ ] **Step 1: Fix CWDNormalizer path**
  - Search for `Ghostty/CWDNormalizer.swift` and replace with `Infrastructure/CWDNormalizer.swift`
  - Fix both in prose and in the Files table at the bottom

- [ ] **Step 2: Fix TerminalPaneMountView init signature**
  - Add `paneId:` parameter to the example init call
  - Note that there are three initializers: worktree-bound, floating, and placeholder-only

- [ ] **Step 3: Commit**
  ```
  git add docs/architecture/ghostty_surface_architecture.md
  git commit -m "docs: fix surface architecture CWDNormalizer path and init signature"
  ```

---

### Task 8: Fix `appkit_swiftui_architecture.md`

**Files:**
- Modify: `docs/architecture/appkit_swiftui_architecture.md`

**What to change:**

- [ ] **Step 1: Update Ownership Hierarchy**
  - Add missing services: `AtomStore`, `repoCacheStore`, `uiStateStore`, `workspaceCacheCoordinator`, `appLifecycleStore`, `windowLifecycleStore`, `applicationLifecycleMonitor`, `managementLayerMonitor`

- [ ] **Step 2: Update Command Bar section**
  - Add repos scope (`# ` prefix, `⌘⌥⇧P` or however it's triggered) to the keyboard shortcuts table
  - Update `CommandBarPanelController` to note `repoCache:` constructor param
  - Add `CommandBarWorktreeActionResolver`, `WorktreePresence` to key components table
  - Add new views: `CommandBarBackRow`, `CommandBarScopePill`, `CommandBarStatusStrip`, `CommandBarSearchField`, `CommandBarFooter`

- [ ] **Step 3: Add Management Layer section**
  - Brief description of `ManagementLayerMonitor` at `App/Lifecycle/ManagementLayerMonitor.swift`
  - `ManagementLayerToolbarButton` for toolbar integration
  - `ManagementLayerAtom` for state

- [ ] **Step 4: Commit**
  ```
  git add docs/architecture/appkit_swiftui_architecture.md
  git commit -m "docs: update appkit_swiftui with ownership hierarchy, repos scope, management layer"
  ```

---

### Task 9: Fix `pane_runtime_architecture.md` and `pane_runtime_eventbus_design.md`

**Files:**
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`

**What to change:**

- [ ] **Step 1: Fix VisibilityTier in pane_runtime_architecture.md**
  - Search for "p0→p3" or "p0-p3" and replace with "p0/p1 (visible/hidden)"
  - Note that only two tiers are implemented, not four

- [ ] **Step 2: Remove phantom files from pane_runtime_architecture.md Key Files**
  - Remove: `RuntimeCommandEnvelope.swift` — does not exist
  - Remove: `PaneLifecycle.swift` — does not exist
  - Remove: `ActionPolicy.swift` — does not exist
  - Add: `PaneRuntimeEventChannel.swift`
  - Add: `SwiftPaneRuntime.swift`
  - Add: `WorkspaceActivityEvent.swift`

- [ ] **Step 3: Fix VisibilityTier in pane_runtime_eventbus_design.md**
  - Same p0-p3 → p0/p1 fix
  - Mention `PaneFilesystemProjectionStore` and `EventChannels` if relevant

- [ ] **Step 4: Commit**
  ```
  git add docs/architecture/pane_runtime_architecture.md docs/architecture/pane_runtime_eventbus_design.md
  git commit -m "docs: fix VisibilityTier claims and remove phantom files from runtime docs"
  ```

---

### Task 10: Fix `workspace_data_architecture.md`

**Files:**
- Modify: `docs/architecture/workspace_data_architecture.md`

**What to change:**

- [ ] **Step 1: Remove dead coordinator references**
  - Search for `WorkspaceBootstrapCoordinator` and `SidebarRefreshCoordinator` — remove both
  - Replace with: `WorkspaceBootSequence` with `orderedSteps` at `App/Boot/WorkspaceBootSequence.swift`

- [ ] **Step 2: Add deferred launch restore flow** as a new subsection under "Lifecycle Flows — App Boot"
  - `WindowLifecycleStore.isReadyForLaunchRestore` drives `finishLaunchRestore(using:source:)`
  - `WindowRestoreBridge` (AsyncStream-based) at `App/Lifecycle/WindowRestoreBridge.swift`
  - Geometry gating: `terminalContainerBounds` must be non-empty before zmx surface creation
  - Terminal placeholder modes (`.preparing` / `.failedToStart`) at `Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift`
  - Retry mechanism: `restoreViewsForActiveTabIfNeeded()` fires when `PaneTabViewController.terminalContainerBoundsChanged()`
  - `TerminalRestoreScheduler` orders panes by visibility tier (p0Visible first, then p1Hidden)
  - `BackgroundRestorePolicy` controls whether hidden zmx panes are restored

- [ ] **Step 3: Commit**
  ```
  git add docs/architecture/workspace_data_architecture.md
  git commit -m "docs: fix workspace_data dead coordinators, add deferred launch restore flow"
  ```

---

### Task 11: Final verification pass

- [ ] **Step 1: Grep all docs for "TerminalSession"**
  - Any remaining occurrence (except in quotes referring to historical context) should be replaced with `Pane`

- [ ] **Step 2: Grep all docs for "ViewDefinition"**
  - Remove all references

- [ ] **Step 3: Grep all docs for "sessionId" in model context**
  - Replace with `paneId` where referring to the primary identity

- [ ] **Step 4: Grep all docs for "p0→p3" or "p0-p3"**
  - Replace with "p0/p1"

- [ ] **Step 5: Grep all docs for "CWDNormalizer" and verify path**
  - Should all point to `Infrastructure/CWDNormalizer.swift`

- [ ] **Step 6: Grep all docs for "WorkspaceBootstrapCoordinator" and "SidebarRefreshCoordinator"**
  - Should be zero results

- [ ] **Step 7: Commit any remaining fixes**
  ```
  git add docs/
  git commit -m "docs: sweep remaining stale references across all architecture docs"
  ```
