import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// Refresh every retained receiver's Files slot after topology changes.
    /// MainActor copies raw facts; validation and ordering run off-main.
    func refreshBridgeFilesBindingsAfterTopologyChange() -> Task<Void, Never> {
        let records = store.bridgeNavigationAtom.recordsSnapshot()
        let topology = store.repositoryTopologyAtom.captureReadSnapshot()
        let ticket = store.bridgeWriteSequencer.nextTicket().value
        return Task { [weak self] in
            let prepared = await BridgeFilesBindingPreparation.prepareAllOffMain(
                records: records, repositoryTopology: topology, ticket: ticket)
            guard let self else { return }
            for (receiver, value) in prepared {
                guard
                    store.bridgeNavigationAtom.record(for: receiver) != nil,
                    store.bridgeNavigationAtom.assignPreparedFilesBinding(
                        value.binding, for: receiver, ticket: value.ticket)
                else { continue }
                mountedBridgeController(for: receiver)?
                    .enqueueFilesSourceUpdate(value.binding)
            }
        }
    }
}
