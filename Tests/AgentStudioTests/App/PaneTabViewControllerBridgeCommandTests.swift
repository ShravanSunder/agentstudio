import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

private enum BridgeCommandRecencyTestError: Error {
    case missingSetupPane
}

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct PaneTabViewControllerBridgeCommandTests {
        init() {
            installTestCoreAtomsIfNeeded()
        }

        @Test("show Review creates once, then show Files reuses and focuses the same Bridge pane")
        func showCommandsCreateThenReuseTheMatchingBridgePane() async throws {
            try await withBridgeCommandHarness { harness in
                // Arrange
                let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
                let baselinePaneIds = Set(harness.store.paneAtom.panes.keys)
                let baselineTabIds = Set(harness.store.tabLayoutAtom.tabs.map(\.id))

                // Act
                harness.controller.execute(.showBridgeReview, target: worktree.id, targetType: .worktree)

                // Assert
                let createdPane = try #require(singleCreatedBridgePane(in: harness, excluding: baselinePaneIds))
                let createdTab = try #require(harness.store.tabLayoutAtom.tabContaining(paneId: createdPane.id))
                let createdController = try #require(harness.viewRegistry.allBridgeViews[createdPane.id]?.controller)
                guard case .bridgePanel(let createdState) = createdPane.content else {
                    Issue.record("Expected show Review to create a Bridge pane")
                    return
                }
                #expect(createdState.panelKind == .diffViewer)
                #expect(
                    Set(harness.store.tabLayoutAtom.tabs.map(\.id)).subtracting(baselineTabIds)
                        == Set([createdTab.id])
                )
                #expect(harness.atomRegistry.bridgePaneAttendance.ordinal(for: createdPane.id) != nil)

                let initialSelection = try await requireSurfaceSelection(
                    .review,
                    from: createdController,
                    because: "show Review must request the Review surface through the comm-worker transport"
                )
                let initialAttendanceOrdinal = try #require(
                    harness.atomRegistry.bridgePaneAttendance.ordinal(for: createdPane.id)
                )
                let paneCountBeforeReuse = harness.store.paneAtom.panes.count
                let tabCountBeforeReuse = harness.store.tabLayoutAtom.tabs.count

                let distractorPane = harness.store.paneAtom.createPane(
                    content: .webview(WebviewState(url: URL(string: "about:blank")!)),
                    metadata: PaneMetadata(
                        title: "Distractor",
                        facets: PaneContextFacets(worktreeId: worktree.id, cwd: worktree.path)
                    )
                )
                let distractorTab = Tab(paneId: distractorPane.id, name: "Distractor")
                harness.store.tabLayoutAtom.appendTab(distractorTab)
                harness.store.tabLayoutAtom.setActiveTab(distractorTab.id)
                let paneCountWithDistractor = harness.store.paneAtom.panes.count
                let tabCountWithDistractor = harness.store.tabLayoutAtom.tabs.count
                let focusWindow = try attachExistingBridgeHostToWindow(
                    paneId: createdPane.id,
                    in: harness
                )
                focusWindow.isReleasedWhenClosed = false
                defer { focusWindow.close() }

                // Act
                harness.controller.execute(.showBridgeFiles, target: worktree.id, targetType: .worktree)

                // Assert
                let fileSelection = try await requireSurfaceSelection(
                    .file,
                    from: createdController,
                    because: "show Files must retarget the reused pane through the comm-worker transport"
                )
                let attendanceAfterReuse = try #require(
                    harness.atomRegistry.bridgePaneAttendance.ordinal(for: createdPane.id)
                )
                #expect(initialSelection.selectionRevision < fileSelection.selectionRevision)
                #expect(attendanceAfterReuse == initialAttendanceOrdinal + 1)
                #expect(harness.store.paneAtom.panes.count == paneCountWithDistractor)
                #expect(harness.store.tabLayoutAtom.tabs.count == tabCountWithDistractor)
                #expect(harness.store.paneAtom.panes.count == paneCountBeforeReuse + 1)
                #expect(harness.store.tabLayoutAtom.tabs.count == tabCountBeforeReuse + 1)
                #expect(harness.store.tabLayoutAtom.activeTabId == createdTab.id)
                #expect(harness.store.tabLayoutAtom.tab(createdTab.id)?.activePaneId == createdPane.id)
                #expect(atom(\.workspaceFocusOwner).owner == .mainPane(paneId: createdPane.id))
                #expect(harness.viewRegistry.allBridgeViews.count == 1)
                #expect(harness.viewRegistry.allBridgeViews[createdPane.id]?.controller === createdController)
            }
        }

        @Test("explicit new-tab commands always create independent Bridge pane authorities")
        func explicitNewTabCommandsAlwaysCreateIndependentBridgeAuthorities() async throws {
            try await withBridgeCommandHarness { harness in
                // Arrange
                let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)

                // Act
                harness.controller.execute(.showBridgeReview, target: worktree.id, targetType: .worktree)
                harness.controller.execute(.openBridgeFilesInNewTab, target: worktree.id, targetType: .worktree)
                harness.controller.execute(.openBridgeReviewInNewTab, target: worktree.id, targetType: .worktree)

                // Assert
                let bridgePanes = harness.store.paneAtom.panes.values
                    .filter { pane in
                        if case .bridgePanel = pane.content { return true }
                        return false
                    }
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                #expect(bridgePanes.count == 3)
                #expect(harness.store.tabLayoutAtom.tabs.count == 3)
                #expect(Set(bridgePanes.map(\.id)).count == 3)

                let controllers = try bridgePanes.map { pane in
                    try #require(harness.viewRegistry.allBridgeViews[pane.id]?.controller)
                }
                #expect(Set(controllers.map(ObjectIdentifier.init)).count == 3)

                var bootstraps: [BridgeProductSessionBootstrap] = []
                for controller in controllers {
                    let bootstrap = try #require(await controller.productSessionOwner.activeBootstrap())
                    bootstraps.append(bootstrap)
                }
                #expect(Set(bootstraps.map(\.paneSessionId)).count == 3)
                #expect(Set(bootstraps.map(\.workerInstanceId)).count == 3)

                var selections: [BridgePaneSurfaceSelectionRequest] = []
                for controller in controllers {
                    let selection = try await requireAnySurfaceSelection(
                        from: controller,
                        because: "each explicit duplicate must own its own native surface request"
                    )
                    selections.append(selection)
                }
                #expect(Set(selections.map(\.requestId)).count == 3)
                #expect(Set(selections.map(\.paneSessionId)) == Set(bootstraps.map(\.paneSessionId)))
                #expect(Set(selections.map(\.workerInstanceId)) == Set(bootstraps.map(\.workerInstanceId)))
                #expect(selections.filter { $0.surface == .file }.count == 1)
                #expect(selections.filter { $0.surface == .review }.count == 2)

                for controller in controllers {
                    let snapshot = controller.surfaceSelectionAuthority.diagnosticSnapshot
                    let currentRequest = try #require(snapshot.currentRequest)
                    let bootstrap = try #require(
                        bootstraps.first { $0.paneSessionId == currentRequest.paneSessionId }
                    )
                    #expect(currentRequest.workerInstanceId == bootstrap.workerInstanceId)
                    #expect(snapshot.lastAcceptedRequest == nil)
                }
            }
        }

        @Test("Bridge Web View Reload is available only for the active mounted Bridge pane")
        func bridgeWebViewReloadAvailabilityRequiresActiveMountedBridgePane() async throws {
            try await withBridgeCommandHarness { harness in
                // Arrange
                let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
                let baselinePaneIds = Set(harness.store.paneAtom.panes.keys)
                harness.controller.execute(
                    .showBridgeReview,
                    target: worktree.id,
                    targetType: .worktree
                )
                let mountedBridgePane = try #require(
                    singleCreatedBridgePane(in: harness, excluding: baselinePaneIds)
                )
                let mountedBridgeTab = try #require(
                    harness.store.tabLayoutAtom.tabContaining(paneId: mountedBridgePane.id)
                )
                let unmountedBridgePane = harness.store.paneAtom.createPane(
                    content: .bridgePanel(
                        BridgePaneState(
                            panelKind: .fileViewer,
                            source: .workspace(
                                rootPath: worktree.path.path,
                                baseline: .localDefaultBranch(branchName: "main")
                            )
                        )
                    ),
                    metadata: PaneMetadata(
                        title: "Unmounted Bridge",
                        facets: PaneContextFacets(worktreeId: worktree.id, cwd: worktree.path)
                    )
                )
                let unmountedBridgeTab = Tab(
                    paneId: unmountedBridgePane.id,
                    name: "Unmounted Bridge"
                )
                harness.store.tabLayoutAtom.appendTab(unmountedBridgeTab)

                // Act / Assert
                harness.store.tabLayoutAtom.setActiveTab(unmountedBridgeTab.id)
                #expect(!harness.controller.canExecute(.reloadBridgeWebView))

                harness.store.tabLayoutAtom.setActiveTab(mountedBridgeTab.id)
                #expect(harness.controller.canExecute(.reloadBridgeWebView))

                let mountedBridgeController = try #require(
                    harness.viewRegistry.allBridgeViews[mountedBridgePane.id]?.controller
                )
                let retirementTask = mountedBridgeController.teardown()
                #expect(!harness.controller.canExecute(.reloadBridgeWebView))
                _ = await retirementTask.value
            }
        }

        @Test("Bridge Web View Reload resets browser state without replacing native authority")
        func bridgeWebViewReloadPreservesControllerPageAndSourceAuthority() async throws {
            try await withBridgeCommandHarness { harness in
                // Arrange
                let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
                let baselinePaneIds = Set(harness.store.paneAtom.panes.keys)
                harness.controller.execute(
                    .showBridgeFiles,
                    target: worktree.id,
                    targetType: .worktree
                )
                let bridgePane = try #require(
                    singleCreatedBridgePane(in: harness, excluding: baselinePaneIds)
                )
                let bridgeContentBeforeReload = bridgePane.content
                let bridgeMountView = try #require(harness.viewRegistry.allBridgeViews[bridgePane.id])
                let bridgeController = bridgeMountView.controller
                let retainedPage = bridgeController.page
                try await WebPageTestHarness.withManagedPage(retainedPage) { retainedPage in
                    #expect(
                        await waitForBridgeCommandCondition {
                            await bridgeController.productSessionOwner.activeBootstrap() != nil
                                && !retainedPage.isLoading
                        }
                    )
                    let bootstrapBeforeReload = try #require(
                        await bridgeController.productSessionOwner.activeBootstrap()
                    )
                    #expect(bridgeController.requestViewerSurface(.review))
                    let reviewRequestBeforeReload = try await requireSurfaceSelection(
                        .review,
                        from: bridgeController,
                        because: "Reload setup must acknowledge Review as the retained native surface"
                    )
                    try await acknowledgeSurfaceSelection(
                        reviewRequestBeforeReload,
                        bootstrap: bootstrapBeforeReload,
                        in: bridgeController
                    )
                    _ = try await retainedPage.callJavaScript(
                        "document.title = 'AgentStudio Bridge Reload Probe'"
                    )
                    #expect(
                        await waitForBridgeCommandCondition {
                            retainedPage.title == "AgentStudio Bridge Reload Probe"
                        }
                    )

                    // Act
                    harness.controller.execute(.reloadBridgeWebView)

                    // Assert
                    #expect(
                        await waitForBridgeCommandCondition {
                            guard
                                let activeBootstrap =
                                    await bridgeController.productSessionOwner.activeBootstrap()
                            else { return false }
                            return activeBootstrap.workerInstanceId
                                != bootstrapBeforeReload.workerInstanceId
                                && !retainedPage.isLoading
                        }
                    )
                    #expect(retainedPage.title != "AgentStudio Bridge Reload Probe")
                    #expect(harness.viewRegistry.allBridgeViews[bridgePane.id] === bridgeMountView)
                    #expect(bridgeMountView.controller === bridgeController)
                    #expect(bridgeController.page === retainedPage)
                    #expect(harness.store.paneAtom.pane(bridgePane.id)?.content == bridgeContentBeforeReload)
                    let bootstrapAfterReload = try #require(
                        await bridgeController.productSessionOwner.activeBootstrap()
                    )
                    #expect(
                        await waitForBridgeCommandCondition {
                            let snapshot = bridgeController.surfaceSelectionAuthority.diagnosticSnapshot
                            guard let acceptedRequest = snapshot.lastAcceptedRequest else {
                                return false
                            }
                            return snapshot.currentRequest == nil
                                && acceptedRequest.requestId != reviewRequestBeforeReload.requestId
                                && acceptedRequest.surface == .review
                                && acceptedRequest.paneSessionId == bootstrapAfterReload.paneSessionId
                                && acceptedRequest.workerInstanceId == bootstrapAfterReload.workerInstanceId
                        }
                    )
                }
            }
        }

        @Test("Command-R toggles Management Layer without reloading a mounted Bridge Web View")
        func commandRTogglesManagementLayerWithoutReloadingMountedBridgeWebView() async throws {
            try await withBridgeCommandHarness { harness in
                // Arrange
                configureMainWindowKeyboardOwner(
                    windowLifecycleStore: harness.windowLifecycleStore
                )
                let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
                let baselinePaneIds = Set(harness.store.paneAtom.panes.keys)
                harness.controller.execute(
                    .showBridgeFiles,
                    target: worktree.id,
                    targetType: .worktree
                )
                let bridgePane = try #require(
                    singleCreatedBridgePane(in: harness, excluding: baselinePaneIds)
                )
                let bridgeMountView = try #require(harness.viewRegistry.allBridgeViews[bridgePane.id])
                let bridgeController = bridgeMountView.controller
                let retainedPage = bridgeController.page
                try await WebPageTestHarness.withManagedPage(retainedPage) { retainedPage in
                    #expect(
                        await waitForBridgeCommandCondition {
                            await bridgeController.productSessionOwner.activeBootstrap() != nil
                                && !retainedPage.isLoading
                        }
                    )
                    let bootstrapBeforeCommand = try #require(
                        await bridgeController.productSessionOwner.activeBootstrap()
                    )
                    _ = try await retainedPage.callJavaScript(
                        "document.title = 'AgentStudio Command-R Probe'"
                    )
                    #expect(
                        await waitForBridgeCommandCondition {
                            retainedPage.title == "AgentStudio Command-R Probe"
                        }
                    )
                    let commandREvent = try #require(
                        makeKeyEvent(
                            modifierFlags: [.command],
                            characters: "r",
                            charactersIgnoringModifiers: "r",
                            keyCode: 15
                        )
                    )
                    let managementLayer = atom(\.managementLayer)
                    #expect(!managementLayer.isActive)

                    // Act
                    try await withIsolatedCommandDispatcher(
                        configure: {
                            AppCommandDispatcher.shared.handler = harness.controller
                            AppCommandDispatcher.shared.appCommandRouter = nil
                        },
                        body: {
                            #expect(harness.controller.handleAppOwnedKeyEvent(commandREvent))
                        }
                    )

                    // Assert
                    #expect(managementLayer.isActive)
                    #expect(!retainedPage.isLoading)
                    #expect(retainedPage.title == "AgentStudio Command-R Probe")
                    #expect(harness.viewRegistry.allBridgeViews[bridgePane.id] === bridgeMountView)
                    #expect(bridgeMountView.controller === bridgeController)
                    #expect(bridgeController.page === retainedPage)
                    let bootstrapAfterCommand = try #require(
                        await bridgeController.productSessionOwner.activeBootstrap()
                    )
                    #expect(bootstrapAfterCommand == bootstrapBeforeCommand)
                }
            }
        }

        @Test("successful targeted Bridge commands record location and attended pane recency")
        func successfulTargetedCommandsRecordLocationAndPaneRecency() async throws {
            for command in [
                AppCommand.showBridgeReview,
                .showBridgeFiles,
                .openBridgeReviewInNewTab,
                .openBridgeFilesInNewTab,
            ] {
                try await assertSuccessfulBridgeCommandRecordsRecency(command)
            }
        }

        @Test("invalid or unsupported Bridge target records no recency or attendance")
        func invalidOrUnsupportedTargetRecordsNothing() async {
            await withBridgeCommandHarness { harness in
                // Arrange
                let (_, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
                let invalidWorktreeId = UUID()
                let attendanceBefore = harness.atomRegistry.bridgePaneAttendance.ordinalByPaneId
                let paneIdsBefore = Set(harness.store.paneAtom.panes.keys)
                let tabIdsBefore = Set(harness.store.tabLayoutAtom.tabs.map(\.id))

                // Act
                harness.controller.execute(.showBridgeReview, target: invalidWorktreeId, targetType: .worktree)
                harness.controller.execute(.openBridgeFilesInNewTab, target: invalidWorktreeId, targetType: .worktree)
                harness.controller.execute(.showBridgeFiles, target: worktree.id, targetType: .repo)

                // Assert
                #expect(Set(harness.store.paneAtom.panes.keys) == paneIdsBefore)
                #expect(Set(harness.store.tabLayoutAtom.tabs.map(\.id)) == tabIdsBefore)
                #expect(harness.viewRegistry.allBridgeViews.isEmpty)
                #expect(harness.atomRegistry.bridgePaneAttendance.ordinalByPaneId == attendanceBefore)
                #expect(harness.atomRegistry.bridgePaneAttendance.ordinal(for: invalidWorktreeId) == nil)
                #expect(harness.atomRegistry.core.applicationEntityRecency.recentEntities.isEmpty)
                #expect(harness.atomRegistry.core.workspaceEntityRecency.recentEntities.isEmpty)
            }
        }
    }
}

