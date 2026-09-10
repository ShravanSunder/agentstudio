# Astra independent app-only review — inventory and candidate findings

> Historical evidence. The current execution tree is [App-only reliability wrap-up](../2026-09-08-app-only-reliability-wrapup.md). Superseded specs/plans mentioned below have been removed; do not execute their old instructions.

Review identity: fresh no-fork reviewer, candidate-only; parent must verify findings. Initial review is read-only. User subsequently authorized only this audit document as a write surface. No builds, tests, setup, vendor edits, fetch, cleanup or Git mutations were performed.

Snapshot: HEAD `293cc48c7f57c3835bfb42b467eafc71355eaa67`; local `origin/main` `6cbbee4a4422c25b10c1bcf1c6a511f5393a0b0c`. 183 committed-range files plus 30 unstaged files, union 186 tracked changed files; 21 initial untracked entries (including one suspiciously named artifact). No staged changes. Both `git diff HEAD -- vendor` and `git diff origin/main -- vendor` are empty. This proves current tracked vendor diffs only, not historical build provenance.

Authority: user's app-only boundary supersedes stale vendor prescriptions in the September 7 Requirements/Specification/Program Design and ignored implementation plan. No new implementation authority is inferred from those documents. Preserve pane/visibility/atom/async corrections; exclude agentstudio-git review-comment work.

## Result and boundaries

**Candidate findings; not ready.** Every initial file is accounted for below. Current app source and test semantic changes were inspected, including cross-file move accounting. Historical unrelated WIP documents are explicitly excluded from re-validating their old source/proof claims; their dates, branch identities, complete section inventories, boundaries and relevance were inspected. That is an inventory classification, not an independent rerun of every prior investigation. Historical vendor prototypes are obsolete under current authority. No source/test/config/vendor file was changed during this review.

The canonical implementation plan remains stale: it prescribes vendor begin/drain/finalize APIs and a zmx existing-only option. Therefore formal implementation acceptance against that unchanged ready plan is blocked-input. The user's direct audit request still authorizes this current-source inventory and candidate report. No remediation count was invented from missing old receipts.

### F1 — P1: pending terminal cleanup never executes

**Trigger:** expire/evict the last available Undo owner, permanently discard the last pane, or reopen a database with an already-pending session.

**Source chain:** `WorkspaceCoreRepository+SessionOwnership.swift:79–114` marks sessions pending only after both live and available-Undo ownership disappear. `WorkspaceSQLiteDatastore+UndoJournal.swift:44–47` returns pending IDs. `WorkspaceSurfaceCoordinator.swift:406–409` installs only available-close projections and native-pane retirements, ignoring pending IDs; `:421–426` releases native surfaces/slots only. Repository-wide search finds `pendingSessionIDs` only in its DTO and return construction. `process_identity`, `last_cleanup_error`, and `cleanup_completed_at` occur only in schema/guards/pruning, with no production writer that records an identity, attempt failure or completed cleanup.

**Consequence:** SQLite says pending while the zmx command can keep running indefinitely; restart still does not execute cleanup. Every associated historical operation remains exempt from pruning (`WorkspaceCoreRepository+UndoPruning.swift:18–27`), so the promised completed-history bound cannot settle for those sessions. This is an absent end-to-end behavior, not a criticism of safely retaining uncertain work.

**Owner/minimal correction:** existing App lifecycle composition and existing Core journal/ZmxBackend boundary must gain the approved app-only cleanup flow. Do not simply call the current blind name-based destroy: `ZmxBackend.swift:302–313` uses CLI `kill <name>` and accepts command success without incarnation/group verification; `:227` is the same shape for handle destruction. Establish exact identity, ownership revalidation, safe retry and completion evidence through existing vendor capabilities before enabling it. No vendor modifications are authorized.

**Proof:** existing SQL/coordinator tests prove pending admission and shared-owner protection, not process termination. A real isolated zmx process/group journey with restart, replacement/unknown identity and deliberately detached service must distinguish successful completion from a still-live original group. Historical `after-first-expiry-sessions.json` contains a pending ownership row and three discovered sessions; this supports the gap, but is not a current live probe.

### F2 — P2: renderer sampler overcounts classes by substring

