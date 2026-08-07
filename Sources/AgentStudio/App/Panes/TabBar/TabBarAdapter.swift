import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioInfrastructure
import Foundation
import Observation

typealias TabBarMaterializedProjection = EagerDerivedAtom<
    TabBarProjectionRequest,
    TabBarProjectionGeneration,
    TabBarProjection
>

/// Derives tab bar display state from the workspace atoms.
/// Owns only the materialized projection and transient MainActor UI state.
@MainActor
@Observable
final class TabBarAdapter {
    // MARK: - Materialized Projection

    var tabs: [TabBarItem] {
        materializedProjection.value?.items ?? []
    }

    var activeTabId: UUID? {
        materializedProjection.value?.activeTabID
    }

    // MARK: - Overflow Detection

    var availableWidth: CGFloat = 0 {
        didSet {
            guard oldValue != availableWidth else { return }
            updateOverflow()
        }
    }
    private(set) var isOverflowing = false
    var contentWidth: CGFloat = 0 {
        didSet {
            guard oldValue != contentWidth else { return }
            updateOverflow()
        }
    }
    var viewportWidth: CGFloat = 0 {
        didSet {
            guard oldValue != viewportWidth else { return }
            updateOverflow()
        }
    }

    static let minTabWidth: CGFloat = 220
    static let tabSpacing: CGFloat = 4
    static let tabBarPadding: CGFloat = 16
    static let hysteresisBuffer: CGFloat = 50

    // MARK: - Management Layer

    private(set) var isManagementLayerActive = false

    // MARK: - Transient UI State

    var draggingTabId: UUID?
    var dropTargetIndex: Int?
    var dwellTabId: UUID?
    var dwellProgress: CGFloat = 0
    var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Internals

    let materializedProjection: TabBarMaterializedProjection

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let inboxAtom: InboxNotificationAtom
    private var projectionGeneration: UInt64 = 0
    private var isObservingManagementLayer = false
    private var hasStopped = false

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        inboxAtom: InboxNotificationAtom,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        project: @escaping @Sendable (TabBarProjectionRequest) throws(CancellationError) -> TabBarProjection =
            { try TabBarProjector.project($0) },
        onProjectionCompletion:
            @escaping @MainActor @Sendable (
                TabBarMaterializedProjection.ProjectionCompletion
            ) -> Void = { _ in }
    ) {
        self.store = store
        self.repoCache = repoCache
        self.inboxAtom = inboxAtom
        self.materializedProjection = TabBarMaterializedProjection(
            requestIdentity: \.generation,
            isValueEqual: ==,
            project: project,
            onProjectionCompletion: onProjectionCompletion
        )
        _ = performanceTraceRecorder
        observe()
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        materializedProjection.stop()
    }

    // MARK: - Observation

    private func observe() {
        isManagementLayerActive = atom(\.managementLayer).isActive
        observeMaterializedProjection()
        observeManagementLayer()
        captureAndAdmitNewestRequest()
    }

    private func captureAndAdmitNewestRequest() {
        guard !hasStopped else { return }

        projectionGeneration &+= 1
        let generation = TabBarProjectionGeneration(value: projectionGeneration)
        let materializedProjection = self.materializedProjection
        let request = withObservationTracking {
            TabBarProjectionRequest(
                generation: generation,
                coreRequest: CoreTabBarProjectionRequest.capture(
                    store: store,
                    repoCache: repoCache
                ),
                inboxAttentionFacts: inboxAtom.captureAttentionFacts()
            )
        } onChange: { [weak self, materializedProjection] in
            materializedProjection.sourceDidInvalidate()
            Task { @MainActor [weak self] in
                self?.captureAndAdmitNewestRequest()
            }
        }
        materializedProjection.admit(request)
    }

    private func observeMaterializedProjection() {
        guard !hasStopped else { return }
        let materializedProjection = self.materializedProjection
        withObservationTracking {
            _ = materializedProjection.value
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasStopped else { return }
                self.updateOverflow()
                self.observeMaterializedProjection()
            }
        }
    }

    private func observeManagementLayer() {
        guard !hasStopped, !isObservingManagementLayer else { return }
        isObservingManagementLayer = true
        withObservationTracking {
            _ = atom(\.managementLayer).isActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.hasStopped else { return }
                self.isObservingManagementLayer = false
                self.isManagementLayerActive = atom(\.managementLayer).isActive
                self.observeManagementLayer()
            }
        }
    }

    private func updateOverflow() {
        guard !tabs.isEmpty else {
            isOverflowing = false
            return
        }

        let effectiveViewport = viewportWidth > 0 ? viewportWidth : availableWidth
        guard effectiveViewport > 0 else { return }

        if contentWidth > 0 {
            if isOverflowing {
                isOverflowing = contentWidth > (effectiveViewport - Self.hysteresisBuffer)
            } else {
                isOverflowing = contentWidth > effectiveViewport
            }
            return
        }

        let tabCount = CGFloat(tabs.count)
        let totalMinWidth =
            tabCount * Self.minTabWidth
            + (tabCount - 1) * Self.tabSpacing
            + Self.tabBarPadding
        isOverflowing = totalMinWidth > effectiveViewport
    }
}
