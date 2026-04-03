import Foundation
import Testing

@testable import AgentStudio

@Suite("RuntimeEnvelopeHarness")
struct RuntimeEnvelopeHarnessTests {
    @Test("topology and worktree envelope helpers preserve typed event families")
    func envelopeHelpersPreserveFamilies() async {
        let harness = EventBusHarness<RuntimeEnvelope>()
        let subscriber = await harness.makeSubscriber(bufferingPolicy: .unbounded)

        _ = await harness.post(
            RuntimeEnvelopeHarness.topologyEnvelope(
                event: .repoDiscovered(
                    repoPath: URL(fileURLWithPath: "/tmp/repo"),
                    parentPath: URL(fileURLWithPath: "/tmp")
                ),
                source: .builtin(.filesystemWatcher),
                seq: 10
            )
        )
        _ = await harness.post(
            RuntimeEnvelopeHarness.gitEnvelope(
                event: .originChanged(
                    repoId: UUID(),
                    from: "",
                    to: "git@github.com:askluna/agent-studio.git"
                ),
                seq: 11
            )
        )

        await assertEventuallyAsync("subscriber should observe two runtime envelopes") {
            await subscriber.snapshot().count == 2
        }

        let snapshot = await subscriber.snapshot()
        let systemEvents = RuntimeEnvelopeHarness.systemEvents(from: snapshot)
        let worktreeEvents = RuntimeEnvelopeHarness.worktreeEvents(from: snapshot)

        #expect(systemEvents.count == 1)
        #expect(worktreeEvents.count == 1)
        if case .topology(.repoDiscovered(let repoPath, let parentPath, _)) = systemEvents[0].event {
            #expect(repoPath == URL(fileURLWithPath: "/tmp/repo"))
            #expect(parentPath == URL(fileURLWithPath: "/tmp"))
        } else {
            Issue.record("expected topology repoDiscovered event")
        }
        if case .gitWorkingDirectory(.originChanged(_, _, let to)) = worktreeEvents[0].event {
            #expect(to == "git@github.com:askluna/agent-studio.git")
        } else {
            Issue.record("expected git originChanged event")
        }

        await subscriber.shutdown()
        await assertBusDrained(harness.bus)
    }
}
