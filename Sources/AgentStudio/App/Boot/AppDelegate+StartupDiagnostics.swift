import AppKit
import Foundation

private struct CrossTabMoveGeometrySmokeFixture {
    let sourceTabId: UUID
    let destinationTabId: UUID
    let movedPaneId: UUID
    let sourceLeftPaneId: UUID
    let targetPaneId: UUID
    let otherDestinationPaneId: UUID

    var paneIds: [UUID] {
        [movedPaneId, sourceLeftPaneId, targetPaneId, otherDestinationPaneId]
    }

    var expectedVisiblePaneIdsAfterMove: [UUID] {
        [movedPaneId, targetPaneId, otherDestinationPaneId]
    }
}

struct CrossTabMoveGeometrySmokeRenderProof: Equatable {
    let expectedVisiblePaneCount: Int
    let terminalViewCount: Int
    let surfaceIdCount: Int
    let mountedSurfaceCount: Int
    let validGeometryCount: Int

    var succeeded: Bool {
        expectedVisiblePaneCount > 0
            && terminalViewCount == expectedVisiblePaneCount
            && mountedSurfaceCount == expectedVisiblePaneCount
            && validGeometryCount == expectedVisiblePaneCount
    }

    var attributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedVisiblePaneCount),
            "agentstudio.startup_diagnostic.fixture.terminal_view.count": .int(terminalViewCount),
            "agentstudio.startup_diagnostic.fixture.surface_reference.count": .int(surfaceIdCount),
            "agentstudio.startup_diagnostic.fixture.surface.count": .int(mountedSurfaceCount),
            "agentstudio.startup_diagnostic.fixture.valid_geometry.count": .int(validGeometryCount),
            "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
        ]
    }
}

