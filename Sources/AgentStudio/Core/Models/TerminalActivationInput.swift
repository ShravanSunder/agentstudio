import Foundation

/// Immutable terminal-restoration candidates emitted by accepted composition.
///
/// The input contains only composition-owned values. Repository and worktree
/// identity, filesystem currentness, and live-session inventory are deliberately
/// absent; the terminal activation owner supplies those later where applicable.
struct TerminalActivationInput: Equatable, Sendable {
    let entries: [TerminalActivationDescriptor]
}

struct TerminalActivationDescriptor: Equatable, Sendable {
    /// Exact immutable pane accepted by composition validation.
    /// Activation must not reconstruct or reread this value from live state.
    let pane: Pane
    let visibilityPriority: TerminalActivationVisibilityPriority
    let hostPlacement: TerminalHostPlacementIdentity

    var paneID: PaneId {
        PaneId(existingUUID: pane.id)
    }
}

/// Immutable nonterminal-mount candidates emitted by accepted composition.
///
/// The closed content union prevents the nonterminal owner from receiving a
/// terminal pane. Each case retains the exact accepted pane so mounting never
/// reconstructs composition or consults live atoms or topology.
struct NonterminalContentMountInput: Equatable, Sendable {
    let entries: [NonterminalContentMountDescriptor]
}

struct NonterminalContentMountDescriptor: Equatable, Sendable {
    let content: NonterminalContentMountContent
    let visibilityPriority: TerminalActivationVisibilityPriority
    let hostPlacement: TerminalHostPlacementIdentity

    var pane: Pane {
        content.pane
    }

    var paneID: PaneId {
        PaneId(existingUUID: pane.id)
    }
}

enum NonterminalContentMountContent: Equatable, Sendable {
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

enum TerminalActivationVisibilityPriority: Int, Comparable, Sendable {
    case activeVisible = 0
    case visible = 1
    case hidden = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum TerminalHostPlacementIdentity: Equatable, Sendable {
    case tab(tabID: UUID)
    case drawer(tabID: UUID, parentPaneID: PaneId, drawerID: UUID)
}