@MainActor
private func assertSuccessfulBridgeCommandRecordsRecency(_ command: AppCommand) async throws {
    try await withAsyncTestAtomRegistry { atoms in
        let harness = makeHarness(windowLifecycleStore: atoms.core.windowLifecycle)
        let (repository, worktree) = makeRepoAndWorktree(harness.store, root: harness.tempDir)
        let reusesExistingPane = command == .showBridgeReview || command == .showBridgeFiles
        let reusedPane: Pane?
        let reuseWindow: NSWindow?
        if reusesExistingPane {
            let paneIdsBeforeSetup = Set(harness.store.paneAtom.panes.keys)
            harness.controller.execute(
                .openBridgeReviewInNewTab,
                target: worktree.id,
                targetType: .worktree
            )
            guard
                let setupPane = singleCreatedBridgePane(
                    in: harness,
                    excluding: paneIdsBeforeSetup
                )
            else {
                throw BridgeCommandRecencyTestError.missingSetupPane
            }
            reusedPane = setupPane
            let distractorPane = harness.store.createPane(title: "Distractor")
            let distractorTab = Tab(paneId: distractorPane.id, name: "Distractor")
            harness.store.appendTab(distractorTab)
            harness.store.setActiveTab(distractorTab.id)
            reuseWindow = try attachExistingBridgeHostToWindow(
                paneId: setupPane.id,
                in: harness
            )
            reuseWindow?.isReleasedWhenClosed = false
        } else {
            reusedPane = nil
            reuseWindow = nil
        }

        atoms.core.applicationEntityRecency.clear()
        atoms.core.workspaceEntityRecency.hydrate(
            workspaceID: harness.store.identityAtom.workspaceId,
            recentEntities: []
        )
        configureMainWindowKeyboardOwner(atoms.core)
        let observer = WorkspacePaneRecencyObserver(
            store: harness.store,
            attendedPane: AttendedPaneDerived(
                tabLayout: harness.store.tabLayoutAtom,
                windowLifecycle: atoms.core.windowLifecycle,
                managementLayer: atoms.core.managementLayer
            ),
            recencyAtom: atoms.core.workspaceEntityRecency
        )
        let paneIdsBeforeDispatch = Set(harness.store.paneAtom.panes.keys)

        do {
            try await dispatchBridgeCommand(
                command,
                worktreeId: worktree.id,
                controller: harness.controller
            )

            let openedPane =
                if let reusedPane {
                    reusedPane
                } else {
                    try #require(
                        singleCreatedBridgePane(in: harness, excluding: paneIdsBeforeDispatch)
                    )
                }
            await eventually("Bridge command should record the newly attended pane") {
                atoms.core.workspaceEntityRecency.recentEntities.contains {
                    $0.entity == .pane(paneID: openedPane.id)
                }
            }

            let applicationRecency = atoms.core.applicationEntityRecency.recentEntities
            #expect(
                Set(applicationRecency.map(\.entity))
                    == Set([
                        .repository(repositoryStableKey: repository.stableKey),
                        .worktree(worktreeStableKey: worktree.stableKey),
                    ])
            )
            #expect(applicationRecency.allSatisfy { $0.interaction == .opened })
            #expect(
                Set(applicationRecency.map(\.lastInteractedAt)).count == 1
            )
            #expect(
                atoms.core.workspaceEntityRecency.recentEntities.map(\.entity)
                    == [.pane(paneID: openedPane.id)]
            )

            observer.stop()
            reuseWindow?.close()
            await finishBridgeCommandHarness(harness)
        } catch {
            observer.stop()
            reuseWindow?.close()
            await finishBridgeCommandHarness(harness)
            throw error
        }
    }
}

