# Command Context and Command Surface Restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` or `superpowers:executing-plans` to
> implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** Complete the hard semantic cutover from the combined pane-focus
projection and implicit command exposure rules to separate focused-pane and
command-context projections plus explicit, typed command surfaces and
targeting.

**Architecture:** `WorkspaceFocusedPaneResolver` owns pure normalization and
focused-pane identity. `CommandContextDerived` projects that value together
with tab, drawer, arrangement, and Zoom facts into immutable command policy.
Every `AppCommandSpec` explicitly declares interactive surface exposure and
targeting, and each interactive consumer asks the same pure presentation query
before using the existing dispatcher for capability and execution.

**Tech Stack:** Swift 6.2, Swift Testing, AppKit, SwiftUI, Observation,
AgentStudioCore, AgentStudioCommandBar, AgentStudio app composition.

## Global Constraints

- Preserve all accepted post-Pane-Zoom labels, icons, shortcuts, grouping,
  placement, selected state, disabled state, targeting behavior, and IPC
  behavior.
- Perform one hard cutover. Do not retain `WorkspacePaneFocus`,
  `WorkspacePaneFocusDerived`, `FocusRequirement`, `isHiddenInCommandBar`,
  `appliesTo`, or `isTargetableCommand`.
- Keep `WorkspaceFocusOwnerAtom` as the only mutable workspace-focus owner.
- Do not introduce mutable command-context or command-surface state.
- Keep visibility, capability, keyboard routing, targeting, mutation
  validation, and IPC authorization orthogonal.
- Keep public IPC DTOs, privileges, execution modes, argument schemas, and
  durable-handle authorization unchanged.
- Keep BridgeWeb, Pane Zoom lifecycle, retained Viewer lifecycle, and
  runtime-command ownership unchanged.
- Interactive hosts continue to own ordering, grouping, spacing, selected
  state, and control construction.
- Use focused tests first, then full applicable command/IPC suites, formatting,
  lint, full tests, and native debug proof.

---

### Task 1: Split Focus Resolution from Command Context

**Files:**

- Create:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusedPane.swift`
- Create:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusedPaneResolver.swift`
- Create:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/CommandContext.swift`
- Create:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/CommandContextDerived.swift`
- Modify:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/CoreAtoms.swift`
- Delete:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift`
- Delete:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift`
- Create:
  `Tests/AgentStudioTests/Core/Views/WorkspaceFocusedPaneResolverTests.swift`
- Create:
  `Tests/AgentStudioTests/Core/Views/CommandContextDerivedTests.swift`
- Delete:
  `Tests/AgentStudioTests/Core/Views/WorkspacePaneFocusDerivedTests.swift`

**Interfaces:**

- Produces `CommandRequirement: Hashable, CaseIterable, Sendable`.
- Produces `WorkspaceFocusedPane: Equatable, Sendable` with normalized owner,
  active main-pane identity, focused pane/repo/worktree identity, content
  classification, and status-strip presentation projection.
- Produces
  `WorkspaceFocusedPaneResolver.resolve(activeTab:workspacePane:requestedOwner:)`
  as a stateless pure resolver.
- Produces `CommandContext: Equatable, Sendable` with active tab and focused
  entity identities plus normalized satisfied requirements.
- Produces
  `CommandContextDerived.currentContext(workspaceTab:workspacePane:focusedPane:workspacePanePresentation:)`.

- [ ] **Step 1: Add resolver characterization tests**

  Cover no active pane, main pane, empty drawer, valid drawer child, collapsed
  drawer, mismatched parent, stale/minimized child fallback, and focused-child
  repo/worktree/content identity.

- [ ] **Step 2: Run the resolver tests and verify red**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter WorkspaceFocusedPaneResolverTests
  ```

  Expected: failure because the new resolver and value do not exist.

- [ ] **Step 3: Implement the focused-pane value and resolver**

  Reuse `WorkspaceFocusOwnerNormalizer` as the normalization primitive. Keep
  mutable focus state in `WorkspaceFocusOwnerAtom`; the resolver only composes
  normalized owner and canonical pane identity.

- [ ] **Step 4: Add command-context projection tests**

  Cover empty workspace, pane/tab counts, drawer requirements, mutually
  exclusive content requirements, terminal Zoom, stale/non-terminal Zoom
  source, and terminal Zoom while a non-terminal drawer child owns focus.

