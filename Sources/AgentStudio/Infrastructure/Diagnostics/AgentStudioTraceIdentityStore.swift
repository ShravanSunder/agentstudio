import Foundation

struct AgentStudioTraceWorktreeIdentity: Equatable, Sendable {
    let repoHash: String
    let worktreeHash: String
    let branch: String?
}

struct AgentStudioTraceIdentitySnapshot: Equatable, Sendable {
    let worktreeIdentitiesByWorktreeId: [UUID: AgentStudioTraceWorktreeIdentity]
    let paneWorktreeIdsByPaneId: [UUID: UUID]

    init(
        worktreeIdentitiesByWorktreeId: [UUID: AgentStudioTraceWorktreeIdentity] = [:],
        paneWorktreeIdsByPaneId: [UUID: UUID] = [:]
    ) {
        self.worktreeIdentitiesByWorktreeId = worktreeIdentitiesByWorktreeId
        self.paneWorktreeIdsByPaneId = paneWorktreeIdsByPaneId
    }

    static let empty = Self()

    @MainActor
    static func from(
        repos: [Repo],
        panes: [Pane],
        worktreeEnrichments: [UUID: WorktreeEnrichment]
    ) -> Self {
        var worktreeIdentitiesByWorktreeId: [UUID: AgentStudioTraceWorktreeIdentity] = [:]
        for repo in repos {
            for worktree in repo.worktrees {
                worktreeIdentitiesByWorktreeId[worktree.id] = AgentStudioTraceWorktreeIdentity(
                    repoHash: repo.stableKey,
                    worktreeHash: worktree.stableKey,
                    branch: Self.nonEmptyBranch(worktreeEnrichments[worktree.id]?.branch)
                )
            }
        }

        let paneWorktreeIdsByPaneId = Dictionary(
            uniqueKeysWithValues: panes.compactMap { pane -> (UUID, UUID)? in
                guard let worktreeId = pane.worktreeId else { return nil }
                return (pane.id, worktreeId)
            }
        )

        return Self(
            worktreeIdentitiesByWorktreeId: worktreeIdentitiesByWorktreeId,
            paneWorktreeIdsByPaneId: paneWorktreeIdsByPaneId
        )
    }

    private static func nonEmptyBranch(_ branch: String?) -> String? {
        let trimmedBranch = branch?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedBranch, !trimmedBranch.isEmpty else { return nil }
        return trimmedBranch
    }
}

actor AgentStudioTraceIdentityStore {
    private var snapshot: AgentStudioTraceIdentitySnapshot

    init(snapshot: AgentStudioTraceIdentitySnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: AgentStudioTraceIdentitySnapshot) {
        self.snapshot = snapshot
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
