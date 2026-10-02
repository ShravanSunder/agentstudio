import Foundation

package struct PaneContextMembershipEntry: Sendable, Equatable {
    package let paneId: PaneId
    package let placement: PaneStructuralFacts.Placement
    package let ownedDrawerChildIds: [PaneId]

    package init(paneId: PaneId, placement: PaneStructuralFacts.Placement, ownedDrawerChildIds: [PaneId]) {
        self.paneId = paneId
        self.placement = placement
        self.ownedDrawerChildIds = ownedDrawerChildIds
    }
}

package struct PaneContextMembershipInstallation: Sendable, Equatable {
    package let workspaceId: UUID
    package let membershipRevision: UInt64
    package let entries: [PaneContextMembershipEntry]

    package init(workspaceId: UUID, membershipRevision: UInt64, entries: [PaneContextMembershipEntry]) {
        self.workspaceId = workspaceId
        self.membershipRevision = membershipRevision
        self.entries = entries
    }
}

package struct PaneContextMembershipView: Sendable, Equatable {
    package let workspaceId: UUID
    package let membershipRevision: UInt64
    package let sources: [PaneId]
}

package struct PaneContextMembershipOwner: Sendable, Equatable {
    package let paneId: PaneId
    package let membershipRevision: UInt64
}

/// RED shell; graph publication and atomic boot installation follow at GREEN.
package final class PaneContextMembershipDirectory: PaneContextMembershipReading, Sendable {
    package let wakes: AsyncStream<Void>

    package init() {
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        channel.continuation.finish()
        wakes = channel.stream
    }

    package func install(_ installation: PaneContextMembershipInstallation) {}
    package func commit(changed: [PaneContextMembershipEntry], removed: [PaneId]) {}
    package func contains(paneID: UUID, inWorkspace workspaceID: UUID) -> Bool { false }
    package func view(for paneId: PaneId) -> PaneContextMembershipView? { nil }
    package func ownerPaneId(for paneId: PaneId) -> PaneId? { nil }
    package func sources(for paneId: PaneId) -> [PaneId]? { nil }
    package func currentOwners() -> [PaneContextMembershipOwner] { [] }
    package func takeAffectedOwners() -> PendingAffectedOwners { .owners([]) }
}
