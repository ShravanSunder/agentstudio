import AgentStudioAppIPC
import Foundation

/// Answers own-pane questions from a fixed table, standing in for the App's
/// pane graph where a test proves admission rather than App wiring. A bound
/// pane missing from the table is a main-layout terminal with an empty drawer,
/// unless the port models vanished panes.
struct StaticOwnPaneScopePort: AppIPCOwnPaneScopePort {
    let scopesByBoundPaneId: [UUID: AppIPCOwnPaneScope]
    let unlistedPanesExist: Bool
    let authorizationLog: AgentAuthorizationLog?

    nonisolated init(
        scopes: [AppIPCOwnPaneScope] = [],
        unlistedPanesExist: Bool = true,
        authorizationLog: AgentAuthorizationLog? = nil
    ) {
        scopesByBoundPaneId = Dictionary(uniqueKeysWithValues: scopes.map { ($0.boundPaneId, $0) })
        self.unlistedPanesExist = unlistedPanesExist
        self.authorizationLog = authorizationLog
    }

    nonisolated func recordAgentAuthorization(elapsed: Duration, outcome: AppIPCAgentAuthorizationOutcome) {
        authorizationLog?.append(outcome)
    }

    func ownPaneScope(boundPaneId: UUID) -> AppIPCOwnPaneScope? {
        if let scope = scopesByBoundPaneId[boundPaneId] { return scope }
        guard unlistedPanesExist else { return nil }
        return AppIPCOwnPaneScope(boundPaneId: boundPaneId, isDrawerTerminal: false, drawerChildPaneIds: [])
    }
}

/// The authorization-time samples a port received, in order.
final class AgentAuthorizationLog: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var outcomesStorage: [AppIPCAgentAuthorizationOutcome] = []

    nonisolated init() {}

    nonisolated var outcomes: [AppIPCAgentAuthorizationOutcome] {
        lock.withLock { outcomesStorage }
    }

    nonisolated func append(_ outcome: AppIPCAgentAuthorizationOutcome) {
        lock.withLock { outcomesStorage.append(outcome) }
    }
}