@MainActor
private func dispatchBridgeCommand(
    _ command: AppCommand,
    worktreeId: UUID,
    controller: PaneTabViewController
) async throws {
    try await withIsolatedCommandDispatcher(
        configure: {
            AppCommandDispatcher.shared.handler = controller
            AppCommandDispatcher.shared.appCommandRouter = nil
        },
        body: {
            AppCommandDispatcher.shared.dispatch(
                command,
                target: worktreeId,
                targetType: .worktree
            )
        }
    )
}

@MainActor
private func withBridgeCommandHarness<TResult>(
    _ operation: @MainActor (PaneTabViewControllerCommandHarness) async throws -> TResult
) async rethrows -> TResult {
    try await withAsyncTestCoreAtoms { _ in
        let harness = makeHarness()
        do {
            let result = try await operation(harness)
            await finishBridgeCommandHarness(harness)
            return result
        } catch {
            await finishBridgeCommandHarness(harness)
            throw error
        }
    }
}

@MainActor
private func finishBridgeCommandHarness(_ harness: PaneTabViewControllerCommandHarness) async {
    harness.controller.shutdown()
    await harness.coordinator.shutdown()
    #expect(harness.coordinator.pendingBridgePaneRetirementCount == 0)
    #expect(harness.viewRegistry.allBridgeViews.isEmpty)
    try? FileManager.default.removeItem(at: harness.tempDir)
}

