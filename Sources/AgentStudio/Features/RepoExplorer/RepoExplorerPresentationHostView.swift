import AgentStudioInfrastructure
import AppKit
import SwiftUI

struct RepoExplorerPresentationHostView: NSViewRepresentable {
    let projectionAdapter: RepoExplorerProjectionAdapter
    let octiconLoader: OcticonLoader
    let onVisibleWorktreeIDsChange: @MainActor (Set<UUID>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            projectionAdapter: projectionAdapter,
            octiconLoader: octiconLoader,
            onVisibleWorktreeIDsChange: onVisibleWorktreeIDsChange
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
            projectionAdapter: projectionAdapter,
            octiconLoader: octiconLoader,
            onVisibleWorktreeIDsChange: onVisibleWorktreeIDsChange
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
        private let octiconLoader: OcticonLoader
        private var onVisibleWorktreeIDsChange: @MainActor (Set<UUID>) -> Void

        init(
            projectionAdapter: RepoExplorerProjectionAdapter,
            octiconLoader: OcticonLoader,
            onVisibleWorktreeIDsChange: @escaping @MainActor (Set<UUID>) -> Void
        ) {
            self.projectionAdapter = projectionAdapter
            self.octiconLoader = octiconLoader
            self.onVisibleWorktreeIDsChange = onVisibleWorktreeIDsChange
        }

        func makeHost() -> RepoExplorerMaterializationHost {
            precondition(materializationHost == nil)
            guard let projectionAdapter else {
                preconditionFailure("Repo Explorer projection adapter released before host creation")
            }
            let stableOcticonLoader = octiconLoader
            let host = RepoExplorerMaterializationHost(
                lifetimeID: RepoExplorerMaterializationHostLifetimeID(
                    rawValue: UUIDv7.generate()
                ),
                initialDemandEpoch: projectionAdapter.materializationDemandEpoch,
                initialPresentation: .noRepositories,
                makeContentChild: { [weak self] in
                    RepoExplorerTableMaterializer(
                        octiconLoader: stableOcticonLoader,
                        onVisibleWorktreeIDsChange: { worktreeIDs in
                            self?.onVisibleWorktreeIDsChange(worktreeIDs)
                        }
                    )
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
            projectionAdapter: RepoExplorerProjectionAdapter,
            octiconLoader: OcticonLoader,
            onVisibleWorktreeIDsChange: @escaping @MainActor (Set<UUID>) -> Void
        ) {
            precondition(self.materializationHost === materializationHost)
            precondition(self.projectionAdapter === projectionAdapter)
            precondition(self.octiconLoader === octiconLoader)
            self.onVisibleWorktreeIDsChange = onVisibleWorktreeIDsChange
        }

        func dismantle(materializationHost: RepoExplorerMaterializationHost) {
            guard self.materializationHost === materializationHost else { return }
            projectionAdapter?.unregisterMaterializationHost(
                lifetimeID: materializationHost.lifetimeID
            )
            materializationHost.detach()
            self.materializationHost = nil
            onVisibleWorktreeIDsChange = { _ in }
        }
    }
}
