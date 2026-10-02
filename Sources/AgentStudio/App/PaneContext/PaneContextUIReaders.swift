import AgentStudioCore
import AgentStudioSessions
import AgentStudioSharedComponents

/// App composes Feature-owned keyed facts; consumers never reach across Features.
@MainActor
struct PaneContextUIReaders {
    let sessionStatusForPane: @MainActor (PaneId) -> AgentSessionStatus?
    let contextDisplayForPane: @MainActor (PaneId) -> PaneContextDisplay?
    let titleForPane: @MainActor (PaneId) -> String?

    init(
        sessionStatus: SessionStatusAtom, presentation: PaneContextPresentationAtom,
        pane: @escaping @MainActor (PaneId) -> Pane?
    ) {
        sessionStatusForPane = { sessionStatus.value(for: $0) }
        contextDisplayForPane = { presentation.value(for: $0) }
        let titles = PaneDisplayTitleDerived(presentation: presentation)
        titleForPane = { paneId in
            guard let pane = pane(paneId) else { return nil }
            return titles.title(for: paneId, fallbackTitle: pane.title)
        }
    }

    func makePopoverController(
        reader: any PaneContextDetailReading, person: any PaneContextPersonActing,
        membership: any PaneLinkMembershipPort, contributor: BridgeLinkContributor,
        location: PaneContextPopoverLocation
    ) -> PaneContextPopoverController {
        PaneContextPopoverController(
            reader: reader, person: person, membership: membership, contributor: contributor,
            location: location, titleForPane: titleForPane,
            revisionForPane: { contextDisplayForPane($0)?.revision })
    }
}
