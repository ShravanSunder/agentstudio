import AppKit
import Foundation
import Testing

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    struct PaneTabViewControllerBridgeCommandTests {
        init() {
            installTestAtomRegistryIfNeeded()
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
                #expect(atom(\.bridgePaneAttendance).ordinal(for: createdPane.id) != nil)

                let initialSelection = try await requireSurfaceSelection(
                    .review,
                    from: createdController,
                    because: "show Review must request the Review surface through the comm-worker transport"
                )
                let initialAttendanceOrdinal = try #require(
                    atom(\.bridgePaneAttendance).ordinal(for: createdPane.id)
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
                    atom(\.bridgePaneAttendance).ordinal(for: createdPane.id)
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

        @Test("invalid Bridge worktree target creates nothing and records no attendance")
        func invalidWorktreeTargetCreatesNothingAndRecordsNoAttendance() async {
            await withBridgeCommandHarness { harness in
                // Arrange
                let invalidWorktreeId = UUID()
                let attendanceBefore = atom(\.bridgePaneAttendance).ordinalByPaneId
                let paneIdsBefore = Set(harness.store.paneAtom.panes.keys)
                let tabIdsBefore = Set(harness.store.tabLayoutAtom.tabs.map(\.id))

                // Act
                harness.controller.execute(.showBridgeReview, target: invalidWorktreeId, targetType: .worktree)
                harness.controller.execute(.openBridgeFilesInNewTab, target: invalidWorktreeId, targetType: .worktree)

                // Assert
                #expect(Set(harness.store.paneAtom.panes.keys) == paneIdsBefore)
                #expect(Set(harness.store.tabLayoutAtom.tabs.map(\.id)) == tabIdsBefore)
                #expect(harness.viewRegistry.allBridgeViews.isEmpty)
                #expect(atom(\.bridgePaneAttendance).ordinalByPaneId == attendanceBefore)
                #expect(atom(\.bridgePaneAttendance).ordinal(for: invalidWorktreeId) == nil)
            }
        }
    }
}

@MainActor
private func withBridgeCommandHarness<TResult>(
    _ operation: @MainActor (PaneTabViewControllerCommandHarness) async throws -> TResult
) async rethrows -> TResult {
    try await withAsyncTestAtomRegistry { _ in
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