`scripts/verify-renderer-population.sh:182–184` sums every numeric heap row containing the class name anywhere. Historical `app-boundary-proof/rebuilt-baseline/heap.txt:2480` contains one actual `PaneHostView`; `:3169` contains one `Swift.ReferenceWritableKeyPath<...PaneHostView>` instance. The sampler counts both as hosts. The duplicate-mount investigation explicitly records this correction. Thus a correct one-host population becomes two and can falsely support a retention/leak conclusion. Match the actual class column/name and add a parser fixture containing both rows. The existing parser tests do not cover heap class counting.

### F3 — P2 documentation defect: current architecture describes removed ownership

`docs/architecture/runtime/ghostty_surface_architecture.md:108` still attributes freed emission to SurfaceView deinit; its close/Undo diagrams retain per-surface expiration tasks and manager TTL. Current code uses explicit `retireNativeSurface`, no SurfaceUndoEntry expiration task, and the durable journal owns deadlines. `session_lifecycle.md` still describes metadata matching after lookup; current manager uses most-recent attachment. The September 7 requirements/program-design/plan additionally authorize or require vendor work now prohibited by the user. Correct these documents before a new executor consumes them. Preserve the useful visibility/focus sections and historical evidence; do not convert stale design into permission.

### Native retirement — material risk remains, no invented fix authority

`GhosttySurfaceView.swift:487–513` clears its handle/callbacks, removes the layer, and invokes existing `ghostty_surface_free` at `:505` synchronously on MainActor while keeping the App alive. `SurfaceManager.swift:513–549` explicitly calls this despite externally retained NSViews and prevents duplicate manager removal. This is app-only and addresses the old ARC-only release failure.

The exact current primary Ghostty pin still synchronously joins search/renderer/I/O threads (`vendor/ghostty/src/Surface.zig:776–802`) and waits for GPU permits (`renderer/generic.zig:276–283`). Its `IOSurfaceLayer.release:43` only releases the layer, while `metal.zig:165–176` installs a raw renderer context used by `display`. A separately retained layer is not shown to have its callback cleared merely by app-side detachment. A late display invocation would dereference freed renderer storage. Current native safety evidence does not establish that such callbacks are impossible after detachment, or bound shutdown under a resistant child/GPU workload. This is a supported risk requiring decisive proof, not a claim that a crash was reproduced in this review.

DeepWiki was used for source pointers; its callback-clearing claim did not match the exact pinned source and was rejected. Do not solve the uncertainty with unauthorized vendor edits or moving unsupported native free onto a detached executor. Two historical free records took 18.224 ms and 21.307 ms; they establish neither a nonblocking contract nor worst-case responsiveness.

### Candidate rejected after tracing invariants

Shared-pane restore overlap initially appeared suspicious: close computes remaining references, while restore rejects overlap with existing pane IDs. Current `WorkspaceCompositionPreparation.swift:300–326` and `WorkspaceCoreRepository+TabGraphValidation.swift:78–89` reject a pane belonging to multiple tabs. Therefore this is not a supported valid-composition bug. Shared **session** IDs across different pane IDs remain supported and are covered by durable owner tests.

## Coverage ledger

Every initial changed/untracked file is listed below. “Inspected” means source/diff inspection, never a passing-test claim. Pending files are not approved. Keep candidate means potentially retain after full review/proof, not acceptance.

