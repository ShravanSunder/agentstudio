import Foundation

package struct AgentStudioTraceWorktreeIdentity: Equatable, Sendable {
    let repoHash: String
    let worktreeHash: String
    let branch: String?

    package init(
        repoHash: String,
        worktreeHash: String,
        branch: String?
    ) {
        self.repoHash = repoHash
        self.worktreeHash = worktreeHash
        self.branch = branch
    }
}

package struct AgentStudioTraceIdentitySnapshot: Equatable, Sendable {
    let worktreeIdentitiesByWorktreeId: [UUID: AgentStudioTraceWorktreeIdentity]
    let paneWorktreeIdsByPaneId: [UUID: UUID]

    package init(
        worktreeIdentitiesByWorktreeId: [UUID: AgentStudioTraceWorktreeIdentity] = [:],
        paneWorktreeIdsByPaneId: [UUID: UUID] = [:]
    ) {
        self.worktreeIdentitiesByWorktreeId = worktreeIdentitiesByWorktreeId
        self.paneWorktreeIdsByPaneId = paneWorktreeIdsByPaneId
    }

    static let empty = Self()
}

package enum AgentStudioTraceIdentityUpdateOutcome: Equatable, Sendable {
    case applied
    case equalSuppressed
}

actor AgentStudioTraceIdentityStore {
    private var snapshot: AgentStudioTraceIdentitySnapshot

    init(snapshot: AgentStudioTraceIdentitySnapshot = .empty) {
        self.snapshot = snapshot
    }

    @discardableResult
    func update(_ snapshot: AgentStudioTraceIdentitySnapshot) -> AgentStudioTraceIdentityUpdateOutcome {
        guard snapshot != self.snapshot else { return .equalSuppressed }
        self.snapshot = snapshot
        return .applied
    }

    func resourceAttributes(
        for attributes: [String: AgentStudioTraceValue],
        baseResource: [String: String]
    ) -> [String: String] {
        guard let identity = identity(for: attributes) else {
            return baseResource
        }

        var resource = baseResource
        resource["dev.repo.hash"] = identity.repoHash
        resource["dev.worktree.hash"] = identity.worktreeHash
        if let branch = identity.branch {
            resource["dev.branch.name"] = branch
        }
        return resource
    }

    private func identity(for attributes: [String: AgentStudioTraceValue]) -> AgentStudioTraceWorktreeIdentity? {
        if let worktreeId = uuidAttribute(named: "agentstudio.worktree.id", in: attributes),
            let identity = snapshot.worktreeIdentitiesByWorktreeId[worktreeId]
        {
            return identity
        }

        guard
            let paneId = uuidAttribute(named: "agentstudio.pane.id", in: attributes),
            let worktreeId = snapshot.paneWorktreeIdsByPaneId[paneId]
        else { return nil }
        return snapshot.worktreeIdentitiesByWorktreeId[worktreeId]
    }

    private func uuidAttribute(
        named key: String,
        in attributes: [String: AgentStudioTraceValue]
    ) -> UUID? {
        guard case .string(let rawValue) = attributes[key] else { return nil }
        return UUID(uuidString: rawValue)
    }
}
