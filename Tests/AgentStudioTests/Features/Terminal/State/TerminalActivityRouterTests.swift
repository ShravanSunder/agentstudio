import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalActivityRouter", .serialized)
struct TerminalActivityRouterTests {
    @Test("consumes pane terminal events from runtime bus into activity atom")
    func consumesPaneTerminalEventsFromRuntimeBusIntoActivityAtom() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.progressReportUpdated(ProgressState(kind: .set, percent: 25))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )

        await assertEventuallyMain("terminal activity router should update progress") {
            atom.snapshot(for: paneId.uuid)?.progress == .reported(ProgressState(kind: .set, percent: 25))
        }

        router.stop()
    }

    @Test("start is idempotent and does not double-consume events")
    func startIsIdempotentAndDoesNotDoubleConsumeEvents() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom()
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.openURLRequested(url: "https://example.com", kind: .text)),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )

        await assertEventuallyMain("idempotent start should consume one URL request") {
            atom.snapshot(for: paneId.uuid)?.recentURLRequests.count == 1
        }

        router.stop()
    }

    @Test("stop prevents later runtime events from mutating activity")
    func stopPreventsLaterRuntimeEventsFromMutatingActivity() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom()
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        router.stop()
        _ = await bus.post(
            .pane(
                .test(
                    event: .terminal(.progressReportUpdated(ProgressState(kind: .set, percent: 99))),
                    paneId: paneId,
                    paneKind: .terminal
                )
            )
        )
        await Task.yield()

        #expect(atom.snapshot(for: paneId.uuid) == nil)
    }

    @Test("non-terminal pane envelopes are ignored")
    func nonTerminalPaneEnvelopesAreIgnored() async {
        let bus = EventBus<RuntimeEnvelope>()
        let atom = TerminalActivityAtom()
        let router = TerminalActivityRouter(bus: bus, activityAtom: atom)
        let paneId = PaneId()

        await router.start()
        _ = await bus.post(
            .pane(
                .test(
                    event: .browser(.pageLoaded(url: URL(fileURLWithPath: "/tmp/index.html"))),
                    paneId: paneId,
                    paneKind: .browser
                )
            )
        )
        await Task.yield()

        #expect(atom.snapshot(for: paneId.uuid) == nil)
        router.stop()
    }
}