| File | Origin | Classification / coverage |
| --- | --- | --- |
| `.mise.toml` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Boot/AppDelegate+MainWindowCreation.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Boot/AppDelegate+PaneAssociationStartupDiagnostics.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Boot/AppDelegate+RepoExplorerKeyMutationStartupDiagnostics.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Boot/AppDelegate+StartupDiagnostics.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Boot/AppDelegate.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Commands/WorkspaceActionExecutor.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActionExecution.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgeMetadataRepair.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgePaneActivity.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+PaneInsertion.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+RendererVisibility.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+TerminalPlaceholders.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+Undo.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+UndoDeadline.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewHelpers.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift` | tracked delta | keep durable-owner candidate; incomplete end-to-end cleanup (F1) |
| `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCLayoutAdapter.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/App/Windows/RepoExplorerCommandPresentationBatch.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/TabLayoutRules/TabArrangementMutationRules.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/WindowLifecycleAtom.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabGraphAtom.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabShellAtom.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceMutationCoordinator.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspacePaneDiscardComposition.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceTerminalCreationComposition.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceUndoComposition.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Coordination/WorkspaceUndoRestoreComposition.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations+SessionOwnership.swift` | tracked delta | keep durable-owner candidate; incomplete end-to-end cleanup (F1) |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+SessionOwnership.swift` | tracked delta | keep durable-owner candidate; incomplete end-to-end cleanup (F1) |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+UndoClose.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+UndoPruning.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+UndoRecovery.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+UndoRestore.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteSaveCoordinator.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceUndoCloseRecord.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceUndoCloseSnapshot.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceUndoCloseWrite.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceUndoJournalClock.swift` | tracked delta | keep durable-owner candidate; incomplete end-to-end cleanup (F1) |
| `Sources/AgentStudio/Core/State/SQLite/RepositoryTopologySQLiteSnapshot.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/SQLite/WorkspaceCompositionRevision.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore+PersistenceOrder.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore+UndoJournal.swift` | tracked delta | keep durable-owner candidate; incomplete end-to-end cleanup (F1) |
| `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastoreTypes.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Core/Views/Panes/PaneMountedContent.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/InboxNotification/Routing/PaneFocusTracker.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionAdapter+InputLifecycle.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift` | tracked delta | app-only keep candidate; native callback/responsiveness proof unverified |
| `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager+RendererState.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceRendererStateDelivery.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceTypes.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Features/Terminal/Routing/TerminalActivityRouter.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/AppPolicies.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection+ControlledStrings.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder+RendererLifecycle.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/RendererLifecycleOTLPProjectionKeys.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudio/Infrastructure/Diagnostics/RendererLifecyclePerformanceState.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Sources/AgentStudioAppIPC/AgentStudioAppIPCService.swift` | tracked delta | keep candidate; source/diff inspected; required current proof unverified |
| `Tests/AgentStudioTests/App/AgentStudioStartupDiagnosticActionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/AppCommandDispatcherModePreflightTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorFilesystemEffectsTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorFilesystemSourceTestSupport.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorFilesystemSourceTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorRestoreMutationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/IPC/AgentStudioIPCLayoutAdapterTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Lifecycle/WindowLifecycleAtomTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTestSupport.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests+Management.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/PaneTabViewControllerEditorChooserCommandTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Panes/DrawerCommandIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Panes/PaneCloseTransitionCoordinatorTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/State/WorkspaceSQLiteStoreBridgeRepairTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/TestSupport/MockCommandHandler.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/TestSupport/WorkspaceSQLiteTestFixtures.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerTestSupport.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Windows/MainWindowControllerPresentationFactsTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Windows/RepoExplorerCommandPresentationBatchCoalescingTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/Windows/RepoExplorerCommandPresentationBatchTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceActionExecutorTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceActionExecutorTests_Quick.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceCommandGestureOrderingTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspacePaneAssociationCreationPathTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceProjectedDividerResizeIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorArrangementSwitchHostTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneActivityIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneActivityRemediationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgePaneActivityTestSupport.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorCWDIdentityTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorCrossTabMoveTransitionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorDrawerRestoreIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorDrawerUndoTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorDurableUndoTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorEntityRecencyTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorGeometryReevaluationIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorHardeningTests+Restoration.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorHardeningTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorPullRequestDemandTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorRendererVisibilityIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorRendererVisibilityTests.swift` | tracked delta | keep candidate; stale omitted-retention-test comment remains despite present test |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorRuntimeDispatchNonTerminalTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorRuntimeDispatchTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorSlotLifecycleTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTabNamingTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTerminalRestoreIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTerminalRestoreTestSupport.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTopologyTraceTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorUndoRestoreTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorZoomLifecycleTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorZoomLifecycleTransitionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorZoomOwnershipTransitionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorZoomRuntimeDispatchTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceTerminalCreationDurabilityTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceUndoDeadlineIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Architecture/SurfaceManagerHotPathArchitectureTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusHarnessTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusWaitForFirstTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/PaneRuntime/Runtime/PaneRuntimeEventChannelTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorActivityTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorVisibleTierTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreMigrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceSessionOwnershipSchemaTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceTerminalOwnershipAdmissionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoCaptureOrderingTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoClosePersistenceTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoCloseRecoveryTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoCloseRestoreTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoCloseSnapshotTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoCompositionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoDatastoreTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoHistoryPruningTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoJournalClockTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoRestoreCompositionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoStartupRecoveryTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Core/Stores/WorkspaceUndoStorePublicationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/InboxNotification/Routing/InboxNotificationRouterObservedPaneTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/InboxNotification/Routing/PaneFocusTrackerTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceViewLifecycleTests.swift` | tracked delta | keep candidate as no-native-handle seam proof only; native behavior unverified |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/SurfaceManagerRendererStateDeliveryTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/SurfaceTypesTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/Restore/StoreVisibilityTierResolverTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeObservationRetentionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/State/TerminalActivityRouterAttentionTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Helpers/GitEventPipelineHarness.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorderTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Infrastructure/Diagnostics/RendererLifecycleOTLPTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Integration/TopologyEventPipelineIntegrationTests.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Scripts/RendererPopulationScriptTests.swift` | tracked delta | keep candidate; missing heap class fixture (F2) |
| `Tests/AgentStudioTests/TestSupport/EventBusHarness.swift` | tracked delta | keep candidate; semantic diff/test boundary inspected; not executed |
| `docs/architecture/runtime/ghostty_surface_architecture.md` | tracked delta | keep visibility/host documentation; obsolete lifetime/Undo portions require correction (F3) |
| `docs/architecture/runtime/session_lifecycle.md` | tracked delta | keep visibility/host documentation; obsolete lifetime/Undo portions require correction (F3) |
| `docs/architecture/structure/component_architecture.md` | tracked delta | keep visibility/host documentation; obsolete lifetime/Undo portions require correction (F3) |
| `docs/specs/2026-09-07-pane-session-reliability/program-design.md` | tracked delta | obsolete vendor-driven portions; app-only authority rewrite required (F3) |
| `docs/specs/2026-09-07-pane-session-reliability/requirements.md` | tracked delta | obsolete vendor-driven portions; app-only authority rewrite required (F3) |
| `docs/specs/2026-09-07-pane-session-reliability/specification.md` | tracked delta | obsolete vendor-driven portions; app-only authority rewrite required (F3) |
| `docs/wip/2026-09-05-memory-pressure-salvage-assessment.md` | tracked delta | historical mixed evidence and superseded decisions; retain as history, not current proof or authority |
| `docs/wip/2026-09-06-attention-ordering/program-design.md` | tracked delta | keep candidate; settled attention design matches reviewed source; external old requirement links remain historical |
| `docs/wip/debugging/2026-09-05-release-takeover-investigation.md` | tracked delta | historical mixed evidence and superseded decisions; retain as history, not current proof or authority |
| `scripts/verify-renderer-population.sh` | tracked delta | defect F2; otherwise keep candidate for separate process/native observations |
| `.join(owners[-4:])[:450]}")[newline]` | untracked | unrelated zero-byte accidental artifact; no execution or cleanup performed |
| `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+PaneDiscard.swift` | untracked | keep candidate; source/diff inspected; required current proof unverified |
| `Tests/AgentStudioTests/App/WorkspacePaneDiscardFocusTests.swift` | untracked | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorTests+Filesystem.swift` | untracked | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionLifetimeTests.swift` | untracked | keep candidate; semantic diff/test boundary inspected; not executed |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/SurfaceManagerNativeRetirementTests.swift` | untracked | keep candidate as no-native-handle seam proof only; native behavior unverified |
| `docs/wip/2026-08-27-hotspot-inventory.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-08-27-performance-side-issues.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-08-27-systemic-issues-and-architecture-amendments.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-08-28-pr2-local-activity-replay.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-08-28-shared-ancestor-activity-settlement.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-08-28-shared-git-ancestor-continuity-amendment.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-09-03-fix-validation-and-open-defects.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-09-03-pr-review-findings.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/2026-09-06-session-retirement/native-retirement-prototype.md` | untracked | obsolete vendor-driven experiment ledger; historical claims unverified for current app-only build |
| `docs/wip/communications/2026-08-28-shared-ancestor-continuity-advisor.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/debugging/2026-08-27-fsevents-callback-hotspot.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/debugging/2026-09-01-pr1-sidebar-dynamic-stability.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/debugging/2026-09-03-pane-lifecycle-repair-validation.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/debugging/2026-09-03-pane-tab-switch-spinner.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |
| `docs/wip/debugging/2026-09-03-pr-complete-review.md` | untracked | unrelated/historical evidence; scope/section inventory inspected; old source and proof claims explicitly not revalidated |