- [ ] **Step 5: Run the context tests and verify red**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter CommandContextDerivedTests
  ```

  Expected: failure because `CommandContextDerived` does not exist.

- [ ] **Step 6: Implement immutable command-context projection**

  Move display labels/icons out of command context. Preserve
  `supportsTerminalZoom` and `hasActiveTerminalZoom` semantics without deriving
  the latter from focused content.

- [ ] **Step 7: Replace Core atom accessors and remove old types**

  Add `workspaceFocusedPane` and `commandContext` derived accessors to
  `CoreAtoms`; delete the old combined projection files and tests.

- [ ] **Step 8: Run the focused Task 1 suites**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter 'WorkspaceFocusedPaneResolverTests|CommandContextDerivedTests|WorkspaceFocusOwnerAtomTests'
  ```

  Expected: all selected tests pass.

### Task 2: Add Typed Surface, Targeting, and Presentation Policy

**Files:**

- Modify:
  `Sources/AgentStudio/Core/Actions/Commands/AppCommand.swift`
- Create:
  `Sources/AgentStudio/Core/Actions/Commands/AppCommandPresentationPolicy.swift`
- Modify:
  `Sources/AgentStudio/Core/Actions/Commands/AppCommand+Catalog.swift`
- Modify:
  `Sources/AgentStudio/Core/Actions/Commands/AppCommand+CatalogHelpers.swift`
- Modify:
  `Tests/AgentStudioTests/App/AppCommandSpecContractTests.swift`
- Create:
  `Tests/AgentStudioTests/Core/Actions/AppCommandPresentationPolicyTests.swift`

**Interfaces:**

- Produces `AppCommandSurface`, `AppCommandToolbarSurface`,
  `AppCommandSurfacePolicy`, `AppCommandTargeting`,
  `AppCommandPreferredInvocation`, `AppCommandPresentationSubject`, and
  `AppCommandPresentationQuery` exactly as specified.
- `SearchItemType` becomes `Hashable` and `Sendable`.
- `AppCommandSpec` requires `surfacePolicy` and `targeting`; no defaults exist.
- `AppCommandSpec.shouldPresent(_:)` is the only shared interactive
  presentation decision.

- [ ] **Step 1: Add pure policy table tests**

  Test unsupported surfaces, contextual requirements, target kinds,
  contextual-target conjunction, `.notPresented`, empty exposed/targeted-set
  rejection, and mutually exclusive content requirements.

- [ ] **Step 2: Run the policy tests and verify red**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter AppCommandPresentationPolicyTests
  ```

  Expected: failure because the policy types do not exist.

- [ ] **Step 3: Implement the policy types and pure query**

  Keep presentation queries identity-only: no target UUID, store, atom,
  dispatcher, or authorization result.

- [ ] **Step 4: Inventory every post-Zoom command**

  Record an explicit surface and targeting policy for every `AppCommand` in the
  exhaustive catalog. Preserve current command-bar inclusion, AppKit menu
  presence, context-menu/inline control presence, pane toolbar presence,
  terminal-Zoom toolbar presence, contextual dispatch, and target drill-in.
  Use `.notPresented` for shortcut-only, IPC-only, generated-row, and internal
  identities.

- [ ] **Step 5: Replace legacy catalog fields**

  Remove `isHiddenInCommandBar` and `appliesTo`. Do not add compatibility
  computed properties or permissive initializer defaults.

- [ ] **Step 6: Add catalog structural tests**

  Prove every command has exactly one spec; every spec has valid explicit
  policies; every shortcut maps to its spec; `.exposed` and targeted sets are
  non-empty; and no old vocabulary remains.

- [ ] **Step 7: Run policy and catalog suites**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter 'AppCommandPresentationPolicyTests|CommandSpecContractTests|AppCommandCatalogTests|AppCommandTests'
  ```

  Expected: all selected tests pass.

### Task 3: Cut Over Command Bar, Dispatcher, and IPC Projection

**Files:**

- Modify:
  `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify:
  `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+RootProjection.swift`
- Modify:
  `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+QuickOpen.swift`
- Modify:
  `Sources/AgentStudio/Features/CommandBar/CommandBarResultSession.swift`
- Modify:
  `Sources/AgentStudio/Features/CommandBar/Models/CommandBarResultSnapshot.swift`
- Modify:
  `Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift`
- Modify:
  `Sources/AgentStudio/App/Commands/AppCommandDispatcher.swift`
- Modify:
  `Sources/AgentStudio/App/Commands/AppCommand+IPCProjection.swift`
- Modify:
  `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
