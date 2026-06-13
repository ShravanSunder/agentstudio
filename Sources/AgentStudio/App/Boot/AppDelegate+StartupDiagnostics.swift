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
        let fixtureSurfaceCount = fixture.paneIds
            .compactMap { viewRegistry.terminalView(for: $0)?.surfaceId }
            .count
        let fixtureTerminalViewCount = fixture.paneIds
            .filter { viewRegistry.terminalView(for: $0) != nil }
            .count
        startupTraceRecorder.recordAppStartup(
            "app.startup_diagnostic_action.command_exercised",
            phase: "startup_diagnostic_action",
            outcome: "succeeded",
            attributes: startupDiagnosticTraceAttributes(for: action).merging([
                "agentstudio.startup_diagnostic.created_pane.count": .int(fixture.paneIds.count),
                "agentstudio.startup_diagnostic.destination_initial_pane.count": .int(2),
                "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                "agentstudio.startup_diagnostic.fixture.terminal_view.count": .int(fixtureTerminalViewCount),
                "agentstudio.startup_diagnostic.fixture.surface.count": .int(fixtureSurfaceCount),
            ]) { _, newValue in newValue }
        )
        let renderProofSucceeded = fixtureSurfaceCount == fixture.paneIds.count
        let finalMessage =
            renderProofSucceeded
            ? "app.startup_diagnostic_action.completed"
            : "app.startup_diagnostic_action.blocked"
        let finalOutcome = renderProofSucceeded ? "succeeded" : "blocked"
        RestoreTrace.log(
            """
            StartupDiagnostic.crossTabMoveGeometrySmoke \(finalOutcome) activeTab=\(store.tabLayoutAtom.activeTabId?.uuidString ?? "nil") \
            fixtureTerminalViews=\(fixtureTerminalViewCount) fixtureSurfaces=\(fixtureSurfaceCount) \
            fixturePanes=\(fixture.paneIds.count)
            """
        )
        startupTraceRecorder.recordAppStartup(
            finalMessage,
            phase: "startup_diagnostic_action",
            outcome: finalOutcome,
            attributes: startupDiagnosticTraceAttributes(for: action).merging([
                "agentstudio.startup_diagnostic.created_pane.count": .int(fixture.paneIds.count),
                "agentstudio.startup_diagnostic.destination_initial_pane.count": .int(2),
                "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                "agentstudio.startup_diagnostic.fixture.terminal_view.count": .int(fixtureTerminalViewCount),
                "agentstudio.startup_diagnostic.fixture.surface.count": .int(fixtureSurfaceCount),
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(renderProofSucceeded),
            ]) { _, newValue in newValue }
        )
    }

    private func startupDiagnosticLaunchRestoreBounds() async -> CGRect? {
        if windowLifecycleStore.isReadyForLaunchRestore {
            return windowLifecycleStore.terminalContainerBounds
        }

        let bridge = WindowRestoreBridge(windowLifecycleStore: windowLifecycleStore)
        for await bounds in bridge.stream {
            return bounds
        }
        return nil
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
