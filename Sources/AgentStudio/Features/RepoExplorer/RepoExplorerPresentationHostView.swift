import AgentStudioInfrastructure
import AppKit
import SwiftUI

struct RepoExplorerPresentationHostView: NSViewRepresentable {
    let projectionAdapter: RepoExplorerProjectionAdapter
    let octiconLoader: OcticonLoader
    let commandPresentationDelta: RepoExplorerCommandPresentationDelta?
    let interactions: RepoExplorerTableInteractions
    let onVisibleWorktreeSnapshotChange: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
    let observeCurrentVisibleTarget: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void

    init(
        projectionAdapter: RepoExplorerProjectionAdapter,
        octiconLoader: OcticonLoader,
        commandPresentationDelta: RepoExplorerCommandPresentationDelta? = nil,
        interactions: RepoExplorerTableInteractions = .inert,
        onVisibleWorktreeSnapshotChange: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
        observeCurrentVisibleTarget: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void = { _ in }
    ) {
        self.projectionAdapter = projectionAdapter
        self.octiconLoader = octiconLoader
        self.commandPresentationDelta = commandPresentationDelta
        self.interactions = interactions
        self.onVisibleWorktreeSnapshotChange = onVisibleWorktreeSnapshotChange
        self.observeCurrentVisibleTarget = observeCurrentVisibleTarget
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            projectionAdapter: projectionAdapter,
            octiconLoader: octiconLoader,
            interactions: interactions,
            onVisibleWorktreeSnapshotChange: onVisibleWorktreeSnapshotChange,
            observeCurrentVisibleTarget: observeCurrentVisibleTarget
        )
    }

    func makeNSView(context: Context) -> RepoExplorerMaterializationHost {
        context.coordinator.makeHost()
    }

    func updateNSView(
        _ materializationHost: RepoExplorerMaterializationHost,
        context: Context
    ) {
        context.coordinator.update(
            materializationHost: materializationHost,
            commandPresentationDelta: commandPresentationDelta,
            onVisibleWorktreeSnapshotChange: onVisibleWorktreeSnapshotChange,
            observeCurrentVisibleTarget: observeCurrentVisibleTarget
        )
    }

    static func dismantleNSView(
        _ materializationHost: RepoExplorerMaterializationHost,
        coordinator: Coordinator
    ) {
        coordinator.dismantle(materializationHost: materializationHost)
    }

    @MainActor
    final class Coordinator {
        private weak var projectionAdapter: RepoExplorerProjectionAdapter?
        private weak var materializationHost: RepoExplorerMaterializationHost?
        private weak var tableMaterializer: RepoExplorerTableMaterializer?
        private let octiconLoader: OcticonLoader
        private let interactions: RepoExplorerTableInteractions
        private var onVisibleWorktreeSnapshotChange: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
        private var observeCurrentVisibleTarget: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void

        init(
            projectionAdapter: RepoExplorerProjectionAdapter,
            octiconLoader: OcticonLoader,
            interactions: RepoExplorerTableInteractions,
            onVisibleWorktreeSnapshotChange: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
            observeCurrentVisibleTarget: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
        ) {
            self.projectionAdapter = projectionAdapter
            self.octiconLoader = octiconLoader
            self.interactions = interactions
            self.onVisibleWorktreeSnapshotChange = onVisibleWorktreeSnapshotChange
            self.observeCurrentVisibleTarget = observeCurrentVisibleTarget
        }

        func makeHost() -> RepoExplorerMaterializationHost {
            precondition(materializationHost == nil)
            guard let projectionAdapter else {
                preconditionFailure("Repo Explorer projection adapter released before host creation")
            }
            let stableOcticonLoader = octiconLoader
            let hostLifetimeID = RepoExplorerMaterializationHostLifetimeID(
                rawValue: UUIDv7.generate()
            )
            let host = RepoExplorerMaterializationHost(
                lifetimeID: hostLifetimeID,
                initialDemandEpoch: projectionAdapter.materializationDemandEpoch,
                initialPresentation: .noRepositories,
                makeContentChild: { [weak self] in
                    let materializer = RepoExplorerTableMaterializer(
                        materializationHostLifetimeID: hostLifetimeID,
                        octiconLoader: stableOcticonLoader,
                        interactions: self?.interactions ?? .inert,
                        onVisibleWorktreeSnapshotChange: { snapshot in
                            self?.onVisibleWorktreeSnapshotChange(snapshot)
                        },
                        observeCurrentVisibleTarget: { snapshot in
                            self?.observeCurrentVisibleTarget(snapshot)
                        }
                    )
                    self?.tableMaterializer = materializer
                    return materializer
                },
                onFeedback: { [weak projectionAdapter] feedback in
                    projectionAdapter?.receiveMaterializationFeedback(feedback)
                }
            )
            guard projectionAdapter.registerMaterializationHost(host) else {
                host.detach()
                preconditionFailure("Repo Explorer materialization host registration failed")
            }
            materializationHost = host
            return host
        }

        func update(
            materializationHost: RepoExplorerMaterializationHost,
            commandPresentationDelta: RepoExplorerCommandPresentationDelta?,
            onVisibleWorktreeSnapshotChange: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
            observeCurrentVisibleTarget: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
        ) {
            precondition(self.materializationHost === materializationHost)
            self.onVisibleWorktreeSnapshotChange = onVisibleWorktreeSnapshotChange
            self.observeCurrentVisibleTarget = observeCurrentVisibleTarget
            if let commandPresentationDelta {
                _ = tableMaterializer?.applyCommandPresentationDelta(commandPresentationDelta)
            }
        }

        func dismantle(materializationHost: RepoExplorerMaterializationHost) {
            guard self.materializationHost === materializationHost else { return }
            projectionAdapter?.unregisterMaterializationHost(
                lifetimeID: materializationHost.lifetimeID
            )
            materializationHost.detach()
            self.materializationHost = nil
            tableMaterializer = nil
            onVisibleWorktreeSnapshotChange = { _ in }
            observeCurrentVisibleTarget = { _ in }
        }
    }
}