@MainActor
private func singleCreatedBridgePane(
    in harness: PaneTabViewControllerCommandHarness,
    excluding baselinePaneIds: Set<UUID>
) -> Pane? {
    let createdBridgePanes = harness.store.paneAtom.panes.values.filter { pane in
        guard !baselinePaneIds.contains(pane.id) else { return false }
        if case .bridgePanel = pane.content { return true }
        return false
    }
    guard createdBridgePanes.count == 1 else { return nil }
    return createdBridgePanes[0]
}

@MainActor
private func waitForBridgeCommandCondition(
    timeout: Duration = .seconds(5),
    _ condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

@MainActor
private func attachExistingBridgeHostToWindow(
    paneId: UUID,
    in harness: PaneTabViewControllerCommandHarness
) throws -> NSWindow {
    let window = makePaneTabViewControllerCommandWindow(for: harness.controller)
    let host = try #require(harness.viewRegistry.view(for: paneId))
    if host.window == nil {
        let contentView = try #require(window.contentView)
        host.frame = contentView.bounds
        contentView.addSubview(host)
    }
    window.makeKeyAndOrderFront(nil)
    #expect(window.makeFirstResponder(host))
    return window
}

@MainActor
private func requireSurfaceSelection(
    _ surface: BridgeProductSurface,
    from controller: BridgePaneController,
    because description: String
) async throws -> BridgePaneSurfaceSelectionRequest {
    await controller.surfaceSelectionTransitionTail?.value
    let currentRequest = controller.surfaceSelectionAuthority.diagnosticSnapshot.currentRequest
    return try #require(
        currentRequest?.surface == surface ? currentRequest : nil,
        Comment(rawValue: description)
    )
}

@MainActor
private func requireAnySurfaceSelection(
    from controller: BridgePaneController,
    because description: String
) async throws -> BridgePaneSurfaceSelectionRequest {
    await controller.surfaceSelectionTransitionTail?.value
    return try #require(
        controller.surfaceSelectionAuthority.diagnosticSnapshot.currentRequest,
        Comment(rawValue: description)
    )
}

@MainActor
private func acknowledgeSurfaceSelection(
    _ request: BridgePaneSurfaceSelectionRequest,
    bootstrap: BridgeProductSessionBootstrap,
    in controller: BridgePaneController
) async throws {
    let productAdmission = try #require(controller.productAdmissionGate.acquire())
    let correlation = try BridgeProductControlCorrelation(
        paneSessionId: bootstrap.paneSessionId,
        requestId: "bridge-command-surface-receipt",
        requestSequence: 1,
        workerInstanceId: bootstrap.workerInstanceId
    )
    await controller.handleCommittedProductActiveViewerModeUpdate(
        sessionId: "bridge-command-viewer-session",
        sequence: 1,
        mode: request.surface.activeViewerMode,
        activeSource: nil,
        productAdmission: productAdmission,
        nativeSelectionRequestId: request.requestId,
        productCorrelation: correlation
    )
}
