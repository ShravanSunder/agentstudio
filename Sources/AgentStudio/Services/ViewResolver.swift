import Foundation
import os.log

private let resolverLogger = Logger(subsystem: "com.agentstudio", category: "ViewResolver")

/// Resolves dynamic and worktree views at runtime.
/// Generates ViewDefinitions from sessions based on rules.
/// Ephemeral — the resolved view reflects current state, not persisted.
@MainActor
struct ViewResolver {

    /// Resolve a worktree view: all sessions for a given worktree, each in its own tab.
    static func resolveWorktreeView(
        worktreeId: UUID,
        sessions: [TerminalSession],
        worktree: Worktree?
    ) -> ViewDefinition {
        let matching = sessions.filter { $0.worktreeId == worktreeId }
        let tabs = matching.map { Tab(sessionId: $0.id) }
        let name = worktree?.name ?? "Worktree"
        return ViewDefinition(
            name: name,
            kind: .worktree(worktreeId: worktreeId),
            tabs: tabs,
            activeTabId: tabs.first?.id
        )
    }

    /// Resolve a dynamic view from a rule.
    static func resolveDynamic(
        rule: DynamicViewRule,
        sessions: [TerminalSession],
        repos: [Repo]
    ) -> ViewDefinition {
        switch rule {
        case .byRepo(let repoId):
            return resolveByRepo(repoId: repoId, sessions: sessions, repos: repos)
        case .byAgent(let agentType):
            return resolveByAgent(agentType: agentType, sessions: sessions)
        case .custom(let name):
            return resolveCustom(name: name, sessions: sessions)
        }
    }

    // MARK: - Private Resolution

    /// All sessions whose source worktree belongs to the given repo.
    private static func resolveByRepo(
        repoId: UUID,
        sessions: [TerminalSession],
        repos: [Repo]
    ) -> ViewDefinition {
        let repo = repos.first { $0.id == repoId }
        let worktreeIds = Set(repo?.worktrees.map(\.id) ?? [])
        let matching = sessions.filter { session in
            guard let wId = session.worktreeId else { return false }
            return worktreeIds.contains(wId)
        }
        let tabs = matching.map { Tab(sessionId: $0.id) }
        let name = repo?.name ?? "Repo"
        return ViewDefinition(
            name: name,
            kind: .dynamic(rule: .byRepo(repoId: repoId)),
            tabs: tabs,
            activeTabId: tabs.first?.id
        )
    }

    /// All sessions running a specific agent type.
    private static func resolveByAgent(
        agentType: AgentType,
        sessions: [TerminalSession]
    ) -> ViewDefinition {
        let matching = sessions.filter { $0.agent == agentType }
        let tabs = matching.map { Tab(sessionId: $0.id) }
        return ViewDefinition(
            name: "\(agentType)",
            kind: .dynamic(rule: .byAgent(agentType)),
            tabs: tabs,
            activeTabId: tabs.first?.id
        )
    }

    /// Custom rule — placeholder, returns empty view.
    private static func resolveCustom(
        name: String,
        sessions: [TerminalSession]
    ) -> ViewDefinition {
        resolverLogger.debug("Custom view rule '\(name)' — no filter implemented, returning all sessions")
        let tabs = sessions.map { Tab(sessionId: $0.id) }
        return ViewDefinition(
            name: name,
            kind: .dynamic(rule: .custom(name: name)),
            tabs: tabs,
            activeTabId: tabs.first?.id
        )
    }
}