## Obligation coverage and real-path status

| Current obligation | Implementation path | Proof fit / status |
| --- | --- | --- |
| Register new session before launch | terminal creation composition → serialized datastore save → slot preparation/publication → native creation | Live app path; 12 creation durability cases use real SQLite and a failing native factory; native startup/current binary proof remains separate |
| Atomic close + full Undo snapshot | Undo composition → same core transaction → will/did publication | Live; rollback, main/drawer/tab identities and slot tests inspected |
| 300 seconds; ten oldest-first operations | AppPolicies → journal clock/write/recovery → one coordinator deadline loop | Live; injected deadline, failure/retry, capacity and ordinary same-boot recovery tests inspected; historical real five-minute observations only |
| Restore logical ownership despite renderer failure | prepareRestore/commitMostRecentUndo → applyCommittedRestore → materializeRestoredPanes | Live; tests now correctly keep pane/slot on failure and retain unavailable placement entries |
| Protect shared/backgrounded owners | global live terminal rows + available members predicate | Live SQL decision; real SQLite cross-workspace/session tests inspected; actual protected command survival not current-proof |
| Pending cleanup and restart retries | pending DTO/schema exists | Missing live cleanup executor and result/identity writer (F1) |
| Exact zmx identity/group extinction and detached/unknown protection | unchanged ZmxBackend name-based CLI destroy | Unimplemented for journal path; do not treat CLI success as termination |
| Explicit app-owned native retirement | SurfaceManager.destroy → SurfaceView.retireNativeSurface → existing free | Live source; current tests use bare handles/injected retirement; retained-layer and shutdown-load safety unresolved |
| Preserve visibility/focus/zoom/drawers | owning window facts + tier resolver → manager delivery seam | Source and unit/integration tests cover transitions/equality/focus ownership; native same-marker scenario matrix incomplete |
| Preserve observation stop/lifetime | weak terminal/runtime captures; RepoExplorer live capture resolution; settled attention queues/epoch | Real interaction tests inspected; actual projector unseen-window and tracker nil/stop regressions exist; no need to re-open older fixed attention findings |
| Bounded completed history | pruning excludes available/pending and caps eligible rows | SQL tests inspected; F1 prevents terminal pending rows from ever becoming eligible |
| Separate native/process/graphics proof | lifecycle counters + external sampler | Correct separation intent; sampler F2; historical source/executable mapping not complete |
| Current aggregate/lint/manual proof | repo-required mise tasks | Not run by reviewer; no current-head readiness established |

