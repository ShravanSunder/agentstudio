import AppKit
import Foundation

@MainActor
extension PaneCoordinator {
    func traceTerminalCommandReceived(commandName: String, source: String = "pane_coordinator") {
        let operationID = UUID().uuidString
        pendingTerminalStartupOperationID = operationID
        startupTraceRecorder?.recordTerminalCommandReceived(
            commandName: commandName,
            source: source,
            attributes: [
                "agentstudio.terminal.startup.operation_id": .string(operationID)
            ]
        )
    }

    func clearUnclaimedTerminalStartupOperation() {
        pendingTerminalStartupOperationID = nil
    }

    func traceTerminalCommandReceived(for action: PaneActionCommand) {
        switch action {
        case .openWorktree:
            traceTerminalCommandReceived(commandName: "openWorktree", source: "pane_action")
        case .openNewTerminalInTab:
            traceTerminalCommandReceived(commandName: "openNewTerminalInTab", source: "pane_action")
        case .openWorktreeInPane:
            traceTerminalCommandReceived(commandName: "openWorktreeInPane", source: "pane_action")
        case .openFloatingTerminal:
            traceTerminalCommandReceived(commandName: "openFloatingTerminal", source: "pane_action")
        case .addDrawerPane:
            traceTerminalCommandReceived(commandName: "addDrawerPane", source: "pane_action")
        default:
            break
        }
    }

    func prepareTerminalPaneSlot(_ pane: Pane) {
        assignStartupOperationIDIfNeeded(to: pane.id)
        traceTerminalPaneCreated(pane)
        viewRegistry.ensureSlot(for: pane.id)
    }

    func traceTerminalPaneCreated(_ pane: Pane) {
        traceTerminalStartup("terminal.startup.pane_created", pane: pane, phase: "pane_created")
    }

    func traceTerminalLayoutInserted(_ pane: Pane) {
        traceTerminalStartup("terminal.startup.layout_inserted", pane: pane, phase: "layout_inserted")
    }

    func traceTerminalViewCreateStarted(_ pane: Pane) {
        traceTerminalStartup("terminal.startup.view_create_started", pane: pane, phase: "view_create_started")
    }

    func traceTerminalLayoutInsertedAndViewCreateStarted(_ pane: Pane) {
        traceTerminalLayoutInserted(pane)
        traceTerminalViewCreateStarted(pane)
    }

    func traceZmxAttachFailed(pane: Pane) {
        traceTerminalStartup(
            "terminal.startup.zmx_attach_prepared",
            pane: pane,
            phase: "zmx_attach_prepared",
            outcome: "failed"
        )
    }

    func traceSurfaceCreateStarted(
        pane: Pane,
        initialFrame: NSRect?,
        startupCommandPresent: Bool,
        environmentVariableCount: Int
    ) {
        traceTerminalStartup(
            "terminal.startup.surface_create_started",
            pane: pane,
            phase: "surface_create_started",
            attributes: surfaceCreationEnvironmentAttributes(
                initialFrame: initialFrame,
                startupCommandPresent: startupCommandPresent,
                environmentVariableCount: environmentVariableCount
            )
        )
    }

    func traceSurfaceCreateSucceeded(pane: Pane, surfaceID: UUID) {
        traceTerminalStartup(
            "terminal.startup.surface_create_succeeded",
            pane: pane,
            phase: "surface_create_succeeded",
            outcome: "succeeded",
            surfaceID: surfaceID
        )
    }

    func traceSurfaceAttached(pane: Pane, surfaceID: UUID) {
        traceTerminalStartup(
            "terminal.startup.surface_attached",
            pane: pane,
            phase: "surface_attached",
            surfaceID: surfaceID
        )
    }

    func traceSurfaceDisplayed(pane: Pane, surfaceID: UUID) {
        traceTerminalStartup(
            "terminal.startup.surface_displayed",
            pane: pane,
            phase: "surface_displayed",
            surfaceID: surfaceID
        )
        finishStartupOperation(for: pane.id)
    }

    func traceSurfaceCreateFailed(
        pane: Pane,
        error: SurfaceError,
        initialFrame: NSRect?,
        startupCommandPresent: Bool,
        environmentVariableCount: Int
    ) {
        var attributes = surfaceCreationEnvironmentAttributes(
            initialFrame: initialFrame,
            startupCommandPresent: startupCommandPresent,
            environmentVariableCount: environmentVariableCount
        )
        attributes["agentstudio.terminal.startup.error"] = .string(error.localizedDescription)
        traceTerminalStartup(
            "terminal.startup.surface_create_failed",
            pane: pane,
            phase: "surface_create_failed",
            outcome: "failed",
            attributes: attributes
        )
        finishStartupOperation(for: pane.id)
    }

