import Foundation

// MARK: - Create Policy

/// When panes should be auto-created from templates.
enum CreatePolicy: String, Codable, Hashable {
    /// Create panes when the worktree is first opened.
    case onCreate
    /// Create panes when the worktree view is activated.
    case onActivate
    /// Only create panes manually.
    case manual
}

// MARK: - Terminal Template

/// Template for a single terminal pane to be created.
struct TerminalTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    /// Working directory relative to the worktree root.
    var relativeWorkingDir: String?

    init(
        id: UUID = UUID(),
        title: String = "Terminal",
        agent: AgentType? = nil,
        provider: SessionProvider = .zmx,
        relativeWorkingDir: String? = nil
    ) {
        self.id = id
        self.title = title
        self.agent = agent
        self.provider = provider
        self.relativeWorkingDir = relativeWorkingDir
    }

    /// Create a Pane from this template for a given worktree/repo.
    func instantiate(worktreeId: UUID, repoId: UUID) -> Pane {
        Pane(
            content: .terminal(TerminalState(
                provider: provider,
                lifetime: .persistent
            )),
            metadata: PaneMetadata(
                source: .worktree(worktreeId: worktreeId, repoId: repoId),
                title: title,
                agentType: agent
            )
        )
    }
}

// MARK: - Worktree Template

/// Template for the initial pane layout when opening a worktree.
/// Defines what terminals to create and how to arrange them.
struct WorktreeTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var terminals: [TerminalTemplate]
    var createPolicy: CreatePolicy
    /// Layout direction for multi-terminal templates.
    var splitDirection: Layout.SplitDirection

    init(
        id: UUID = UUID(),
        name: String = "Default",
        terminals: [TerminalTemplate] = [TerminalTemplate()],
        createPolicy: CreatePolicy = .manual,
        splitDirection: Layout.SplitDirection = .horizontal
    ) {
        self.id = id
        self.name = name
        self.terminals = terminals
        self.createPolicy = createPolicy
        self.splitDirection = splitDirection
    }

    /// Create panes and a tab from this template for a given worktree/repo.
    func instantiate(worktreeId: UUID, repoId: UUID) -> (panes: [Pane], tab: Tab) {
        let panes = terminals.map { $0.instantiate(worktreeId: worktreeId, repoId: repoId) }

        guard let first = panes.first else {
            fatalError("WorktreeTemplate must have at least one terminal")
        }

        // Build layout: start with first pane, insert each subsequent one
        var layout = Layout(paneId: first.id)
        for pane in panes.dropFirst() {
            let lastId = layout.paneIds.last ?? first.id
            layout = layout.inserting(
                paneId: pane.id,
                at: lastId,
                direction: splitDirection,
                position: .after
            )
        }

        let paneIds = panes.map(\.id)
        let arrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: layout,
            visiblePaneIds: Set(paneIds)
        )
        let tab = Tab(
            name: first.title,
            panes: paneIds,
            arrangements: [arrangement],
            activeArrangementId: arrangement.id,
            activePaneId: first.id
        )
        return (panes: panes, tab: tab)
    }
}
