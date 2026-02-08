import Foundation
@testable import AgentStudio

/// Mock backend for testing SessionRegistry without real tmux.
final class MockSessionBackend: SessionBackend, @unchecked Sendable {
    var isAvailableResult: Bool = true
    var healthCheckResult: Bool = true
    var sessionExistsResult: Bool = true
    var socketExistsResult: Bool = true
    var orphanSessions: [String] = []

    var throwOnDestroy: Bool = false

    var createCalls: [(UUID, Worktree, UUID)] = []
    var destroyCalls: [PaneSessionHandle] = []
    var healthCheckCalls: [PaneSessionHandle] = []
    var destroyByIdCalls: [String] = []

    /// Pre-configured handle to return from createPaneSession.
    var createResult: Result<PaneSessionHandle, Error> = .failure(SessionBackendError.notAvailable)

    var isAvailable: Bool {
        get async { isAvailableResult }
    }

    func createPaneSession(projectId: UUID, worktree: Worktree, paneId: UUID) async throws -> PaneSessionHandle {
        createCalls.append((projectId, worktree, paneId))
        return try createResult.get()
    }

    func attachCommand(for handle: PaneSessionHandle) -> String {
        "mock-attach \(handle.id)"
    }

    func destroyPaneSession(_ handle: PaneSessionHandle) async throws {
        destroyCalls.append(handle)
        if throwOnDestroy {
            throw SessionBackendError.operationFailed("Mock destroy failure")
        }
    }

    func healthCheck(_ handle: PaneSessionHandle) async -> Bool {
        healthCheckCalls.append(handle)
        return healthCheckResult
    }

    func socketExists() -> Bool {
        socketExistsResult
    }

    func sessionExists(_ handle: PaneSessionHandle) async -> Bool {
        sessionExistsResult
    }

    func discoverOrphanSessions(excluding knownIds: Set<String>) async -> [String] {
        orphanSessions.filter { !knownIds.contains($0) }
    }

    func destroySessionById(_ sessionId: String) async throws {
        destroyByIdCalls.append(sessionId)
    }
}
