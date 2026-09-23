import Foundation

/// How a receiving Bridge relates to the pane graph.
///
/// A terminal-associated receiver is keyed by its terminal pane; the native
/// Zoom companion that renders it is a replaceable implementation detail. A
/// standalone receiver is keyed by the Bridge tab's own pane.
package enum BridgeReceiverKind: String, Hashable, Sendable, CaseIterable {
    case terminalAssociated
    case standaloneBridge
}

/// The stable identity of one receiving Bridge: an existing pane identity plus
/// its receiver kind. It never mints another persistent Bridge-session ID.
package struct BridgeReceiver: Hashable, Sendable {
    package let paneId: UUID
    package let kind: BridgeReceiverKind

    package init(paneId: UUID, kind: BridgeReceiverKind) {
        self.paneId = paneId
        self.kind = kind
    }

    package static func terminal(_ paneId: UUID) -> Self {
        Self(paneId: paneId, kind: .terminalAssociated)
    }

    package static func standalone(_ paneId: UUID) -> Self {
        Self(paneId: paneId, kind: .standaloneBridge)
    }
}
