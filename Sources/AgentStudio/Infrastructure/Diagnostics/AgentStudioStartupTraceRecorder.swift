import Foundation

final class AgentStudioStartupTraceRecorder: @unchecked Sendable {
    private let traceRuntime: AgentStudioTraceRuntime?
    private let eventQueue: AgentStudioTraceEventQueue?
    private let lock = NSLock()
    private var firstGhosttyActionKeys: Set<String> = []
    private var firstOutputKeys: Set<String> = []
    private var cwdReadyKeys: Set<String> = []
    private var titleReadyKeys: Set<String> = []
    private var childExitedKeys: Set<String> = []

    private enum StartupMilestone {
        case firstGhosttyAction
        case firstOutput
        case cwdReady
        case titleReady
        case childExited
    }

    init(traceRuntime: AgentStudioTraceRuntime?) {
        self.traceRuntime = traceRuntime
        if let traceRuntime, traceRuntime.isEnabled {
            self.eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            self.eventQueue = nil
        }
    }

    func recordAppStartup(
        _ body: String,
        phase: String,
        outcome: String? = nil,
        attributes: [String: AgentStudioTraceValue] = [:]
    ) {
        var mergedAttributes = attributes
        mergedAttributes["agentstudio.app.startup.phase"] = .string(phase)
        if let outcome {
            mergedAttributes["agentstudio.app.startup.outcome"] = .string(outcome)
        }
        record(tag: .appStartup, body: body, attributes: mergedAttributes)
    }

    func recordWorkspaceBootStep(rawValue: String, purpose: String) {
        recordAppStartup(
            "workspace.boot.step",
            phase: "workspace_boot",
            attributes: [
                "agentstudio.workspace.boot.step": .string(rawValue),
                "agentstudio.workspace.boot.purpose": .string(purpose),
            ]
        )
    }

    func recordZmxStartupReconciliation(_ summary: ZmxStartupReconciliationSummary) {
        recordAppStartup(
            "app.zmx_startup_reconciliation.completed",
            phase: "zmx_startup_reconciliation",
            outcome: summary.inventoryOutcome.rawValue,
            attributes: [
                "agentstudio.zmx.startup.inventory_outcome": .string(summary.inventoryOutcome.rawValue),
                "agentstudio.zmx.startup.live_session_count": .int(summary.liveSessionCount),
                "agentstudio.zmx.startup.hydrated_anchor_count": .int(summary.hydratedAnchorCount),
                "agentstudio.zmx.startup.protected_session_count": .int(summary.protectedSessionCount),
                "agentstudio.zmx.startup.unresolved_candidate_count": .int(summary.unresolvedCandidateCount),
                "agentstudio.zmx.startup.unmatched_live_session_count": .int(summary.unmatchedLiveSessionCount),
            ]
        )
    }

    func recordTerminalStartup(
        _ body: String,
        paneID: UUID,
        parentPaneID: UUID? = nil,
        surfaceID: UUID? = nil,
        phase: String,
        outcome: String? = nil,
        provider: String? = nil,
        attributes: [String: AgentStudioTraceValue] = [:]
    ) {
        var mergedAttributes = attributes
        mergedAttributes["agentstudio.pane.id"] = .string(paneID.uuidString)
        mergedAttributes["agentstudio.terminal.startup.phase"] = .string(phase)
        if let parentPaneID {
            mergedAttributes["agentstudio.pane.parent_id"] = .string(parentPaneID.uuidString)
        }
        if let surfaceID {
            mergedAttributes["agentstudio.surface.id"] = .string(surfaceID.uuidString)
        }
        if let provider {
            mergedAttributes["agentstudio.terminal.provider"] = .string(provider)
        }
        if let outcome {
            mergedAttributes["agentstudio.terminal.startup.outcome"] = .string(outcome)
        }
        record(tag: .terminalStartup, body: body, attributes: mergedAttributes)
    }

