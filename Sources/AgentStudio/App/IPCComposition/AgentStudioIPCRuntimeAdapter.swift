import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation

@MainActor
protocol AppIPCRuntimeCommandDispatching: Sendable {
    func dispatchRuntimeCommand(
        _ command: RuntimeCommand,
        target: RuntimeCommandTarget,
        correlationId: UUID?
    ) async -> ActionResult
}

@MainActor
struct ActionExecutorRuntimeCommandDispatcher: AppIPCRuntimeCommandDispatching, @unchecked Sendable {
    private let actionExecutor: ActionExecutor

    init(actionExecutor: ActionExecutor) {
        self.actionExecutor = actionExecutor
    }

    func dispatchRuntimeCommand(
        _ command: RuntimeCommand,
        target: RuntimeCommandTarget,
        correlationId: UUID?
    ) async -> ActionResult {
        await actionExecutor.dispatchRuntimeCommand(command, target: target, correlationId: correlationId)
    }
}

@MainActor
struct AgentStudioIPCRuntimeAdapter: AppIPCRuntimePort, @unchecked Sendable {
    private let workspaceStore: WorkspaceStore
    private let runtimeRegistry: RuntimeRegistry
    private let commandDispatcher: any AppIPCRuntimeCommandDispatching

    init(
        workspaceStore: WorkspaceStore,
        runtimeRegistry: RuntimeRegistry,
        commandDispatcher: any AppIPCRuntimeCommandDispatching
    ) {
        self.workspaceStore = workspaceStore
        self.runtimeRegistry = runtimeRegistry
        self.commandDispatcher = commandDispatcher
    }

    func terminalStatus(_ handle: IPCHandle) throws -> IPCTerminalStatusResult {
        let paneId = try resolveTerminalPaneId(handle)
        let runtimeSnapshot = try terminalRuntimeSnapshot(for: paneId)
        return IPCTerminalStatusResult(
            paneId: paneId,
            lifecycle: IPCRuntimeLifecycle(runtimeSnapshot.lifecycle),
            isReady: runtimeSnapshot.lifecycle == .ready,
            backend: IPCExecutionBackendKind(runtimeSnapshot.metadata.executionBackend),
            capabilities: capabilityNames(runtimeSnapshot.capabilities)
        )
    }

    func terminalSnapshot(_ handle: IPCHandle) throws -> IPCTerminalSnapshotResult {
        let paneId = try resolveTerminalPaneId(handle)
        let runtime = try terminalRuntime(for: paneId)
        let runtimeSnapshot = runtime.snapshot()
        let terminalRuntime = runtime as? TerminalRuntime
        return IPCTerminalSnapshotResult(
            paneId: paneId,
            lifecycle: IPCRuntimeLifecycle(runtimeSnapshot.lifecycle),
            backend: IPCExecutionBackendKind(runtimeSnapshot.metadata.executionBackend),
            capabilities: capabilityNames(runtimeSnapshot.capabilities),
            lastSequence: runtimeSnapshot.lastSeq,
            timestamp: runtimeSnapshot.timestamp,
            rendererHealthy: terminalRuntime?.rendererHealthy,
            readOnly: terminalRuntime?.isReadOnly,
            secureInput: terminalRuntime?.isSecureInput
        )
    }

    func sendTerminalInput(
        to handle: IPCHandle,
        input: String,
        correlationId: UUID?
    ) async throws -> IPCTerminalSendInputResult {
        let paneId = try resolveTerminalPaneId(handle)
        _ = try terminalRuntime(for: paneId)

        let result = await commandDispatcher.dispatchRuntimeCommand(
            .terminal(.sendInput(input)),
            target: .pane(PaneId(uuid: paneId)),
            correlationId: correlationId
        )
        return try mapTerminalSendResult(result, paneId: paneId, correlationId: correlationId)
    }

    private func terminalRuntimeSnapshot(for paneId: UUID) throws -> PaneRuntimeSnapshot {
        try terminalRuntime(for: paneId).snapshot()
    }

    private func terminalRuntime(for paneId: UUID) throws -> any PaneRuntime {
        guard let runtime = runtimeRegistry.runtime(for: PaneId(uuid: paneId)) else {
            throw AppIPCRuntimeError(reason: .noRuntime)
        }
        guard runtime.metadata.contentType == .terminal else {
            throw AppIPCRuntimeError(reason: .unsupportedCommand)
        }
        return runtime
    }

    private func resolveTerminalPaneId(_ handle: IPCHandle) throws -> UUID {
        guard handle.kind == .pane else {
            throw AppIPCRuntimeError(reason: .validationRejected)
        }

        let snapshot = workspaceStore.programmaticControlSnapshot()
        let pane: ProgrammaticControlPaneSnapshot?
        switch handle.reference {
        case .canonicalUUID(let paneId):
            pane = snapshot.panes.first { $0.id == paneId }
        case .friendlyOrdinal(let ordinal):
            pane = snapshot.panes[safe: ordinal - 1]
        }

        guard let pane else {
            throw AppIPCRuntimeError(reason: .targetNotFound)
        }
        guard pane.contentKind == .terminal else {
            throw AppIPCRuntimeError(reason: .unsupportedCommand)
        }
        return pane.id
    }

    private func mapTerminalSendResult(
        _ result: ActionResult,
        paneId: UUID,
        correlationId: UUID?
    ) throws -> IPCTerminalSendInputResult {
        switch result {
        case .success(let commandId):
            return IPCTerminalSendInputResult(
                paneId: paneId,
                commandId: commandId,
                correlationId: correlationId,
                disposition: .accepted,
                queuePosition: nil
            )
        case .queued(let commandId, let position):
            return IPCTerminalSendInputResult(
                paneId: paneId,
                commandId: commandId,
                correlationId: correlationId,
                disposition: .queued,
                queuePosition: position
            )
        case .failure(let error):
            throw AppIPCRuntimeError(error)
        }
    }

    private func capabilityNames(_ capabilities: Set<PaneCapability>) -> [String] {
        capabilities.map { capability in
            switch capability {
            case .input:
                return "input"
            case .resize:
                return "resize"
            case .search:
                return "search"
            case .navigation:
                return "navigation"
            case .diffReview:
                return "diffReview"
            case .editorActions:
                return "editorActions"
            case .plugin(let name):
                return "plugin:\(name)"
            }
        }
        .sorted()
    }
}

extension AppIPCRuntimeError {
    fileprivate init(_ actionError: ActionError) {
        switch actionError {
        case .runtimeNotReady(let lifecycle):
            self.init(reason: .runtimeNotReady, detail: String(describing: lifecycle))
        case .unsupportedCommand(let command, let required):
            self.init(reason: .unsupportedCommand, detail: "\(command) requires \(required)")
        case .invalidPayload(let description):
            self.init(reason: .validationRejected, detail: description)
        case .backendUnavailable(let backend):
            self.init(reason: .backendUnavailable, detail: backend)
        case .timeout(let commandId):
            self.init(reason: .timeout, detail: commandId.uuidString)
        }
    }
}

extension IPCRuntimeLifecycle {
    fileprivate init(_ lifecycle: PaneRuntimeLifecycle) {
        switch lifecycle {
        case .created:
            self = .created
        case .ready:
            self = .ready
        case .draining:
            self = .draining
        case .terminated:
            self = .terminated
        }
    }
}

extension IPCExecutionBackendKind {
    fileprivate init(_ backend: ExecutionBackend) {
        switch backend {
        case .local:
            self = .local
        case .docker:
            self = .docker
        case .gondolin:
            self = .gondolin
        case .remote:
            self = .remote
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
