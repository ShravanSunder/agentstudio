import Foundation

/// Immutable terminal-restoration candidates emitted by accepted composition.
///
/// The input contains only composition-owned values. Repository and worktree
/// identity, filesystem currentness, and live-session inventory are deliberately
/// absent; the terminal activation owner supplies those later where applicable.
package struct TerminalActivationInput: Equatable, Sendable {
    package let entries: [TerminalActivationDescriptor]
}

package struct TerminalActivationDescriptor: Equatable, Sendable {
    /// Exact immutable pane accepted by composition validation.
    /// Activation must not reconstruct or reread this value from live state.
    package let pane: Pane
    package let visibilityPriority: TerminalActivationVisibilityPriority
    let hostPlacement: TerminalHostPlacementIdentity

    package var paneID: PaneId {
        PaneId(existingUUID: pane.id)
    }
}

/// Immutable nonterminal-mount candidates emitted by accepted composition.
///
/// The closed content union prevents the nonterminal owner from receiving a
/// terminal pane. Each case retains the exact accepted pane so mounting never
/// reconstructs composition or consults live atoms or topology.
package struct NonterminalContentMountInput: Equatable, Sendable {
    package let entries: [NonterminalContentMountDescriptor]

    package init(entries: [NonterminalContentMountDescriptor]) {
        self.entries = entries
    }
}

package struct NonterminalContentMountDescriptor: Equatable, Sendable {
    package let content: NonterminalContentMountContent
    package let visibilityPriority: TerminalActivationVisibilityPriority
    let hostPlacement: TerminalHostPlacementIdentity

    package var pane: Pane {
        content.pane
    }

    package var paneID: PaneId {
        PaneId(existingUUID: pane.id)
    }
}

package enum NonterminalContentMountContent: Equatable, Sendable {
    case webview(Pane)
    case bridgePanel(Pane)
    case codeViewer(Pane)
    case unsupported(Pane)

    var pane: Pane {
        switch self {
        case .webview(let pane), .bridgePanel(let pane), .codeViewer(let pane), .unsupported(let pane):
            return pane
        }
    }
}

package enum TerminalActivationVisibilityPriority: Int, Comparable, Sendable {
    case activeVisible = 0
    case visible = 1
    case hidden = 2

    package static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum TerminalHostPlacementIdentity: Equatable, Sendable {
    case tab(tabID: UUID)
    case drawer(tabID: UUID, parentPaneID: PaneId, drawerID: UUID)
}
