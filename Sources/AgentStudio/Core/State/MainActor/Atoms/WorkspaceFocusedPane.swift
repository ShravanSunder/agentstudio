import Foundation

/// Immutable identity and content for the pane that currently owns workspace focus.
package struct WorkspaceFocusedPane: Equatable, Sendable {
    package enum ContentType: Equatable, Sendable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unsupported
    }

    package let owner: WorkspaceFocusOwner
    package let activeMainPaneId: UUID
    package let paneId: UUID
    package let repoId: UUID?
    package let worktreeId: UUID?
    package let contentType: ContentType

    package init(
        owner: WorkspaceFocusOwner,
        activeMainPaneId: UUID,
        paneId: UUID,
        repoId: UUID?,
        worktreeId: UUID?,
        contentType: ContentType
    ) {
        self.owner = owner
        self.activeMainPaneId = activeMainPaneId
        self.paneId = paneId
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.contentType = contentType
    }
}