    func traceTerminalStartup(
        _ body: String,
        pane: Pane,
        phase: String,
        outcome: String? = nil,
        surfaceID: UUID? = nil,
        attributes: [String: AgentStudioTraceValue] = [:]
    ) {
        guard let startupTraceRecorder else { return }

        var mergedAttributes = attributes
        mergedAttributes["agentstudio.pane.kind"] = .string(Self.startupTraceContentType(for: pane.content))
        if let repoId = pane.repoId {
            mergedAttributes["agentstudio.repo.id"] = .string(repoId.uuidString)
        }
        if let worktreeId = pane.worktreeId {
            mergedAttributes["agentstudio.worktree.id"] = .string(worktreeId.uuidString)
        }
        if let operationID = terminalStartupOperationIDsByPaneID[pane.id] {
            mergedAttributes["agentstudio.terminal.startup.operation_id"] = .string(operationID)
        }
        startupTraceRecorder.recordTerminalStartup(
            body,
            paneID: pane.id,
            parentPaneID: pane.parentPaneId,
            surfaceID: surfaceID,
            phase: phase,
            outcome: outcome,
            provider: pane.provider?.rawValue,
            attributes: mergedAttributes
        )
    }

    private func assignStartupOperationIDIfNeeded(to paneID: UUID) {
        if terminalStartupOperationIDsByPaneID[paneID] != nil {
            return
        }
        let operationID = pendingTerminalStartupOperationID ?? UUID().uuidString
        terminalStartupOperationIDsByPaneID[paneID] = operationID
        pendingTerminalStartupOperationID = nil
    }

    private func finishStartupOperation(for paneID: UUID) {
        terminalStartupOperationIDsByPaneID[paneID] = nil
    }

    func traceZmxAttachPrepared(
        pane: Pane,
        diagnostics: TerminalRestoreRuntime.ZmxAttachDiagnostics?
    ) {
        var attributes: [String: AgentStudioTraceValue] = [:]
        if let diagnostics {
            attributes["agentstudio.zmx.session_id"] = .string(diagnostics.sessionId)
            attributes["agentstudio.zmx.socket_path_len"] = .int(diagnostics.socketPathLength)
            attributes["agentstudio.zmx.socket_path_headroom"] = .int(diagnostics.socketPathHeadroom)
        } else {
            attributes["agentstudio.terminal.startup.outcome"] = .string("missing_zmx_diagnostics")
        }
        traceTerminalStartup(
            "terminal.startup.zmx_attach_prepared",
            pane: pane,
            phase: "zmx_attach_prepared",
            attributes: attributes
        )
    }

    private static func startupTraceContentType(for content: PaneContent) -> String {
        switch content {
        case .terminal:
            "terminal"
        case .webview:
            "webview"
        case .bridgePanel:
            "bridgePanel"
        case .codeViewer:
            "codeViewer"
        case .unsupported(let unsupportedContent):
            unsupportedContent.type
        }
    }

    private func surfaceCreationEnvironmentAttributes(
        initialFrame: NSRect?,
        startupCommandPresent: Bool,
        environmentVariableCount: Int
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.app.is_active": .bool(NSApplication.shared.isActive),
            "agentstudio.app.activation_policy": .string(Self.startupTraceActivationPolicyName()),
            "agentstudio.display.count": .int(NSScreen.screens.count),
            "agentstudio.ghostty.surface.startup_command_present": .bool(startupCommandPresent),
            "agentstudio.ghostty.surface.environment_variable_count": .int(environmentVariableCount),
        ]

        if let mainScreen = NSScreen.main {
            attributes["agentstudio.display.main_scale_factor"] = .double(Double(mainScreen.backingScaleFactor))
        }

        if let initialFrame {
            attributes["agentstudio.ghostty.surface.initial_frame_width"] = .double(Double(initialFrame.width))
            attributes["agentstudio.ghostty.surface.initial_frame_height"] = .double(Double(initialFrame.height))
        } else {
            attributes["agentstudio.ghostty.surface.initial_frame_present"] = .bool(false)
        }

        return attributes
    }

    private static func startupTraceActivationPolicyName() -> String {
        switch NSApplication.shared.activationPolicy() {
        case .accessory:
            "accessory"
        case .prohibited:
            "prohibited"
        case .regular:
            "regular"
        @unknown default:
            "unknown"
        }
    }
}