    func recordTerminalCommandReceived(
        commandName: String,
        source: String,
        attributes: [String: AgentStudioTraceValue] = [:]
    ) {
        var mergedAttributes = attributes
        mergedAttributes["agentstudio.command.name"] = .string(commandName)
        mergedAttributes["agentstudio.command.source"] = .string(source)
        mergedAttributes["agentstudio.terminal.startup.phase"] = .string("command_received")
        record(
            tag: .terminalStartup,
            body: "terminal.startup.command_received",
            attributes: mergedAttributes
        )
    }

    func recordFirstGhosttyAction(paneID: UUID, surfaceID: UUID, actionName: String) {
        guard
            shouldRecordFirst(
                key: paneSurfaceKey(paneID: paneID, surfaceID: surfaceID),
                milestone: .firstGhosttyAction
            )
        else { return }
        recordTerminalStartup(
            "terminal.startup.first_ghostty_action",
            paneID: paneID,
            surfaceID: surfaceID,
            phase: "first_ghostty_action",
            attributes: [
                "agentstudio.ghostty.action": .string(actionName)
            ]
        )
    }

    func recordFirstOutput(paneID: UUID, surfaceID: UUID?) {
        guard
            shouldRecordFirst(
                key: paneSurfaceKey(paneID: paneID, surfaceID: surfaceID),
                milestone: .firstOutput
            )
        else { return }
        recordTerminalStartup(
            "terminal.startup.first_output",
            paneID: paneID,
            surfaceID: surfaceID,
            phase: "first_output"
        )
    }

    func recordCwdReady(paneID: UUID, surfaceID: UUID?) {
        guard
            shouldRecordFirst(
                key: paneSurfaceKey(paneID: paneID, surfaceID: surfaceID),
                milestone: .cwdReady
            )
        else { return }
        recordTerminalStartup(
            "terminal.startup.cwd_ready",
            paneID: paneID,
            surfaceID: surfaceID,
            phase: "cwd_ready"
        )
    }

    func recordTitleReady(paneID: UUID, surfaceID: UUID?) {
        guard
            shouldRecordFirst(
                key: paneSurfaceKey(paneID: paneID, surfaceID: surfaceID),
                milestone: .titleReady
            )
        else { return }
        recordTerminalStartup(
            "terminal.startup.title_ready",
            paneID: paneID,
            surfaceID: surfaceID,
            phase: "title_ready"
        )
    }

    func recordChildExited(paneID: UUID, surfaceID: UUID, actionName: String) {
        guard
            shouldRecordFirst(
                key: paneSurfaceKey(paneID: paneID, surfaceID: surfaceID),
                milestone: .childExited
            )
        else { return }
        recordTerminalStartup(
            "terminal.startup.child_exited",
            paneID: paneID,
            surfaceID: surfaceID,
            phase: "child_exited",
            outcome: "failed",
            attributes: [
                "agentstudio.ghostty.action": .string(actionName)
            ]
        )
    }

    func drain() async throws {
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    func cancel() {
        eventQueue?.cancel()
    }

    private func record(
        tag: AgentStudioTraceTag,
        body: String,
        attributes: [String: AgentStudioTraceValue]
    ) {
        guard let traceRuntime, traceRuntime.isEnabled(tag), let eventQueue else { return }
        eventQueue.record(
            tag: tag,
            body: body,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }

    private func shouldRecordFirst(key: String, milestone: StartupMilestone) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        switch milestone {
        case .firstGhosttyAction:
            guard !firstGhosttyActionKeys.contains(key) else { return false }
            firstGhosttyActionKeys.insert(key)
        case .firstOutput:
            guard !firstOutputKeys.contains(key) else { return false }
            firstOutputKeys.insert(key)
        case .cwdReady:
            guard !cwdReadyKeys.contains(key) else { return false }
            cwdReadyKeys.insert(key)
        case .titleReady:
            guard !titleReadyKeys.contains(key) else { return false }
            titleReadyKeys.insert(key)
        case .childExited:
            guard !childExitedKeys.contains(key) else { return false }
            childExitedKeys.insert(key)
        }
        return true
    }

    private func paneSurfaceKey(paneID: UUID, surfaceID: UUID?) -> String {
        "\(paneID.uuidString):\(surfaceID?.uuidString ?? "unknown-surface")"
    }
}