@MainActor
extension AppDelegate {
    func runStartupDiagnosticActionIfRequested() {
        guard let action = AgentStudioStartupDiagnosticAction.fromEnvironment() else { return }
        startupTraceRecorder.recordAppStartup(
            "app.startup_diagnostic_action.requested",
            phase: "startup_diagnostic_action",
            attributes: startupDiagnosticTraceAttributes(for: action)
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            self.startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.dispatched",
                phase: "startup_diagnostic_action",
                attributes: self.startupDiagnosticTraceAttributes(for: action)
            )
            switch action.kind {
            case .newTab:
                CommandDispatcher.shared.dispatch(.newTab)
            case .commandBarRepoFilter:
                CommandDispatcher.shared.dispatch(.showCommandBarEverything)
                await Task.yield()
                self.commandBarController.state.rawInput = "# repo"
            #if DEBUG
                case .crossTabMoveGeometrySmoke:
                    await self.runCrossTabMoveGeometrySmokeDiagnostic(action: action)
                case .ipcTerminalSmoke:
                    await self.runIPCTerminalSmokeDiagnostic(action: action)
                case .bridgeReviewObservabilitySmoke:
                    await self.runBridgeReviewObservabilitySmokeDiagnostic(action: action)
            #endif
            case .addWatchFolder:
                guard let folderURL = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                    self.startupTraceRecorder.recordAppStartup(
                        "app.startup_diagnostic_action.skipped",
                        phase: "startup_diagnostic_action",
                        attributes: self.startupDiagnosticTraceAttributes(for: action).merging([
                            "agentstudio.startup_diagnostic.skip_reason": .string("missing_watch_folder")
                        ]) { _, newValue in newValue }
                    )
                    return
                }
                await self.handleWatchFolderRequested(startingAt: folderURL)
            }
        }
    }

    #if DEBUG
        private func runIPCTerminalSmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)

            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.skipped",
                    phase: "startup_diagnostic_action",
                    outcome: "skipped",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("missing_bounds")
                    ]) { _, newValue in newValue }
                )
                return
            }

            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "ipcTerminalSmokePreflight"
                )
            }

            guard
                let pane = paneCoordinator.openFloatingTerminal(
                    launchDirectory: FileManager.default.homeDirectoryForCurrentUser,
                    title: "IPC Smoke Terminal"
                )
            else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("terminal_open_failed")
                    ]) { _, newValue in newValue }
                )
                return
            }

            await paneCoordinator.restoreAllViews(in: terminalContainerBounds)
            await Task.yield()
            mainWindowController?.syncVisibleTerminalGeometry(reason: "ipcTerminalSmoke")
            let renderProof = await waitForIPCTerminalSmokeRenderProof(for: pane.id)
            guard renderProof.succeeded else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging(
                        [
                            "agentstudio.startup_diagnostic.created_pane.count": .int(1),
                            "agentstudio.startup_diagnostic.pane.id": .string(pane.id.uuidString),
                        ].merging(renderProof.attributes) { _, newValue in newValue }
                    ) { _, newValue in newValue }
                )
                return
            }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: "succeeded",
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    [
                        "agentstudio.startup_diagnostic.created_pane.count": .int(1),
                        "agentstudio.startup_diagnostic.pane.id": .string(pane.id.uuidString),
                    ].merging(renderProof.attributes) { _, newValue in newValue }
                ) { _, newValue in newValue }
            )
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.completed",
                phase: "startup_diagnostic_action",
                outcome: "succeeded",
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    [
                        "agentstudio.startup_diagnostic.created_pane.count": .int(1),
                        "agentstudio.startup_diagnostic.pane.id": .string(pane.id.uuidString),
                    ].merging(renderProof.attributes) { _, newValue in newValue }
                ) { _, newValue in newValue }
            )
        }

        private func runBridgeReviewObservabilitySmokeDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            guard let pane = paneCoordinator.openBridgeReviewObservabilitySmoke() else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("bridge_pane_creation_failed")
                    ]) { _, newValue in newValue }
                )
                return
            }

            guard
                let bridgeView = viewRegistry.view(for: pane.id)?
                    .mountedContent(as: BridgePaneMountView.self)
            else {
                startupTraceRecorder.recordAppStartup(
                    "app.startup_diagnostic_action.blocked",
                    phase: "startup_diagnostic_action",
                    outcome: "blocked",
                    attributes: startupDiagnosticTraceAttributes(for: action).merging([
                        "agentstudio.startup_diagnostic.skip_reason": .string("bridge_view_missing")
                    ]) { _, newValue in newValue }
                )
                return
            }

            let commandId = UUIDv7.generate()
            let result = await bridgeView.controller.handleDiffCommand(
                .loadDiff(
                    DiffArtifact(
                        diffId: BridgeObservabilitySmokeReviewSourceProvider.diffId,
                        worktreeId: BridgeObservabilitySmokeReviewSourceProvider.worktreeId,
                        patchData: Data()
                    )
                ),
                commandId: commandId,
                correlationId: nil
            )
            let outcome: String
            switch result {
            case .success:
                outcome = "succeeded"
            case .queued:
                outcome = "queued"
            case .failure:
                outcome = "blocked"
            }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    bridgeReviewObservabilitySmokeTraceAttributes(succeeded: outcome == "succeeded")
                ) { _, newValue in newValue }
            )
            startupTraceRecorder.recordAppStartup(
                outcome == "succeeded"
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    bridgeReviewObservabilitySmokeTraceAttributes(succeeded: outcome == "succeeded")
                ) { _, newValue in newValue }
            )
        }

        private func bridgeReviewObservabilitySmokeTraceAttributes(
            succeeded: Bool
        ) -> [String: AgentStudioTraceValue] {
            [
                "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(1),
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
            ]
        }
    #endif

    private func runCrossTabMoveGeometrySmokeDiagnostic(
        action: AgentStudioStartupDiagnosticAction
    ) async {
        guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
            RestoreTrace.log("StartupDiagnostic.crossTabMoveGeometrySmoke skipped reason=missingBounds")
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.skipped",
                phase: "startup_diagnostic_action",
                outcome: "skipped",
                attributes: startupDiagnosticTraceAttributes(for: action).merging([
                    "agentstudio.startup_diagnostic.skip_reason": .string("missing_bounds")
                ]) { _, newValue in newValue }
            )
            return
        }

        if !launchRestoreObservationState.didComplete {
            await finishLaunchRestore(
                using: terminalContainerBounds,
                source: "crossTabMoveGeometrySmokePreflight"
            )
        }

        let fixture = createCrossTabMoveGeometrySmokeFixture()
        RestoreTrace.log(
            """
            StartupDiagnostic.crossTabMoveGeometrySmoke prepared sourceTab=\(fixture.sourceTabId) \
            destTab=\(fixture.destinationTabId) movedPane=\(fixture.movedPaneId) \
            sourceLeftPane=\(fixture.sourceLeftPaneId) targetPane=\(fixture.targetPaneId) \
            otherDestinationPane=\(fixture.otherDestinationPaneId) bounds=\(NSStringFromRect(terminalContainerBounds))
            """
        )

        await paneCoordinator.restoreAllViews(in: terminalContainerBounds)
        mainWindowController?.syncVisibleTerminalGeometry(reason: "crossTabMoveGeometrySmokeBefore")
        await Task.yield()
        paneCoordinator.execute(
            .movePaneAcrossTabs(
                CrossTabPaneMoveRequest(
                    paneId: fixture.movedPaneId,
                    sourceTabId: fixture.sourceTabId,
                    destTabId: fixture.destinationTabId,
                    targetPaneId: fixture.targetPaneId,
                    direction: .horizontal,
                    position: .after
                )
            )
        )
        await Task.yield()
        mainWindowController?.syncVisibleTerminalGeometry(reason: "crossTabMoveGeometrySmokeAfter")
        let renderProof = crossTabMoveGeometrySmokeRenderProof(for: fixture)
        startupTraceRecorder.recordAppStartup(
            "app.startup_diagnostic_action.command_exercised",
            phase: "startup_diagnostic_action",
            outcome: "succeeded",
            attributes: startupDiagnosticTraceAttributes(for: action).merging(
                [
                    "agentstudio.startup_diagnostic.created_pane.count": .int(fixture.paneIds.count),
                    "agentstudio.startup_diagnostic.destination_initial_pane.count": .int(2),
                    "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                ].merging(renderProof.attributes) { _, newValue in newValue }
            ) { _, newValue in newValue }
        )
        let renderProofSucceeded = renderProof.succeeded
        let finalMessage =
            renderProofSucceeded
            ? "app.startup_diagnostic_action.completed"
            : "app.startup_diagnostic_action.blocked"
        let finalOutcome = renderProofSucceeded ? "succeeded" : "blocked"
        RestoreTrace.log(
            """
            StartupDiagnostic.crossTabMoveGeometrySmoke \(finalOutcome) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil") \
            expectedVisiblePanes=\(renderProof.expectedVisiblePaneCount) fixtureTerminalViews=\(renderProof.terminalViewCount) \
            fixtureSurfaceIds=\(renderProof.surfaceIdCount) fixtureMountedSurfaces=\(renderProof.mountedSurfaceCount) \
            validGeometry=\(renderProof.validGeometryCount) fixturePanes=\(fixture.paneIds.count)
            """
        )
        startupTraceRecorder.recordAppStartup(
            finalMessage,
            phase: "startup_diagnostic_action",
            outcome: finalOutcome,
            attributes: startupDiagnosticTraceAttributes(for: action).merging(
                [
                    "agentstudio.startup_diagnostic.created_pane.count": .int(fixture.paneIds.count),
                    "agentstudio.startup_diagnostic.destination_initial_pane.count": .int(2),
                    "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                ].merging(renderProof.attributes) { _, newValue in newValue }
            ) { _, newValue in newValue }
        )
    }

    private func startupDiagnosticLaunchRestoreBounds() async -> CGRect? {
        if windowLifecycleStore.isReadyForLaunchRestore {
            return windowLifecycleStore.terminalContainerBounds
        }

        let bridge = WindowRestoreBridge(windowLifecycleStore: windowLifecycleStore)
        return await Self.firstLaunchRestoreBounds(
            from: bridge.stream,
            timeout: AppPolicies.StartupDiagnostic.launchRestoreBoundsTimeout
        )
    }

    nonisolated static func firstLaunchRestoreBounds(
        from stream: AsyncStream<CGRect>,
        timeout: Duration
    ) async -> CGRect? {
        await withTaskGroup(of: CGRect?.self, returning: CGRect?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeout.nanosecondsForTaskSleep)
                } catch {
                    return nil
                }
                return nil
            }

            guard let firstResult = await group.next() else {
                group.cancelAll()
                return nil
            }
            group.cancelAll()
            return firstResult
        }
    }

    private func crossTabMoveGeometrySmokeRenderProof(
        for fixture: CrossTabMoveGeometrySmokeFixture
    ) -> CrossTabMoveGeometrySmokeRenderProof {
        let expectedVisiblePaneIds = fixture.expectedVisiblePaneIdsAfterMove
        let terminalViews = expectedVisiblePaneIds.compactMap { viewRegistry.terminalView(for: $0) }
        let mountedSurfaces = terminalViews.compactMap(\.ghosttySurface)
        let validGeometryCount = mountedSurfaces.filter(Self.surfaceHasValidSmokeGeometry).count

        return CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: expectedVisiblePaneIds.count,
            terminalViewCount: terminalViews.count,
            surfaceIdCount: expectedVisiblePaneIds.compactMap { viewRegistry.terminalView(for: $0)?.surfaceId }.count,
            mountedSurfaceCount: mountedSurfaces.count,
            validGeometryCount: validGeometryCount
        )
    }

    private func ipcTerminalSmokeRenderProof(for paneId: UUID) -> CrossTabMoveGeometrySmokeRenderProof {
        let terminalView = viewRegistry.terminalView(for: paneId)
        let mountedSurfaces = [terminalView?.ghosttySurface].compactMap { $0 }
        let validGeometryCount = mountedSurfaces.filter(Self.surfaceHasValidSmokeGeometry).count
        let runtime = paneCoordinator.runtimeForPane(PaneId(uuid: paneId))

        return CrossTabMoveGeometrySmokeRenderProof(
            expectedVisiblePaneCount: 1,
            terminalViewCount: terminalView == nil ? 0 : 1,
            surfaceIdCount: terminalView?.surfaceId == nil ? 0 : 1,
            mountedSurfaceCount: mountedSurfaces.count,
            validGeometryCount: runtime?.lifecycle == .ready ? validGeometryCount : 0
        )
    }

    private func waitForIPCTerminalSmokeRenderProof(for paneId: UUID) async -> CrossTabMoveGeometrySmokeRenderProof {
        let clock = ContinuousClock()
        let start = clock.now
        var proof = ipcTerminalSmokeRenderProof(for: paneId)
        while !proof.succeeded
            && start.duration(to: clock.now) < AppPolicies.StartupDiagnostic.ipcTerminalSmokeReadinessTimeout
        {
            try? await Task.sleep(for: .milliseconds(50))
            mainWindowController?.syncVisibleTerminalGeometry(reason: "ipcTerminalSmokeReadiness")
            proof = ipcTerminalSmokeRenderProof(for: paneId)
        }
        return proof
    }

    private static func surfaceHasValidSmokeGeometry(_ surface: Ghostty.SurfaceView) -> Bool {
        frameIsFiniteAndPositive(surface.frame) && frameIsFiniteAndPositive(surface.bounds)
    }

    nonisolated static func frameIsFiniteAndPositive(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
            && rect.size.width > 0
            && rect.size.height > 0
    }

    private func createCrossTabMoveGeometrySmokeFixture() -> CrossTabMoveGeometrySmokeFixture {
        let movedPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Move Source")
        let sourceLeftPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Source Left")
        let targetPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Destination Target")
        let otherDestinationPane = createCrossTabMoveGeometrySmokePane(title: "Smoke Destination Peer")
        for paneId in [movedPane.id, sourceLeftPane.id, targetPane.id, otherDestinationPane.id] {
            viewRegistry.ensureSlot(for: paneId)
        }

        viewRegistry.beginInitialRestore()
        let sourceTab = Tab(paneId: movedPane.id, name: "Smoke Source")
        let destinationTab = Tab(paneId: targetPane.id, name: "Smoke Destination")
        store.tabLayoutAtom.appendTab(sourceTab)
        store.tabLayoutAtom.appendTab(destinationTab)
        _ = store.tabLayoutAtom.insertPane(
            sourceLeftPane.id,
            inTab: sourceTab.id,
            at: movedPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        _ = store.tabLayoutAtom.insertPane(
            otherDestinationPane.id,
            inTab: destinationTab.id,
            at: targetPane.id,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
        store.tabLayoutAtom.setActiveTab(destinationTab.id)

        return CrossTabMoveGeometrySmokeFixture(
            sourceTabId: sourceTab.id,
            destinationTabId: destinationTab.id,
            movedPaneId: movedPane.id,
            sourceLeftPaneId: sourceLeftPane.id,
            targetPaneId: targetPane.id,
            otherDestinationPaneId: otherDestinationPane.id
        )
    }

    private func createCrossTabMoveGeometrySmokePane(title: String) -> Pane {
        store.paneAtom.createPane(
            title: title,
            provider: .zmx,
            lifetime: .temporary
        )
    }

    private func startupDiagnosticTraceAttributes(
        for action: AgentStudioStartupDiagnosticAction
    ) -> [String: AgentStudioTraceValue] {
        [
            "agentstudio.command.source": .string("startup_diagnostic"),
            "agentstudio.command.name": .string(action.commandName),
            "agentstudio.startup_diagnostic.action": .string(action.kind.rawValue),
        ]
    }
}