## Test-change reduction

The large DrawerCommand/Management, Hardening/Restoration, Coordinator/Filesystem and TerminalRestore/support diffs were compared across both old and new file groups after removing formatting and async-call spelling changes. Their apparent deletions mostly move scenarios, widen helper visibility for same-target reuse, adopt SQLite fixtures, and await commands/shutdown. No dropped scenario was found in those four moved groups. Their new files are accounted for individually above.

Behavioral assertion changes are intentional under durable ownership: closed panes leave live rows and exist in the journal; failed rendering preserves restored panes instead of deleting them; invalid placement keeps its Undo entry. They are not evidence that native teardown was proven. The previous native-independent tests only prove release of bare Swift/AppKit objects or invocation of a retirement closure.

The filesystem tests replace the real native event stream only where synthetic cursor IDs are injected; exact watermark assertions remain. The cadence tests assert the chosen deadline against both cadence and measured duty before advancing the injected clock. The eventually helper now permits a minimum turn budget plus a real timeout; it does not weaken the final predicate, although it can wait longer than the nominal timeout. Coalescing tests use a controlled entry gate but still contain fixed-yield settling and unbounded gate waits; this is a remaining test-fidelity limitation, not a proved product regression.

Attention coverage includes real `Ghostty.ActionRouter` → projector unseen-window cancellation and preservation, stop/restart ordering and deallocation, and exact nil transition traces. The controlled sink tests remain limited to serialized control ordering. Renderer-visibility source tests complement real manager + recording delivery integration; neither is native rendering smoke.

## Evidence provenance ledger

