import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct NotificationReducerTests {
    @Test("critical events are emitted immediately")
    func criticalImmediate() async {
        let reducer = NotificationReducer()
        var iterator = reducer.criticalEvents.makeAsyncIterator()

        let envelope = makePaneEnvelope(
            seq: 1,
            event: .terminal(.bellRang)
        )
        reducer.submit(envelope)

        let received = await iterator.next()
        #expect(received?.seq == envelope.seq)
    }

    @Test("lossy events coalesce by key and latest wins")
    func lossyCoalesces() async {
        let reducer = NotificationReducer()
        var iterator = reducer.batchedEvents.makeAsyncIterator()
        let source = EventSource.pane(PaneId())

        let first = makePaneEnvelope(
            seq: 1,
            source: source,
            event: .terminal(.scrollbarChanged(ScrollbarState(top: 1, bottom: 10, total: 100)))
        )
        let second = makePaneEnvelope(
            seq: 2,
            source: source,
            event: .terminal(.scrollbarChanged(ScrollbarState(top: 2, bottom: 11, total: 100)))
        )
        reducer.submit(first)
        reducer.submit(second)

        let batch = await iterator.next()
        #expect(batch?.count == 1)
        #expect(batch?.first?.seq == 2)
    }

    @Test("critical events are ordered by visibility tier before emission")
    func criticalTierOrdering() async {
        let highTierPaneId = PaneId()
        let lowTierPaneId = PaneId()
        let resolver = TestVisibilityTierResolver(
            mapping: [
                highTierPaneId: .p0ActivePane,
                lowTierPaneId: .p3Background,
            ]
        )
        let reducer = NotificationReducer(tierResolver: resolver)
        var iterator = reducer.criticalEvents.makeAsyncIterator()

        reducer.submit(makePaneEnvelope(seq: 1, source: .pane(lowTierPaneId), event: .terminal(.bellRang)))
        reducer.submit(makePaneEnvelope(seq: 2, source: .pane(highTierPaneId), event: .terminal(.bellRang)))

        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.source == .pane(highTierPaneId))
        #expect(second?.source == .pane(lowTierPaneId))
    }

    @Test("lossy batch ordering prioritizes visibility tier")
    func lossyTierOrdering() async {
        let highTierPaneId = PaneId()
        let lowTierPaneId = PaneId()
        let resolver = TestVisibilityTierResolver(
            mapping: [
                highTierPaneId: .p0ActivePane,
                lowTierPaneId: .p3Background,
            ]
        )
        let reducer = NotificationReducer(tierResolver: resolver)
        var iterator = reducer.batchedEvents.makeAsyncIterator()

        reducer.submit(
            makePaneEnvelope(
                seq: 1,
                source: .pane(lowTierPaneId),
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 1, bottom: 10, total: 100)))
            )
        )
        reducer.submit(
            makePaneEnvelope(
                seq: 2,
                source: .pane(highTierPaneId),
                event: .terminal(.scrollbarChanged(ScrollbarState(top: 1, bottom: 10, total: 100)))
            )
        )

        let batch = await iterator.next()
        #expect(batch?.count == 2)
        #expect(batch?.first?.source == .pane(highTierPaneId))
        #expect(batch?.last?.source == .pane(lowTierPaneId))
    }

    @Test("system-source events are treated as p0 and emitted ahead of background pane events")
    func systemEventsPrioritizedAsP0() async {
        let lowTierPaneId = PaneId()
        let worktreeId = UUID()
        let repoId = UUID()
        let resolver = TestVisibilityTierResolver(
            mapping: [
                lowTierPaneId: .p3Background
            ]
        )
        let reducer = NotificationReducer(tierResolver: resolver)
        var iterator = reducer.criticalEvents.makeAsyncIterator()

        reducer.submit(
            makePaneEnvelope(
                seq: 1,
                source: .pane(lowTierPaneId),
                event: .terminal(.bellRang)
            )
        )
        reducer.submit(
            .system(
                SystemEnvelope.test(
                    event: .topology(
                        .worktreeRegistered(
                            worktreeId: worktreeId, repoId: repoId,
                            rootPath: URL(fileURLWithPath: "/tmp/worktree-\(UUID().uuidString)"))),
                    source: .builtin(.filesystemWatcher),
                    seq: 2
                )
            )
        )

        let first = await iterator.next()
        let second = await iterator.next()

        #expect(first?.source == .system(.builtin(.filesystemWatcher)))
        #expect(second?.source == .pane(lowTierPaneId))
    }

    @Test("system topology stays system-scoped with no legacy bridge conversion")
    func systemTopologyStaysSystemScoped() async {
        let reducer = NotificationReducer()
        var iterator = reducer.criticalEvents.makeAsyncIterator()
        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/reducer-\(UUID().uuidString)")

        reducer.submit(
            .system(
                SystemEnvelope.test(
                    event: .topology(.worktreeRegistered(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)),
                    source: .builtin(.filesystemWatcher),
                    seq: 99
                )
            )
        )

        let received = await iterator.next()
        guard case .system(let systemEnvelope) = received else {
            Issue.record("Expected system envelope")
            return
        }

        #expect(systemEnvelope.seq == 99)
        #expect(systemEnvelope.source == .builtin(.filesystemWatcher))
        guard
            case .topology(.worktreeRegistered(let mappedWorktreeId, let mappedRepoId, let mappedRootPath)) =
                systemEnvelope.event
        else {
            Issue.record("Expected system topology worktreeRegistered event")
            return
        }
        #expect(mappedWorktreeId == worktreeId)
        #expect(mappedRepoId == repoId)
        #expect(mappedRootPath == rootPath)
    }

    private func makePaneEnvelope(
        seq: UInt64,
        source: EventSource = .pane(PaneId()),
        paneKind: PaneContentType = .terminal,
        event: PaneRuntimeEvent
    ) -> RuntimeEnvelope {
        let clock = ContinuousClock()
        let resolvedPaneId: PaneId
        switch source {
        case .pane(let paneId):
            resolvedPaneId = paneId
        case .worktree, .system:
            resolvedPaneId = PaneId()
        }

        return .pane(
            PaneEnvelope(
                source: source,
                seq: seq,
                timestamp: clock.now,
                paneId: resolvedPaneId,
                paneKind: paneKind,
                event: event
            )
        )
    }
}

@MainActor
private final class TestVisibilityTierResolver: VisibilityTierResolver {
    private let mapping: [PaneId: VisibilityTier]

    init(mapping: [PaneId: VisibilityTier]) {
        self.mapping = mapping
    }

    func tier(for paneId: PaneId) -> VisibilityTier {
        mapping[paneId] ?? .p3Background
    }
}
