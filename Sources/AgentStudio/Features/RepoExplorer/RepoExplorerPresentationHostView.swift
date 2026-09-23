import AgentStudioInfrastructure
import AppKit
import SwiftUI

struct RepoExplorerPresentationHostView: NSViewRepresentable {
    let projectionAdapter: RepoExplorerProjectionAdapter
    let octiconLoader: OcticonLoader
    let commandPresentationDelta: RepoExplorerCommandPresentationDelta?
    let visibleSnapshotConsumerToken: UUID?
    let interactions: RepoExplorerTableInteractions
    let keyboardInteraction: RepoExplorerKeyboardInteraction?
    let keyboardCallbacks: RepoExplorerKeyboardCallbacks?
    let showsKeyboardHints: Bool
    let onVisibleWorktreeSnapshotChange: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
    let observeCurrentVisibleTarget: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void

    init(
        projectionAdapter: RepoExplorerProjectionAdapter,
        octiconLoader: OcticonLoader,
        commandPresentationDelta: RepoExplorerCommandPresentationDelta? = nil,
        visibleSnapshotConsumerToken: UUID? = nil,
        interactions: RepoExplorerTableInteractions = .inert,
        keyboardInteraction: RepoExplorerKeyboardInteraction? = nil,
        keyboardCallbacks: RepoExplorerKeyboardCallbacks? = nil,
        showsKeyboardHints: Bool = false,
        onVisibleWorktreeSnapshotChange: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
        observeCurrentVisibleTarget: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void = { _ in }
    ) {
        self.projectionAdapter = projectionAdapter
        self.octiconLoader = octiconLoader
        self.commandPresentationDelta = commandPresentationDelta
        self.visibleSnapshotConsumerToken = visibleSnapshotConsumerToken
        self.interactions = interactions
        self.keyboardInteraction = keyboardInteraction
        self.keyboardCallbacks = keyboardCallbacks
        self.showsKeyboardHints = showsKeyboardHints
        self.onVisibleWorktreeSnapshotChange = onVisibleWorktreeSnapshotChange
        self.observeCurrentVisibleTarget = observeCurrentVisibleTarget
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            projectionAdapter: projectionAdapter,
            octiconLoader: octiconLoader,
            interactions: interactions,
            keyboardInteraction: keyboardInteraction,
            keyboardCallbacks: keyboardCallbacks,
            onVisibleWorktreeSnapshotChange: onVisibleWorktreeSnapshotChange,
            observeCurrentVisibleTarget: observeCurrentVisibleTarget,
            visibleSnapshotConsumerToken: visibleSnapshotConsumerToken
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
            presentation: self
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
        private let keyboardInteraction: RepoExplorerKeyboardInteraction?
        private var onVisibleWorktreeSnapshotChange: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
        private var observeCurrentVisibleTarget: @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void
        private var currentVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot?
        private var visibleSnapshotConsumerToken: UUID?
        private var lastPublishedVisibleSnapshot: RepoExplorerVisibleWorktreeSnapshot?
        private var lastPublishedConsumerToken: UUID?

        init(
            projectionAdapter: RepoExplorerProjectionAdapter,
            octiconLoader: OcticonLoader,
            interactions: RepoExplorerTableInteractions,
            keyboardInteraction: RepoExplorerKeyboardInteraction?,
            keyboardCallbacks: RepoExplorerKeyboardCallbacks?,
            onVisibleWorktreeSnapshotChange: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
            observeCurrentVisibleTarget: @escaping @MainActor (RepoExplorerVisibleWorktreeSnapshot) -> Void,
            visibleSnapshotConsumerToken: UUID?
        ) {
            self.projectionAdapter = projectionAdapter
            self.octiconLoader = octiconLoader
            self.interactions = interactions
            self.keyboardInteraction = keyboardInteraction
            if let keyboardCallbacks {
                keyboardInteraction?.configure(keyboardCallbacks)
            }
            self.onVisibleWorktreeSnapshotChange = onVisibleWorktreeSnapshotChange
            self.observeCurrentVisibleTarget = observeCurrentVisibleTarget
            self.visibleSnapshotConsumerToken = visibleSnapshotConsumerToken
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
                            self?.publishVisibleWorktreeSnapshot(snapshot)
                        },
                        observeCurrentVisibleTarget: { snapshot in
                            self?.observeCurrentVisibleSnapshot(snapshot)
                        }
                    )
                    self?.tableMaterializer = materializer
                    materializer.setShowsKeyboardHints(self?.keyboardInteraction?.isListKeyboardActive == true)
                    return materializer
                },
                onFeedback: { [weak projectionAdapter] feedback in
                    projectionAdapter?.receiveMaterializationFeedback(feedback)
                }
            )
            host.identifier = RepoExplorerView.focusTargetIdentifier
            if let keyboardInteraction {
                host.installKeyboardInteraction(keyboardInteraction)
            }
            guard projectionAdapter.registerMaterializationHost(host) else {
                host.detach()
                preconditionFailure("Repo Explorer materialization host registration failed")
            }
            materializationHost = host
            let initialVisibleSnapshot = RepoExplorerVisibleWorktreeSnapshot(
                target: RepoExplorerCommandPresentationTarget(
                    materializationHostLifetimeID: hostLifetimeID,
                    materializationGeneration: 0,
                    visibleRevision: 0
                ),
                worktreeIDs: []
            )
            publishVisibleWorktreeSnapshot(initialVisibleSnapshot)
            return host
        }

        func update(
            materializationHost: RepoExplorerMaterializationHost,
            presentation: RepoExplorerPresentationHostView
        ) {
            precondition(self.materializationHost === materializationHost)
            if let keyboardCallbacks = presentation.keyboardCallbacks {
                keyboardInteraction?.configure(keyboardCallbacks)
            }
            tableMaterializer?.setShowsKeyboardHints(presentation.showsKeyboardHints)
            onVisibleWorktreeSnapshotChange = presentation.onVisibleWorktreeSnapshotChange
            observeCurrentVisibleTarget = presentation.observeCurrentVisibleTarget
            visibleSnapshotConsumerToken = presentation.visibleSnapshotConsumerToken
            if let currentVisibleSnapshot,
                currentVisibleSnapshot != lastPublishedVisibleSnapshot
                    || visibleSnapshotConsumerToken != lastPublishedConsumerToken
            {
                lastPublishedVisibleSnapshot = currentVisibleSnapshot
                lastPublishedConsumerToken = visibleSnapshotConsumerToken
                onVisibleWorktreeSnapshotChange(currentVisibleSnapshot)
            }
            if let commandPresentationDelta = presentation.commandPresentationDelta {
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
            currentVisibleSnapshot = nil
            onVisibleWorktreeSnapshotChange = { _ in }
            observeCurrentVisibleTarget = { _ in }
            lastPublishedVisibleSnapshot = nil
            lastPublishedConsumerToken = nil
        }

        private func publishVisibleWorktreeSnapshot(
            _ snapshot: RepoExplorerVisibleWorktreeSnapshot
        ) {
            currentVisibleSnapshot = snapshot
            lastPublishedVisibleSnapshot = snapshot
            lastPublishedConsumerToken = visibleSnapshotConsumerToken
            onVisibleWorktreeSnapshotChange(snapshot)
        }

        private func observeCurrentVisibleSnapshot(
            _ snapshot: RepoExplorerVisibleWorktreeSnapshot
        ) {
            currentVisibleSnapshot = snapshot
            observeCurrentVisibleTarget(snapshot)
        }
    }
}
