import AgentStudioInfrastructure
import AppKit

#if DEBUG
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
            ]
        }

        func runStrictSidebarCPUPopulationDiagnostic(
            action: AgentStudioStartupDiagnosticAction
        ) async {
            guard let population = SidebarPerformanceProofPopulation(kind: action.kind),
                let window = mainWindowController?.window
            else {
                recordStrictSidebarPopulationResult(action: action, outcome: "failed")
                return
            }
            let session = SidebarPerformanceProofSession(
                population: population,
                window: window,
                recorder: startupTraceRecorder
            )
            sidebarPerformanceProofSession = session
            defer { sidebarPerformanceProofSession = nil }

            let prepared: Bool
            if population == .zeroPTYIdle {
                atomStore.core.workspaceSidebarState.setSidebarSurface(.repos)
                mainWindowController?.expandSidebar()
                SidebarPerformanceProofFixture.populateRealSizeTopology(
                    store: store,
                    repositoryRoot: FileManager.default.homeDirectoryForCurrentUser
                )
                SidebarPerformanceProofFixture.populateRealSizePaneFleet(store: store)
                prepared = true
            } else {
                prepared = await prepareSidebarPerformanceProofFixture(action: action) != nil
            }
            guard prepared else {
                recordStrictSidebarPopulationResult(action: action, outcome: "failed")
                return
            }
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

        func typeAndClearFixtureQuery(in window: NSWindow) async -> Bool {
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

            guard sendKey(character: "a", keyCode: 0, modifiers: [.command], to: window),
                sendKey(character: "", keyCode: 51, modifiers: [], to: window)
            else { return false }
            return window.firstResponder is NSTextView
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