- Modify affected command-bar and IPC tests under
  `Tests/AgentStudioTests/Features/CommandBar/` and
  `Tests/AgentStudioTests/App/`.

**Interfaces:**

- Command Bar requests `.commandBar` contextual presentation.
- Root-row direct dispatch versus drill-in comes only from
  `AppCommandTargeting.preferredInvocation`.
- Target builders use the declared target kinds.
- Dispatcher contextual and targeted entry points reject undeclared modes
  before calling execution owners.
- IPC target-kind projection remains independently declared by `ipcExposure`;
  interactive targeting must not derive, widen, or narrow accepted public IPC
  metadata.

- [ ] **Step 1: Add command-bar targeting and presentation failures**

  Prove direct contextual dispatch, target-selection drill-in, targeted-only
  drill-in, unsupported target omission, and status-strip use of
  `WorkspaceFocusedPane`.

- [ ] **Step 2: Replace Command Bar legacy visibility and targetability logic**

  Delete `isTargetableCommand`; use `shouldPresent` and `AppCommandTargeting`
  for root rows and generated targets.

- [ ] **Step 3: Add dispatcher mode-preflight tests**

  Prove unsupported contextual and targeted requests never reach shell or
  workspace handlers.

- [ ] **Step 4: Implement dispatcher targeting preflight**

  Retain management-layer and execution-owner `canExecute` checks after the
  declaration-level mode check.

- [ ] **Step 5: Preserve IPC metadata through the new policy**

  Keep execution modes, privileges, argument schemas, target handles, durable
  authorization, and public DTO shape unchanged. Prove the synchronized
  projection from `AppCommand.allCases -> AppCommandSpec ->
  IPCCommandListEntry` while keeping `AppCommand.ipcSpec` independent from
  interactive surface and targeting policy. Replace internal empty-array
  sentinels and default switch branches with exhaustive
  `AppCommandIPCExposure`, `AppCommandIPCDurableTargetContract`, and
  `AppCommandIPCArgumentContract` discriminated unions; decode into a
  non-optional `AppCommandExecutionArguments` union and project back to the
  unchanged public DTO arrays.

- [ ] **Step 6: Run command-bar and IPC suites**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter 'CommandBar|AppCommandDispatcher|AgentStudioIPCCommandAdapter|AgentStudioAppIPCServiceCommand|IPCContracts'
  ```

  Expected: all selected tests pass.

### Task 4: Converge Menus, Toolbars, Context Menus, and Inline Controls

**Files:**

- Modify:
  `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Modify:
  `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- Modify:
  `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify:
  `Sources/AgentStudio/Core/Views/Panes/PaneSurfaceToolbarPresentation.swift`
- Modify current command-backed menu/control consumers under:
  `Sources/AgentStudio/App/Panes/`,
  `Sources/AgentStudio/Core/Views/`,
  `Sources/AgentStudio/Features/RepoExplorer/`, and
  `Sources/AgentStudio/Features/InboxNotification/`.
- Modify focused AppKit menu, toolbar, context-menu, and inline-control tests.

**Interfaces:**

- AppKit menu validation requests `.mainMenu` contextual presentation, then
  asks the dispatcher for enablement.
- Context menus request `.contextMenu` with their typed target kind.
- App/titlebar controls request `.toolbar(.app)` or `.inlineControl`.
- Normal pane toolbars request `.toolbar(.pane)` with `.targeted(.pane)`.
- Terminal Zoom requests `.toolbar(.terminalZoom)` with `.targeted(.pane)`.
- Physical pane controls do not apply the globally focused
  `CommandContext`; `contextualTarget` is reserved for targets that describe
  the same presentation subject as that context.
- Tooltip presentation remains
  `AppCommandSpec -> CommandDisplayDescriptor -> ControlTooltipSource ->
  ControlTooltipRenderValue`.

- [ ] **Step 1: Add consumer agreement tests**

  Prove command bar and main menu agree on context; context menus reject
  undeclared kinds; and app, pane, and terminal-Zoom toolbar surfaces remain
  distinct.

- [ ] **Step 2: Cut over AppKit menu validation**

  Hide commands failing `.mainMenu` presentation; preserve `canDispatch` as
  enablement.