| Evidence | Observed content | Classification |
| --- | --- | --- |
| `git diff origin/main -- vendor`; `git diff HEAD -- vendor` | empty at reviewed snapshot | Current tracked vendor boundary only; does not exonerate earlier experiments |
| `native-constructor-build.log:5` | invokes `build-ghostty-local.sh` | Historical custom-vendor build; excluded from app-only validation |
| Native start-gate red/green receipts | parent supplies 68/69 red and incomplete named green log | Not independently accepted as app-only proof; removed custom API path |
| `tmp/debug-workflows/2026-09-07-agent-studio-duplicate-terminal-mount/debug-investigation.md:31` | primary framework selected for **next** build; old framework held; explicit proof disclaimer | Selection/provenance intent only |
| `app-boundary-proof/app-build.log` | app compilation/link and Build complete; 16.21 s build / 25.83 s task output | Historical successful build output; no executable hash/link-input receipt ties this alone to later live telemetry |
| Parent-reported primary/held static-library digests | different libraries; primary begins 9ce6c1a8, held ebc50dad | Independently reported parent evidence, not rehashed in this lane |
| `app-boundary-proof/native-free-events.jsonl` | two freed events at 23:39:41Z and 23:43:41Z, 18.224/21.307 ms, created 3/freed 2/live 1/managed 1 | Historical instrumented native free; not current source proof, process termination, or retained-layer stress |
| `app-boundary-proof/*/sample.txt` | rebuilt baseline 1 renderer/I/O; three panes 3/3; after both expiries 1/1 | Historical independent native thread population agrees with conservation; executable provenance still incomplete |
| `app-boundary-proof/undo-before.json`, `undo-after.json` | samePID flag true; final operation restored | Historical same-session continuity observation; raw capture review is not a fresh runtime journey |
| `app-boundary-proof/after-first-expiry-sessions.json` | one pending owner and three listed sessions | Historical pending-but-live evidence, consistent with F1 |
| attention-remediation per-suite logs | historical test receipts and current matching scenarios | Useful historical lower-layer evidence; no current whole-branch gate |
| older combined aggregate at 9c2370020, current worktree includes later commits/dirty changes | historical successful aggregate described in debug ledger | Stale for current readiness |
| `git diff --check` run during this review | exit 0, no output | Current whitespace-only check; not tests/lint/build |

No new build, test, native action, process signal, or GitHub mutation was performed. No complete current aggregate, CI/PR review-thread state, signed artifact or release proof is established. No PR lookup was performed by this lane; “no PR found” remains parent-supplied evidence.

## Minimum recovery sequence — recommendations only

1. Keep the reviewed app reliability foundation and all preservation tests. Do not reset the branch wholesale. The empty accidental file and unrelated historical documents need an explicit packaging decision, not implementation changes.
2. Replace stale active design/plan meaning with the app-only boundary: existing three-table journal; one durable close/Undo authority; existing native API; exact cleanup outcome; no vendor APIs/patches/pins. Make the unresolved native responsiveness/retained-layer guarantee and zmx capability gap explicit and settle them before writing through a new seam.
3. Complete the missing cleanup path through existing owners and available vendor capabilities, with exact ownership/identity checks, bounded retry, durable results and crash/restart reconciliation. Preserve unknown and detached services. If that cannot be achieved with existing capabilities, stop for an owner decision; do not improvise a vendor change or custom framework.
4. Fix the sampler's exact class matching and test it against the observed keypath counterexample. Preserve separate counts for Swift views, native freed/thread population, zmx original group and dirty/reclaimable graphics.
5. Rebuild with a recorded source snapshot and selected primary vendor artifact identity; record the final executable identity and exact launch marker/PID. Exercise creation/close/Undo/expiry, relaunch before/after deadlines, shared/backgrounded owner protection, replacement/unknown identity, detached service, retained layer, repeated retirement and busy/quit workloads. Do not reuse custom-vendor prototype results.
6. Run focused real-path tests plus required `mise run lint` and `mise run test` on final state, then fresh independent review and the requested delivery boundary. No PR/release readiness until those gates and scoped native/process proof hold.

## Explicit exclusions and residual uncertainty

All 14 unrelated historical WIP/communication/debug documents in the inventory remain unverified as current correctness claims. Their sections refer to old FSEvents, shared-ancestor continuity, PR1/PR2 and earlier pane-residency investigations. No source change in those excluded lanes is proposed. The obsolete native prototype ledger is not accepted proof. The salvage and takeover ledgers mix old success and failure receipts and should remain history.

No current native stress, process extinction, full aggregate, or release claim is verified. API research and source tracing cannot substitute for those observations. This audit completes file accounting and current app/source-test candidate review; it deliberately does not certify all historic investigations or completion of the requested product behavior.
