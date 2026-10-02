import AgentStudioInfrastructure

package enum PendingAffectedOwners: Sendable, Equatable {
    case owners(Set<PaneId>)
    case all

    package mutating func insert(contentsOf paneIds: Set<PaneId>) {}
}
