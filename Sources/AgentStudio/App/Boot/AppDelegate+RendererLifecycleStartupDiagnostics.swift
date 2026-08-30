import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTerminal
import AppKit
import Foundation

#if DEBUG
    struct RendererLifecycleContinuityFixture {
        let paneIDs: [UUID]
        let firstTabID: UUID
        let secondTabID: UUID
        let firstArrangementID: UUID
        let secondArrangementID: UUID
        let drawerParentID: UUID
        let drawerPaneIDs: [UUID]
        let backgroundPaneID: UUID
        let zoomPaneIDs: [UUID]
        let retentionPaneID: UUID
        let repairPaneID: UUID
        let expiryPaneIDs: [UUID]
    }

    @MainActor
    extension AppDelegate {
        func runRendererLifecycleContinuityDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            NSApp.activate(ignoringOtherApps: true)
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
            await waitForStartupDiagnosticAppActivation()
            guard let terminalContainerBounds = await startupDiagnosticLaunchRestoreBounds() else {
                recordRendererLifecycleDiagnosticResult(action: action, succeeded: false, reason: "missing_bounds")
                return
            }
            if !launchRestoreObservationState.didComplete {
                await finishLaunchRestore(
                    using: terminalContainerBounds,
                    source: "rendererLifecycleContinuityPreflight"
                )
            }
            if ProcessInfo.processInfo.environment["AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE"] == "restart" {
                await runRendererLifecycleRestartDiagnostic(action: action)
                return
            }
            guard let fixture = createRendererLifecycleContinuityFixture() else {
                recordRendererLifecycleDiagnosticResult(action: action, succeeded: false, reason: "fixture_failed")
                return
            }
            guard mountRendererLifecycleContinuityFixture(fixture, frame: terminalContainerBounds) else {
                recordRendererLifecycleDiagnosticResult(action: action, succeeded: false, reason: "mount_failed")
                return
            }
            mainWindowController?.syncVisibleTerminalGeometry(reason: "rendererLifecycleContinuityMounted")
            guard
                await waitForRendererLifecycleCondition(
                    timeout: .seconds(20),
                    {
                        fixture.paneIDs.allSatisfy { paneID in
                            self.viewRegistry.terminalView(for: paneID)?.ghosttySurface != nil
                                && self.workspaceSurfaceCoordinator.runtimeForPane(PaneId(existingUUID: paneID))?
                                    .lifecycle
                                    == .ready
                        }
                    })
            else {
                recordRendererLifecycleDiagnosticResult(action: action, succeeded: false, reason: "surface_not_ready")
                return
            }

            let initialSurfaceIDs = rendererLifecycleSurfaceIDs(for: fixture.paneIDs)
            guard initialSurfaceIDs.count == fixture.paneIDs.count else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "surface_identity_missing")
                return
            }
            let initialSessionIDs = rendererLifecycleSessionIDs(for: fixture.paneIDs)
            guard initialSessionIDs.count == fixture.paneIDs.count else {
                recordRendererLifecycleDiagnosticResult(
                    action: action, succeeded: false, reason: "session_identity_missing")
                return
            }
            if let baselineFailure = await rendererLifecycleVisibleBaselineFailure(fixture) {
                recordRendererLifecycleDiagnosticResult(
                    action: action,
                    succeeded: false,
                    reason: baselineFailure,
                    paneCount: fixture.paneIDs.count
                )
                return
            }

            if ProcessInfo.processInfo.environment["AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE"] == "soak" {
                await runRendererLifecycleSoakDiagnostic(
                    action: action,
                    fixture: fixture,
                    initialSurfaceIDs: initialSurfaceIDs,
                    initialSessionIDs: initialSessionIDs
                )
                return
            }

            await completeInitialRendererLifecycleDiagnostic(
                action: action,
                fixture,
                initialSurfaceIDs: initialSurfaceIDs,
                initialSessionIDs: initialSessionIDs
            )
        }

        private func createRendererLifecycleContinuityFixture() -> RendererLifecycleContinuityFixture? {
            guard let worktreeRoot = AgentStudioStartupDiagnosticAction.watchFolderURL() else {
                return nil
            }
            let worktree = store.mutationCoordinator.ensureMainWorktree(at: worktreeRoot)
            let mainPanes = (0..<18).map { index in
                store.paneAtom.createPane(
                    launchDirectory: worktree.path,
                    title: "Renderer Lifecycle \(index)",
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: .generateUUIDv7()
                )
            }
            let firstTabMainPanes = Array(mainPanes.prefix(8))
            let secondTabMainPanes = Array(mainPanes.suffix(10))
            guard
                let firstPane = firstTabMainPanes.first,
                let secondPane = secondTabMainPanes.first
            else { return nil }

            let firstTab = Tab(paneId: firstPane.id, name: "Renderer Lifecycle A")
            let secondTab = Tab(paneId: secondPane.id, name: "Renderer Lifecycle B")
            store.tabLayoutAtom.appendTab(firstTab)
            store.tabLayoutAtom.appendTab(secondTab)
            guard insertRendererLifecyclePanes(Array(firstTabMainPanes.dropFirst()), into: firstTab, at: firstPane.id),
                insertRendererLifecyclePanes(Array(secondTabMainPanes.dropFirst()), into: secondTab, at: secondPane.id)
            else { return nil }

            for pane in mainPanes {
                viewRegistry.ensureSlot(for: pane.id)
            }
            guard
                let firstDrawerPane = store.paneAtom.addDrawerPane(
                    to: firstPane.id,
                    parentFallbackCWD: worktree.path,
                    zmxSessionID: .generateUUIDv7()
                ),
                let secondDrawerPane = store.paneAtom.addDrawerPane(
                    to: firstPane.id,
                    parentFallbackCWD: worktree.path,
                    zmxSessionID: .generateUUIDv7()
                ),
                let drawerID = store.paneAtom.pane(firstPane.id)?.drawer?.drawerId
            else { return nil }
            for drawerPane in [firstDrawerPane, secondDrawerPane] {
                viewRegistry.ensureSlot(for: drawerPane.id)
                store.tabArrangementAtom.addDrawerPaneView(
                    drawerId: drawerID,
                    parentPaneId: firstPane.id,
                    drawerPaneId: drawerPane.id,
                    inTab: firstTab.id
                )
            }
            guard
                let secondArrangementID = store.tabLayoutAtom.createArrangement(
                    name: "Renderer Lifecycle Alternate",
                    inTab: firstTab.id
                ),
                store.tabLayoutAtom.minimizePane(firstPane.id, inTab: firstTab.id),
                let completedFirstTab = store.tabLayoutAtom.tab(firstTab.id),
                let firstArrangementID = completedFirstTab.arrangements.first(where: \.isDefault)?.id,
                completedFirstTab.activeArrangementId == secondArrangementID,
                completedFirstTab.activeMinimizedPaneIds.contains(firstPane.id)
            else { return nil }
            store.tabLayoutAtom.switchArrangement(to: firstArrangementID, inTab: firstTab.id)
            guard store.tabLayoutAtom.tab(firstTab.id)?.activeArrangementId == firstArrangementID else {
                return nil
            }
            store.tabLayoutAtom.setActiveTab(firstTab.id)

            return RendererLifecycleContinuityFixture(
                paneIDs: mainPanes.map(\.id) + [firstDrawerPane.id, secondDrawerPane.id],
                firstTabID: firstTab.id,
                secondTabID: secondTab.id,
                firstArrangementID: firstArrangementID,
                secondArrangementID: secondArrangementID,
                drawerParentID: firstPane.id,
                drawerPaneIDs: [firstDrawerPane.id, secondDrawerPane.id],
                backgroundPaneID: firstTabMainPanes[3].id,
                zoomPaneIDs: [firstTabMainPanes[1].id, firstTabMainPanes[2].id],
                retentionPaneID: firstTabMainPanes[5].id,
                repairPaneID: firstTabMainPanes[4].id,
                expiryPaneIDs: [firstTabMainPanes[6].id] + secondTabMainPanes.dropLast().map(\.id)
            )
        }

        private func insertRendererLifecyclePanes(
            _ panes: [Pane],
            into tab: Tab,
            at targetPaneID: UUID
        ) -> Bool {
            panes.allSatisfy { pane in
                store.tabLayoutAtom.insertPane(
                    pane.id,
                    inTab: tab.id,
                    at: targetPaneID,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            }
        }

        private func mountRendererLifecycleContinuityFixture(
            _ fixture: RendererLifecycleContinuityFixture,
            frame: CGRect
        ) -> Bool {
            fixture.paneIDs.allSatisfy { paneID in
                guard let pane = store.paneAtom.pane(paneID) else { return false }
                return workspaceSurfaceCoordinator.createViewForContent(
                    pane: pane,
                    initialFrame: frame,
                    treatAsRestoredSessionStart: false
                ) != nil
            }
        }

        func rendererLifecycleSurfaceIDs(for paneIDs: [UUID]) -> [UUID: UUID] {
            Dictionary(
                uniqueKeysWithValues: paneIDs.compactMap { paneID in
                    viewRegistry.terminalView(for: paneID)?.surfaceId.map { (paneID, $0) }
                }
            )
        }

        func rendererLifecycleSessionIDs(for paneIDs: [UUID]) -> [UUID: ZmxSessionID] {
            Dictionary(
                uniqueKeysWithValues: paneIDs.compactMap { paneID in
                    guard let pane = store.paneAtom.pane(paneID), case .terminal(let state) = pane.content else {
                        return nil
                    }
                    return (paneID, state.zmxSessionID)
                }
            )
        }

        func waitForRendererLifecycleCondition(
            timeout: Duration,
            _ condition: @escaping @MainActor () -> Bool
        ) async -> Bool {
            let clock = ContinuousClock()
            let start = clock.now
            while !condition(), !Task.isCancelled, start.duration(to: clock.now) < timeout {
                do {
                    try await Task.sleep(nanoseconds: Duration.milliseconds(50).nanosecondsForTaskSleep)
                } catch {
                    return false
                }
            }
            return condition()
        }

        private func rendererLifecycleVisibleBaselineFailure(
            _ fixture: RendererLifecycleContinuityFixture
        ) async -> String? {
            guard let window = mainWindowController?.window,
                let workspaceWindowID = windowLifecycleStore.preferredWorkspaceWindowId
            else { return "baseline_window_missing" }
            NSApp.activate(ignoringOtherApps: true)
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.level = .floating
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            let established = await waitForRendererLifecycleCondition(timeout: .seconds(10)) {
                guard let facts = self.windowLifecycleStore.presentationFacts(for: workspaceWindowID) else {
                    return false
                }
                return window.isVisible
                    && !window.isMiniaturized
                    && window.occlusionState.contains(.visible)
                    && facts.isVisible
                    && !facts.isMiniaturized
                    && !facts.isOccluded
                    && self.viewRegistry.terminalView(for: fixture.drawerParentID)?.ghosttySurface?
                        .requestManagedFocus(true) == true
            }
            guard !established else { return nil }
            guard window.isVisible else { return "baseline_native_not_visible" }
            guard !window.isMiniaturized else { return "baseline_native_miniaturized" }
            guard window.occlusionState.contains(.visible) else { return "baseline_native_occluded" }
            guard let facts = windowLifecycleStore.presentationFacts(for: workspaceWindowID) else {
                return "baseline_facts_missing"
            }
            guard facts.isVisible else { return "baseline_facts_not_visible" }
            guard !facts.isMiniaturized else { return "baseline_facts_miniaturized" }
            guard !facts.isOccluded else { return "baseline_facts_occluded" }
            return "baseline_renderer_not_visible"
        }

        func recordRendererLifecycleDiagnosticResult(
            action: AgentStudioStartupDiagnosticAction,
            succeeded: Bool,
            reason: String,
            paneCount: Int = 0
        ) {
            let attributes = startupDiagnosticTraceAttributes(for: action).merging([
                "agentstudio.startup_diagnostic.created_pane.count": .int(paneCount),
                "agentstudio.startup_diagnostic.fixture.surface.count": .int(paneCount),
                "agentstudio.startup_diagnostic.fixture.tab.count": .int(paneCount == 0 ? 0 : 2),
                "agentstudio.startup_diagnostic.projection_proof.succeeded": .bool(succeeded),
                "agentstudio.startup_diagnostic.render_proof.succeeded": .bool(succeeded),
                "agentstudio.startup_diagnostic.renderer_lifecycle.phase": .string(
                    ProcessInfo.processInfo.environment["AGENTSTUDIO_RENDERER_LIFECYCLE_PHASE"] ?? "initial"
                ),
                "agentstudio.startup_diagnostic.skip_reason": .string(reason),
            ]) { _, newValue in newValue }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: succeeded ? "succeeded" : "blocked",
                attributes: attributes
            )
            startupTraceRecorder.recordAppStartup(
                succeeded
                    ? "app.startup_diagnostic_action.completed"
                    : "app.startup_diagnostic_action.blocked",
                phase: "startup_diagnostic_action",
                outcome: succeeded ? "succeeded" : "blocked",
                attributes: attributes
            )
        }

        func recordRendererLifecycleDiagnosticProgress(
            action: AgentStudioStartupDiagnosticAction,
            stage: String,
            scenario: String = "none",
            completedCount: Int = 0,
            expectedCount: Int = 0,
            paneCount: Int = 20
        ) {
            let attributes = startupDiagnosticTraceAttributes(for: action).merging([
                "agentstudio.startup_diagnostic.created_pane.count": .int(completedCount),
                "agentstudio.startup_diagnostic.expected_visible_pane.count": .int(expectedCount),
                "agentstudio.startup_diagnostic.fixture.surface.count": .int(paneCount),
                "agentstudio.startup_diagnostic.fixture.tab.count": .int(2),
                "agentstudio.startup_diagnostic.renderer_lifecycle.phase": .string("soak"),
                "agentstudio.startup_diagnostic.skip_reason": .string(scenario),
            ]) { _, newValue in newValue }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: stage,
                outcome: "succeeded",
                attributes: attributes
            )
        }
    }
#endif
