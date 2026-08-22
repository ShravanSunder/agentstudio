import AgentStudioInfrastructure
import AppKit
import SwiftUI

struct RepoExplorerPresentationHostView: NSViewRepresentable {
    let projectionAdapter: RepoExplorerProjectionAdapter
    let onVisibleWorktreeIDsChange: @MainActor (Set<UUID>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            projectionAdapter: projectionAdapter,
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
        private var onVisibleWorktreeIDsChange: @MainActor (Set<UUID>) -> Void

        init(
            projectionAdapter: RepoExplorerProjectionAdapter,
            onVisibleWorktreeIDsChange: @escaping @MainActor (Set<UUID>) -> Void
        ) {
            self.projectionAdapter = projectionAdapter
            self.onVisibleWorktreeIDsChange = onVisibleWorktreeIDsChange
        }

        func makeHost() -> RepoExplorerMaterializationHost {
            precondition(materializationHost == nil)
            guard let projectionAdapter else {
                preconditionFailure("Repo Explorer projection adapter released before host creation")
            }
            let host = RepoExplorerMaterializationHost(
                lifetimeID: RepoExplorerMaterializationHostLifetimeID(
                    rawValue: UUIDv7.generate()
                ),
                initialDemandEpoch: projectionAdapter.materializationDemandEpoch,
                initialPresentation: .noRepositories,
                makeContentChild: { [weak self] in
                    RepoExplorerTableMaterializer(
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
            onVisibleWorktreeIDsChange: @escaping @MainActor (Set<UUID>) -> Void
        ) {
            precondition(self.materializationHost === materializationHost)
            precondition(self.projectionAdapter === projectionAdapter)
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
