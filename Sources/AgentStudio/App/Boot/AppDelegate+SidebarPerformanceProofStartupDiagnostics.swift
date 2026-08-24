import AgentStudioCore
import AgentStudioInfrastructure
import AppKit

#if DEBUG
    private struct StrictSidebarPerformanceFixtureEvidence {
        let repositoryCount: Int
        let worktreeCount: Int
        let topologyFingerprint: String
        let expectedSessionCount: Int
    }

    extension AppDelegate {
        func sidebarPerformanceProofPolicyAttributes() -> [String: AgentStudioTraceValue] {
            let policy = AppPolicies.SidebarPerformanceProof.self
            return [
                "agentstudio.startup_diagnostic.sidebar_proof.policy_id": .string(policy.policyID),
                "agentstudio.startup_diagnostic.sidebar_proof.policy_version": .int(policy.policyVersion),
                "agentstudio.startup_diagnostic.sidebar_proof.standard_trace_tags": .string(
                    policy.standardTraceTags.joined(separator: ",")),
                "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_trace_tags": .string(
                    policy.diagnosticTraceTags.joined(separator: ",")),
                "agentstudio.startup_diagnostic.sidebar_proof.idle_populations": .string(
                    policy.idlePopulationNames.joined(separator: ",")),
                "agentstudio.startup_diagnostic.sidebar_proof.action_populations": .string(
                    policy.actionPopulationNames.joined(separator: ",")),
                "agentstudio.startup_diagnostic.sidebar_proof.idle_p99_max_percent": .double(
                    policy.idleProcessCPUP99MaximumPercent),
                "agentstudio.startup_diagnostic.sidebar_proof.action_p95_max_percent": .double(
                    policy.actionProcessCPUP95MaximumPercent),
                "agentstudio.startup_diagnostic.sidebar_proof.sample_interval_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: policy.sampleInterval)),
                "agentstudio.startup_diagnostic.sidebar_proof.idle_sample_floor": .int(
                    policy.requiredIdleUsableSampleCount),
                "agentstudio.startup_diagnostic.sidebar_proof.action_count_floor": .int(
                    policy.requiredSuccessfulActionCount),
                "agentstudio.startup_diagnostic.sidebar_proof.action_sample_floor": .int(
                    policy.requiredActionBearingSampleCount),
                "agentstudio.startup_diagnostic.sidebar_proof.fixture_preparation_timeout_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: policy.fixturePreparationTimeout)),
                "agentstudio.startup_diagnostic.sidebar_proof.fixture_state_observation_interval_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: policy.fixtureStateObservationInterval)),
                "agentstudio.startup_diagnostic.sidebar_proof.fixture_tab_count": .int(
                    policy.strictTabCount),
                "agentstudio.startup_diagnostic.sidebar_proof.fixture_pane_model_count": .int(
                    policy.strictPaneModelCount),
                "agentstudio.startup_diagnostic.sidebar_proof.zero_pty_expected_session_count": .int(
                    policy.zeroPTYExpectedSessionCount),
                "agentstudio.startup_diagnostic.sidebar_proof.mounted_pty_expected_session_count": .int(
                    policy.mountedPTYExpectedSessionCount),
                "agentstudio.startup_diagnostic.sidebar_proof.zmx_inventory_interval_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: policy.zmxInventoryInterval)),
                "agentstudio.startup_diagnostic.sidebar_proof.search_character_count": .int(
                    policy.searchCharacterCount),
                "agentstudio.startup_diagnostic.sidebar_proof.search_character_interval_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: policy.searchCharacterInterval)),
                "agentstudio.startup_diagnostic.sidebar_proof.quiescence_interval_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: policy.quiescenceInterval)),
                "agentstudio.startup_diagnostic.sidebar_proof.readback_timeout_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: policy.actionReadbackTimeout)),
                "agentstudio.startup_diagnostic.sidebar_proof.sampler_gap_max_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(from: policy.maximumSamplerGap)),
                "agentstudio.startup_diagnostic.sidebar_proof.unrelated_host_cpu_max_percent": .double(
                    policy.maximumUnrelatedHostCPUPercent),
                "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_cpu_delta_max_points": .double(
                    policy.maximumDiagnosticCPUP95DeltaPercentagePoints),
                "agentstudio.startup_diagnostic.sidebar_proof.diagnostic_interaction_growth_max_percent": .double(
                    policy.maximumDiagnosticInteractionP95GrowthPercent),
                "agentstudio.startup_diagnostic.sidebar_proof.git_status_physical_limit": .int(
                    policy.gitStatusPhysicalLimit),
                "agentstudio.startup_diagnostic.sidebar_proof.git_maximum_settlement_ms": .double(
                    AgentStudioPerformanceTraceRecorder.milliseconds(
                        from: policy.gitMaximumSettlementInterval)),
            ]
        }

        func runStrictSidebarCPUPopulationDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            guard let population = SidebarPerformanceProofPopulation(kind: action.kind),
                let mainWindowController,
                let window = mainWindowController.window
            else {
                recordStrictSidebarPopulationResult(action: action, outcome: "failed")
                return
            }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic.sidebar_proof.policy_projected",
                phase: "startup_diagnostic_action",
                outcome: "ready",
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    sidebarPerformanceProofPolicyAttributes()
                ) { _, newValue in newValue }
            )
            let session = SidebarPerformanceProofSession(
                population: population,
                window: window,
                recorder: startupTraceRecorder,
                performanceRecorder: performanceTraceRecorder,
                readShell: { [weak mainWindowController] in
                    mainWindowController?.sidebarPerformanceProofShellReadback()
                }
            )
            sidebarPerformanceProofSession = session
            defer {
                if !population.isIdle {
                    sidebarPerformanceProofSession = nil
                }
            }

            guard
                let fixtureEvidence = await prepareStrictSidebarPerformanceProofFixture(
                    action: action,
                    population: population
                )
            else {
                recordStrictSidebarPopulationResult(action: action, outcome: "failed")
                return
            }
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic.sidebar_proof.fixture_ready",
                phase: "startup_diagnostic_action",
                outcome: "ready",
                attributes: startupDiagnosticTraceAttributes(for: action).merging([
                    "agentstudio.startup_diagnostic.sidebar_proof.open_source_root_present": .bool(true),
                    "agentstudio.startup_diagnostic.sidebar_proof.project_dev_root_present": .bool(true),
                    "agentstudio.startup_diagnostic.sidebar_proof.discovered_repository_count": .int(
                        fixtureEvidence.repositoryCount),
                    "agentstudio.startup_diagnostic.sidebar_proof.discovered_worktree_count": .int(
                        fixtureEvidence.worktreeCount),
                    "agentstudio.startup_diagnostic.sidebar_proof.topology_fingerprint": .string(
                        fixtureEvidence.topologyFingerprint),
                    "agentstudio.startup_diagnostic.sidebar_proof.tab_count": .int(
                        AppPolicies.SidebarPerformanceProof.strictTabCount),
                    "agentstudio.startup_diagnostic.sidebar_proof.pane_model_count": .int(
                        AppPolicies.SidebarPerformanceProof.strictPaneModelCount),
                    "agentstudio.startup_diagnostic.sidebar_proof.expected_session_variant": .int(
                        fixtureEvidence.expectedSessionCount),
                ]) { _, newValue in newValue }
            )
            AppCommandDispatcher.shared.dispatch(.showWorktreeSidebar)
            AppCommandDispatcher.shared.dispatch(.setRepoSidebarGroupingRepo)
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.command_exercised",
                phase: "startup_diagnostic_action",
                outcome: "ready",
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    sidebarPerformanceProofPolicyAttributes()
                ) { _, newValue in newValue }
            )
            let succeeded = await session.run()
            recordStrictSidebarPopulationResult(
                action: action,
                outcome: succeeded ? "succeeded" : "failed"
            )
        }

        private func prepareStrictSidebarPerformanceProofFixture(
            action: AgentStudioStartupDiagnosticAction,
            population: SidebarPerformanceProofPopulation
        ) async -> StrictSidebarPerformanceFixtureEvidence? {
            guard
                let watchedPaths = SidebarPerformanceProofFixture.registerStrictWatchedRoots(
                    store: store
                )
            else {
                recordBlockedSidebarPerformanceProofDiagnostic(
                    action: action,
                    reason: "required_watched_roots_unavailable"
                )
                return nil
            }
            guard let summary = await refreshStrictWatchedRootsAndAwaitZeroLogicalDebt(watchedPaths)
            else {
                recordBlockedSidebarPerformanceProofDiagnostic(
                    action: action,
                    reason: "required_watched_root_scan_timeout_or_debt"
                )
                return nil
            }
            let rootURLs = SidebarPerformanceProofFixture.strictWatchedRootURLs
            guard
                rootURLs.allSatisfy({ rootURL in
                    !summary.repoPaths(in: rootURL).isEmpty
                }),
                summary.filesystemLogicalDebtCount == 0,
                let topologyFingerprint = summary.topologyFingerprint
            else {
                recordBlockedSidebarPerformanceProofDiagnostic(
                    action: action,
                    reason: "required_watched_root_scan_incomplete"
                )
                return nil
            }

            let terminalPane: Pane?
            if population == .zeroPTYIdle {
                terminalPane = nil
            } else {
                terminalPane = workspaceSurfaceCoordinator.openFloatingTerminal(
                    launchDirectory: rootURLs[1],
                    title: "Sidebar Performance Terminal"
                )
                guard terminalPane?.metadata.contentType == .terminal else {
                    recordBlockedSidebarPerformanceProofDiagnostic(
                        action: action,
                        reason: "terminal_fixture_failed"
                    )
                    return nil
                }
            }

            guard SidebarPerformanceProofFixture.populateStrictPaneFleet(store: store) else {
                recordBlockedSidebarPerformanceProofDiagnostic(
                    action: action,
                    reason: "pane_fleet_failed"
                )
                return nil
            }
            atomStore.core.workspaceSidebarState.setSidebarSurface(.repos)
            mainWindowController?.expandSidebar()

            if let terminalPane {
                workspaceSurfaceCoordinator.restoreVisiblePaneIfNeeded(
                    terminalPane.id,
                    forceWhenBoundsExist: true
                )
                await Task.yield()
                mainWindowController?.syncVisibleTerminalGeometry(
                    reason: "sidebarPerformanceProof"
                )
                let terminalRenderProof = await waitForIPCTerminalSmokeRenderProof(
                    for: terminalPane.id
                )
                guard terminalRenderProof.succeeded else {
                    recordBlockedSidebarPerformanceProofDiagnostic(
                        action: action,
                        reason: "terminal_render_failed"
                    )
                    return nil
                }
            }

            let repositoryCount = rootURLs.reduce(into: 0) { count, rootURL in
                count += summary.repoPaths(in: rootURL).count
            }
            let linkedWorktreeCount = rootURLs.reduce(into: 0) { count, rootURL in
                count += summary.linkedWorktreePaths(in: rootURL).count
            }
            return StrictSidebarPerformanceFixtureEvidence(
                repositoryCount: repositoryCount,
                worktreeCount: repositoryCount + linkedWorktreeCount,
                topologyFingerprint: topologyFingerprint,
                expectedSessionCount: population == .zeroPTYIdle
                    ? AppPolicies.SidebarPerformanceProof.zeroPTYExpectedSessionCount
                    : AppPolicies.SidebarPerformanceProof.mountedPTYExpectedSessionCount
            )
        }

        private func refreshStrictWatchedRootsAndAwaitZeroLogicalDebt(
            _ watchedPaths: [WatchedPath]
        ) async -> WatchedFolderRefreshSummary? {
            let commands = watchedFolderCommands!
            let timeout = AppPolicies.SidebarPerformanceProof.fixturePreparationTimeout
            let observationInterval = AppPolicies.SidebarPerformanceProof.fixtureStateObservationInterval
            return await withTaskGroup(of: WatchedFolderRefreshSummary?.self) { group in
                group.addTask {
                    let summary = await commands.refreshWatchedFolders(watchedPaths)
                    while !Task.isCancelled {
                        let logicalDebtCount = await commands.filesystemLogicalDebtCount()
                        if logicalDebtCount == 0 {
                            return summary.replacingFilesystemLogicalDebtCount(logicalDebtCount)
                        }
                        do {
                            try await AsyncDelay.taskSleep.wait(observationInterval)
                        } catch {
                            return nil
                        }
                    }
                    return nil
                }
                group.addTask {
                    do {
                        try await AsyncDelay.taskSleep.wait(timeout)
                    } catch {
                        return nil
                    }
                    return nil
                }
                guard let result = await group.next() else {
                    group.cancelAll()
                    return nil
                }
                group.cancelAll()
                return result
            }
        }

        private func recordStrictSidebarPopulationResult(
            action: AgentStudioStartupDiagnosticAction,
            outcome: String
        ) {
            startupTraceRecorder.recordAppStartup(
                "app.startup_diagnostic_action.completed",
                phase: "startup_diagnostic_action",
                outcome: outcome,
                attributes: startupDiagnosticTraceAttributes(for: action).merging(
                    sidebarPerformanceProofPolicyAttributes()
                ) { _, newValue in newValue }
            )
        }
    }

    @MainActor
    struct SidebarPerformanceProofNativeInputDriver {
        private let delay: AsyncDelay

        init(delay: AsyncDelay = .taskSleep) {
            self.delay = delay
        }

        func typeFixtureQuery(in window: NSWindow) async -> Bool {
            let query = AppPolicies.SidebarPerformanceProof.fixtureQuery
            guard query.count == AppPolicies.SidebarPerformanceProof.searchCharacterCount,
                window.firstResponder is NSTextView
            else { return false }

            for character in query {
                guard let keyCode = Self.keyCodeByCharacter[character],
                    sendKey(
                        character: String(character),
                        keyCode: keyCode,
                        modifiers: [],
                        to: window
                    )
                else { return false }
                do {
                    try await delay.wait(AppPolicies.SidebarPerformanceProof.searchCharacterInterval)
                } catch {
                    return false
                }
            }

            return (window.firstResponder as? NSTextView)?.string == query
        }

        func clearFixtureQuery(in window: NSWindow) -> Bool {
            guard sendKey(character: "a", keyCode: 0, modifiers: [.command], to: window),
                sendKey(character: "", keyCode: 51, modifiers: [], to: window)
            else { return false }
            return (window.firstResponder as? NSTextView)?.string.isEmpty == true
        }

        private func sendKey(
            character: String,
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags,
            to window: NSWindow
        ) -> Bool {
            guard
                let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: character,
                    charactersIgnoringModifiers: character,
                    isARepeat: false,
                    keyCode: keyCode
                )
            else { return false }
            window.sendEvent(event)
            return true
        }

        private static let keyCodeByCharacter: [Character: UInt16] = [
            "w": 13,
            "o": 31,
            "r": 15,
            "k": 40,
            "t": 17,
            "e": 14,
        ]
    }
#endif
