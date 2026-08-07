import AgentStudioCore
import AgentStudioInboxNotification
import AgentStudioInfrastructure
import Foundation
import Observation
import Synchronization

typealias TabBarMaterializedProjection = EagerDerivedAtom<
    TabBarProjectionRequest,
    TabBarProjectionGeneration,
    TabBarProjection
>

private struct TabBarProjectionCapture {
    let request: TabBarProjectionRequest
}

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
    private let projectionTelemetry: TabBarProjectionTelemetry
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
        let projectionTelemetry = TabBarProjectionTelemetry(recorder: performanceTraceRecorder)
        let measuredProject: @Sendable (TabBarProjectionRequest) throws(CancellationError) -> TabBarProjection =
            { request in
                try projectionTelemetry.project(request, using: project)
            }
        self.store = store
        self.repoCache = repoCache
        self.inboxAtom = inboxAtom
        self.projectionTelemetry = projectionTelemetry
        self.materializedProjection = TabBarMaterializedProjection(
            requestIdentity: \.generation,
            isValueEqual: ==,
            project: measuredProject,
            onProjectionCompletion: { completion in
                projectionTelemetry.recordCompletion(completion)
                onProjectionCompletion(completion)
            }
        )
        observe()
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        materializedProjection.stop()
    }

    isolated deinit {
        stop()
    }

    func visibleProjectionDidRender() {
        projectionTelemetry.recordVisibleProjection()
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
        let captureStartedAt = projectionTelemetry.captureStartedAt()
        let capture = withObservationTracking {
            TabBarProjectionCapture(
                request: TabBarProjectionRequest(
                    generation: generation,
                    coreRequest: CoreTabBarProjectionRequest.capture(
                        store: store,
                        repoCache: repoCache
                    ),
                    inboxAttentionFacts: inboxAtom.captureAttentionFacts()
                )
            )
        } onChange: { [weak self, weak materializedProjection] in
            materializedProjection?.sourceDidInvalidate()
            Task { @MainActor [weak self] in
                self?.captureAndAdmitNewestRequest()
            }
        }
        projectionTelemetry.recordAdmission(capture, startedAt: captureStartedAt)
        materializedProjection.admit(capture.request)
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

private final class TabBarProjectionTelemetry: Sendable {
    private struct Admission: Sendable {
        let sequence: UInt64
        let startedAt: ContinuousClock.Instant
        var tabCount: Int?
        var paneCount: Int?
        var activeTabPresent: Bool?
    }

    private struct State: Sendable {
        var admissionsBySequence: [UInt64: Admission] = [:]
        var pendingVisibleAdmission: Admission?
    }

    private let recorder: AgentStudioPerformanceTraceRecorder?
    private let clock = ContinuousClock()
    private let state = Mutex(State())

    init(recorder: AgentStudioPerformanceTraceRecorder?) {
        self.recorder = recorder
    }

    func captureStartedAt() -> ContinuousClock.Instant? {
        guard recorder?.isEnabled == true else { return nil }
        return clock.now
    }

    func recordAdmission(
        _ capture: TabBarProjectionCapture,
        startedAt: ContinuousClock.Instant?
    ) {
        guard let recorder, recorder.isEnabled, let startedAt else { return }
        let admission = Admission(
            sequence: capture.request.generation.value,
            startedAt: startedAt,
            tabCount: nil,
            paneCount: nil,
            activeTabPresent: nil
        )
        state.withLock { state in
            state.admissionsBySequence[admission.sequence] = admission
        }
        recorder.recordDuration(
            .tabBarRefresh,
            duration: startedAt.duration(to: clock.now),
            attributes: Self.attributes(for: admission)
        )
    }

    func project(
        _ request: TabBarProjectionRequest,
        using projector: @Sendable (TabBarProjectionRequest) throws(CancellationError) -> TabBarProjection
    ) throws(CancellationError) -> TabBarProjection {
        guard let recorder, recorder.isEnabled else {
            return try projector(request)
        }
        let startedAt = clock.now
        defer {
            if let admission = admission(for: request.generation.value) {
                recorder.recordDuration(
                    .tabBarWorker,
                    duration: startedAt.duration(to: clock.now),
                    attributes: Self.attributes(for: admission)
                )
            }
        }
        let projection = try projector(request)
        state.withLock { state in
            guard var admission = state.admissionsBySequence[request.generation.value] else { return }
            admission.tabCount = projection.items.count
            admission.paneCount = projection.items.reduce(into: 0) { count, item in
                count += item.panes.count
            }
            admission.activeTabPresent = projection.activeTabID != nil
            state.admissionsBySequence[request.generation.value] = admission
        }
        return projection
    }

    @MainActor
    func recordCompletion(_ completion: TabBarMaterializedProjection.ProjectionCompletion) {
        guard let recorder, recorder.isEnabled else { return }
        let sequence: UInt64
        let outcome: String
        let didPublish: Bool
        switch completion {
        case .published(let generation):
            sequence = generation.value
            outcome = "published"
            didPublish = true
        case .equal(let generation):
            sequence = generation.value
            outcome = "equal"
            didPublish = false
        case .superseded(let generation):
            sequence = generation.value
            outcome = "superseded"
            didPublish = false
        case .cancelled(let generation):
            sequence = generation.value
            outcome = "cancelled"
            didPublish = false
        }
        let admission = state.withLock { state -> Admission? in
            guard let admission = state.admissionsBySequence.removeValue(forKey: sequence) else {
                return nil
            }
            if didPublish {
                state.pendingVisibleAdmission = admission
            }
            return admission
        }
        guard let admission else { return }
        var attributes = Self.attributes(for: admission)
        attributes["agentstudio.performance.tabbar.terminal.outcome"] = .string(outcome)
        recorder.recordDuration(
            .tabBarTerminal,
            duration: admission.startedAt.duration(to: clock.now),
            attributes: attributes
        )
    }

    @MainActor
    func recordVisibleProjection() {
        guard let recorder, recorder.isEnabled else { return }
        let admission = state.withLock { state in
            defer { state.pendingVisibleAdmission = nil }
            return state.pendingVisibleAdmission
        }
        guard let admission else { return }
        recorder.recordDuration(
            .tabBarVisible,
            duration: admission.startedAt.duration(to: clock.now),
            attributes: Self.attributes(for: admission)
        )
    }

    private func admission(for sequence: UInt64) -> Admission? {
        state.withLock { state in
            state.admissionsBySequence[sequence]
        }
    }

    private static func attributes(
        for admission: Admission
    ) -> [String: AgentStudioTraceValue] {
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.tabbar.sequence": .int(Int(clamping: admission.sequence))
        ]
        if let tabCount = admission.tabCount {
            attributes["agentstudio.performance.tabbar.tab.count"] = .int(tabCount)
        }
        if let paneCount = admission.paneCount {
            attributes["agentstudio.performance.tabbar.pane.count"] = .int(paneCount)
        }
        if let activeTabPresent = admission.activeTabPresent {
            attributes["agentstudio.performance.tabbar.active_tab.present"] = .bool(activeTabPresent)
        }
        return attributes
    }
}
