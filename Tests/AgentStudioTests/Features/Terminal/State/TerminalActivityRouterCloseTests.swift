import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioTerminal

/// Split from `TerminalActivityRouterTests` (SwiftLint `type_body_length`): tests for the
/// `.surfaceClosed` ordered-control path, the canonical pane-removal owner for terminal activity
/// state.
@MainActor
@Suite("TerminalActivityRouter close", .serialized)
struct TerminalActivityRouterCloseTests {
    private final class SurfaceLifetimeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var isLive = true

        func retire() {
            lock.withLock { isLive = false }
        }

        func containsSurface() -> Bool {
            lock.withLock { isLive }
        }
    }

    @Test("ordered surface close clears compact state and pending quiet work")
    func orderedSurfaceCloseClearsCompactStateAndPendingQuietWork() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let clock = TestPushClock()
        let surfaceLifetime = SurfaceLifetimeBox()
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            surfaceIDForPaneID: { surfaceLifetime.containsSurface() ? $0 : nil },
            unseenActivityDebounceDuration: .milliseconds(750),
            unseenActivityClock: clock
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        await ingestActivity(
            paneId: paneId,
            totals: [100, 140],
            context: .init(isAttended: false, isAgentClassified: false, outputBurstThreshold: 30),
            through: router
        )
        await clock.waitForPendingSleepCount(atLeast: 1)
        surfaceLifetime.retire()
        await router.consumeTerminalActivityInput(
            .orderedControl(
                surfaceID: paneId.uuid,
                paneID: paneId.uuid,
                precedingAggregate: nil,
                control: .surfaceClosed
            )
        )
        await clock.waitForPendingSleepCount(exactly: 0)
        #expect(atom.snapshot(for: paneId.uuid) == nil)
        await router.stop()
    }

    @Test("ordered surface close clears pane activity status and resets its rate limit")
    func orderedSurfaceCloseClearsPaneActivityStatus() async {
        // F9: a closed pane must not retain its keyed PaneActivityStatusAtom fact or rate-limit
        // date for the process lifetime. The canonical close owner (surfaceClosed) is the only
        // place that knows a pane's identity is retiring, so it must invoke the clear closure the
        // same way it already clears TerminalActivityAtom's compact state.
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let surfaceLifetime = SurfaceLifetimeBox()
        final class ClearedPaneIdsBox: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var clearedPaneIds: [UUID] = []

            func record(_ paneId: UUID) {
                lock.lock()
                clearedPaneIds.append(paneId)
                lock.unlock()
            }
        }
        let clearedPaneIds = ClearedPaneIdsBox()
        let router = TerminalActivityRouter(
            bus: bus,
            activityAtom: atom,
            surfaceIDForPaneID: { surfaceLifetime.containsSurface() ? $0 : nil },
            clearPaneActivityStatus: { paneId in
                clearedPaneIds.record(paneId)
            }
        )
        let paneId = PaneId.generateUUIDv7()

        await router.start()
        surfaceLifetime.retire()
        await router.consumeTerminalActivityInput(
            .orderedControl(
                surfaceID: paneId.uuid,
                paneID: paneId.uuid,
                precedingAggregate: nil,
                control: .surfaceClosed
            )
        )

        #expect(clearedPaneIds.clearedPaneIds == [paneId.uuid])
        await router.stop()
    }

    private func ingestActivity(
        paneId: PaneId,
        totals: [Int],
        context: TerminalActivityProjectionContext,
        through router: TerminalActivityRouter,
        startedAtMilliseconds: Int64 = 1000
    ) async {
        guard let firstTotal = totals.first, let latestTotal = totals.last else { return }
        var aggregate = TerminalScrollbarActivityAggregate(
            state: ScrollbarState(top: 0, bottom: 10, total: firstTotal),
            observedAtMilliseconds: startedAtMilliseconds
        )
        for (index, totalRows) in totals.dropFirst().enumerated() {
            aggregate.merge(
                state: ScrollbarState(top: 0, bottom: 10, total: totalRows),
                observedAtMilliseconds: startedAtMilliseconds + Int64((index + 1) * 100)
            )
        }
        await router.consumeTerminalActivityInput(
            .aggregate(
                surfaceID: paneId.uuid,
                paneID: paneId.uuid,
                input: TerminalActivityAggregateInput(
                    aggregate: aggregate,
                    latestState: ScrollbarState(top: 0, bottom: 10, total: latestTotal),
                    context: context
                )
            )
        )
    }
}
