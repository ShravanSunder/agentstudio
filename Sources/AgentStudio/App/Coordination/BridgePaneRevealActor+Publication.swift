import AgentStudioCore
import Foundation

enum BridgeRevealPublicationOutcome {
    case applied
    case superseded
    case inconsistent
}

extension BridgePaneRevealActor {
    /// Overlay one acknowledged document into the newest UI record. A UI
    /// filter, selection or surface chosen after admission remains authoritative.
    func publishRetained(
        _ committed: BridgeNavigationRecord, item: BridgeRetainedOpenViewItem,
        request: Request
    ) async -> BridgeRevealPublicationOutcome {
        guard
            let committedDocument = committed.openedDocuments.first(where: {
                $0.retainedOpenViewItem == item
            })
        else { return .inconsistent }
        while true {
            if let closeTicket = closeTicket(for: request), closeTicket > request.generation {
                return .superseded
            }
            let latest = await handler.latestLinkRecord(for: request.receiver)
            let presentationTopology = await handler.captureLinkTopology(sourcePaneID: request.sourcePaneID)
            var updated = latest.record
            if let index = updated.openedDocuments.firstIndex(where: {
                $0.location == committedDocument.location
            }) {
                let existing = updated.openedDocuments[index]
                updated.openedDocuments[index] = BridgeOpenedDocument(
                    location: existing.location, provenance: existing.provenance,
                    retainedOpenViewItem: item
                )
            } else {
                updated.openedDocuments.append(committedDocument)
            }
            let application = BridgeCommittedLinkApplication(
                record: updated, memberRoots: presentationTopology.effectiveMemberRoots(in: updated),
                reviewReplacement: nil
            )
            await publicationInterlock.beforeApply(
                receiver: request.receiver, location: committedDocument.location
            )
            if await handler.applyCommittedLinkApplication(
                application, for: request.receiver, ifRevision: latest.revision,
                reviewSurface: nil
            ) {
                return .applied
            }
            // A close fact is yielded synchronously with its atom revision.
            // Consume it before recomputing a rejected apply.
            await awaitIngressBarrier()
        }
    }
}