- [ ] **Step 3: Cut over pane and Zoom toolbar construction**

  Filter action construction through the exact toolbar surface and
  targeted-pane query. Preserve Viewer capability resolution and selected
  state. Do not apply globally focused context to a control attached to a
  different physical pane.

- [ ] **Step 4: Cut over context menus and command-backed inline controls**

  Retain explicit host ordering and callbacks. Use `LocalActionSpec` for
  controls that are not app commands.

  Make the tab context menu an honest targeted consumer before applying its
  presentation filter:

  - declare and implement real `.tab` targeting for split-left, split-right,
    equalize-panes, save-arrangement, and new-floating-terminal;
  - resolve target-pane and launch-directory inputs from the clicked tab inside
    the execution owner;
  - request `.contextMenu` with `.targeted(.tab)` so active-tab
    `CommandContext` requirements cannot hide valid commands for an inactive
    clicked tab;
  - use targeted `canDispatch` and targeted dispatch for every command row;
  - replace command-labelled no-op arrangement rows with one functional local
    action that opens the arrangement panel;
  - use a `LocalActionSpec` for the split-command submenu title instead of
    borrowing a command label;
  - query the exact physical surface for every arrangement placement: Switch,
    panel Save, rename pencil, and double-click Rename use `.inlineControl`;
    arrangement-chip right-click Rename/Delete and tab-menu Save use
    `.contextMenu`;
  - resolve inline and right-click placements independently, then converge on
    the same targeted capability and dispatch path;
  - preserve IPC exposure independently from all interactive targeting
    changes.

  Add red/green tests proving active-unsplit/clicked-split and
  active-split/clicked-unsplit presentation, inactive-tab targeting,
  invalid/stale-tab rejection, the absence of dead command rows, exact
  arrangement inline/right-click targeting, capability recheck on activation,
  clicked-tab CWD/nil fallback, and zero IPC metadata change.

- [ ] **Step 5: Run focused consumer suites**

  Run:

  ```bash
  SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test -- --filter 'Menu|Toolbar|RepoExplorerWorktreeRow|InboxSidebarToolbar|PaneInboxNotificationPopover|CollapsedPaneBar|ArrangementPanel'
  ```

  Expected: all selected tests pass.

### Task 5: Remove Stale Vocabulary, Update Documentation, and Prove the Cutover

**Files:**

- Modify:
  `docs/architecture/commands/command_specs.md`
- Modify:
  `docs/architecture/structure/component_architecture.md`
- Modify:
  `docs/architecture/README.md`
- Modify:
  `AGENTS.md`
- Modify:
  `docs/specs/2026-07-27-command-context-surface-restoration/2026-07-27-command-context-surface-restoration.md`
- Modify architecture/static tests as required by the final module placement.

- [ ] **Step 1: Remove every stale source/test/document reference**

  Run:

  ```bash
  rg -n 'WorkspacePaneFocus|WorkspacePaneFocusDerived|FocusRequirement|isHiddenInCommandBar|isTargetableCommand|\\.appliesTo' Sources Tests docs/architecture AGENTS.md
  ```

  Expected: no matches.

- [ ] **Step 2: Update architecture ownership and consumer contracts**

  Document focused-pane resolution, command-context projection, typed surface
  exposure, targeting, presentation queries, dispatcher preflight, and
  unchanged IPC/keyboard boundaries. Mark the spec implemented only after all
  proof gates pass.

- [ ] **Step 3: Format and lint**

  Run:

  ```bash
  mise run format
  mise run lint
  ```

  Expected: exit 0; SwiftLint reports zero violations.

- [ ] **Step 4: Run the full test suite**

  Run:

  ```bash
  SWIFT_TEST_TIMEOUT_SECONDS=240 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=240 mise run test
  ```

  Expected: exit 0 with all default Swift and serialized WebKit lanes passing.

- [ ] **Step 5: Run native debug characterization**

  Run the repository-standard debug app through the observability launcher.
  Verify unchanged command bar, main menu, shortcuts, context menus, normal
  pane toolbar, and terminal-Zoom toolbar with PID-targeted Peekaboo in
  background mode.

- [ ] **Step 6: Review final diff against every spec requirement**

  Confirm R1-R23, proof expectations, security invariants, non-goals, and the
  acceptance boundary. Do not claim completion if any higher proof layer was
  skipped.
