import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalActivityAtom")
struct TerminalActivityAtomTests {
    private func paneEnvelope(
        paneId: PaneId = PaneId.generateUUIDv7(),
        event: GhosttyEvent,
        seq: UInt64 = 1
    ) -> PaneEnvelope {
        .test(
            event: .terminal(event),
            paneId: paneId,
            paneKind: .terminal,
            seq: seq
        )
    }

    @Test("tracks every progress state including non-error and remove")
    func tracksEveryProgressStateIncludingNonErrorAndRemove() {
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let paneId = PaneId.generateUUIDv7()

        atom.consume(
            paneEnvelope(
                paneId: paneId,
                event: .progressReportUpdated(ProgressState(kind: .set, percent: 42))
            )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.progress == .reported(ProgressState(kind: .set, percent: 42)))

        atom.consume(
            paneEnvelope(
                paneId: paneId,
                event: .progressReportUpdated(ProgressState(kind: .paused, percent: nil)),
                seq: 2
            )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.progress == .reported(ProgressState(kind: .paused, percent: nil)))

        atom.consume(
            paneEnvelope(
                paneId: paneId,
                event: .progressReportUpdated(nil),
                seq: 3
            )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.progress == .removed)
    }

    @Test("tracks cwd and recent URL requests without turning them into notifications")
    func tracksCwdAndRecentURLRequests() {
        let atom = TerminalActivityAtom(outputBurstThreshold: 30, recentURLLimit: 2)
        let paneId = PaneId.generateUUIDv7()

        atom.consume(paneEnvelope(paneId: paneId, event: .cwdChanged("/tmp/project")))
        atom.consume(
            paneEnvelope(
                paneId: paneId,
                event: .openURLRequested(url: "https://one.example", kind: .text),
                seq: 2
            )
        )
        atom.consume(
            paneEnvelope(
                paneId: paneId,
                event: .openURLRequested(url: "https://two.example", kind: .html),
                seq: 3
            )
        )
        atom.consume(
            paneEnvelope(
                paneId: paneId,
                event: .openURLRequested(url: "https://three.example", kind: .unknown),
                seq: 4
            )
        )

        let snapshot = atom.snapshot(for: paneId.uuid)
        #expect(snapshot?.cwd == URL(fileURLWithPath: "/tmp/project"))
        #expect(snapshot?.recentURLRequests.map(\.url) ?? [] == ["https://two.example", "https://three.example"])
        #expect(snapshot?.recentURLRequests.map(\.kind) ?? [] == [.html, .unknown])
    }

    @Test("compact projector updates replace scrollbar and output burst state")
    func compactProjectorUpdatesReplaceScrollbarAndOutputBurstState() {
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let paneId = PaneId.generateUUIDv7()
        let surfaceID = UUIDv7.generate()

        atom.apply(
            TerminalActivityCompactUpdate(
                surfaceID: surfaceID,
                paneID: paneId.uuid,
                scrollbarState: ScrollbarState(top: 50, bottom: 80, total: 100),
                outputBurst: .quiet(lastTotal: 100)
            )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.outputBurst == .quiet(lastTotal: 100))

        atom.apply(
            TerminalActivityCompactUpdate(
                surfaceID: surfaceID,
                paneID: paneId.uuid,
                scrollbarState: ScrollbarState(top: 80, bottom: 110, total: 135),
                outputBurst: .accumulating(
                    TerminalOutputBurst(
                        baselineTotal: 100,
                        latestTotal: 135,
                        addedRows: 35,
                        threshold: 30
                    )
                )
            )
        )
        #expect(
            atom.snapshot(for: paneId.uuid)?.outputBurst
                == .accumulating(
                    TerminalOutputBurst(
                        baselineTotal: 100,
                        latestTotal: 135,
                        addedRows: 35,
                        threshold: 30
                    )
                )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.outputBurst.thresholdReached == true)
    }

    @Test("scrollbar state records pinned-to-bottom observation")
    func scrollbarStateRecordsPinnedToBottomObservation() {
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let paneId = PaneId.generateUUIDv7()

        atom.apply(
            TerminalActivityCompactUpdate(
                surfaceID: UUIDv7.generate(),
                paneID: paneId.uuid,
                scrollbarState: ScrollbarState(top: 40, bottom: 80, total: 100),
                outputBurst: .quiet(lastTotal: 100)
            )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.scrollbarState?.isPinnedToBottom == false)
        #expect(atom.snapshot(for: paneId.uuid)?.isPinnedToBottom == false)

        atom.apply(
            TerminalActivityCompactUpdate(
                surfaceID: UUIDv7.generate(),
                paneID: paneId.uuid,
                scrollbarState: ScrollbarState(top: 80, bottom: 100, total: 100),
                outputBurst: .quiet(lastTotal: 100)
            )
        )
        #expect(atom.snapshot(for: paneId.uuid)?.scrollbarState?.isPinnedToBottom == true)
        #expect(atom.snapshot(for: paneId.uuid)?.isPinnedToBottom == true)
    }

    @Test("clear removes per-pane terminal activity")
    func clearRemovesPerPaneTerminalActivity() {
        let atom = TerminalActivityAtom(outputBurstThreshold: 30)
        let paneId = PaneId.generateUUIDv7()

        atom.consume(paneEnvelope(paneId: paneId, event: .cwdChanged("/tmp/project")))
        atom.clear(paneId: paneId.uuid)

        #expect(atom.snapshot(for: paneId.uuid) == nil)
    }
}
