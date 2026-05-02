import Foundation
import Testing

@testable import AgentStudio

@Suite("RuntimeEnvelopeTraceSummary")
struct RuntimeEnvelopeTraceSummaryTests {
    @Test("pane summaries carry stable eventbus attributes")
    func paneSummariesCarryStableEventbusAttributes() throws {
        let paneId = PaneId()
        let eventId = UUID()
        let correlationId = UUID()
        let causationId = UUID()
        let commandId = UUID()
        let envelope = PaneEnvelope.test(
            event: .terminal(.bellRang),
            paneId: paneId,
            paneKind: .terminal,
            seq: 42,
            eventId: eventId,
            correlationId: correlationId,
            causationId: causationId,
            commandId: commandId
        )

        let summary = RuntimeEnvelopeTraceSummary(envelope)
        let attributes = summary.attributes(
            eventBusName: "paneRuntime",
            consumerName: "InboxNotificationRouter"
        )

        #expect(attributes["agentstudio.eventbus.consumer"] == .string("InboxNotificationRouter"))
        #expect(attributes["agentstudio.eventbus.name"] == .string("paneRuntime"))
        #expect(attributes["agentstudio.envelope.event_id"] == .string(eventId.uuidString))
        #expect(attributes["agentstudio.envelope.scope"] == .string("pane"))
        #expect(attributes["agentstudio.envelope.schema_version"] == .int(Int(RuntimeEnvelopeSchema.current)))
        #expect(attributes["agentstudio.envelope.seq"] == .int(42))
        #expect(attributes["agentstudio.runtime.event"] == .string("terminal.bellRang"))
        #expect(attributes["agentstudio.runtime.action_policy"] == .string("critical"))
        #expect(attributes["agentstudio.envelope.correlation_id"] == .string(correlationId.uuidString))
        #expect(attributes["agentstudio.envelope.causation_id"] == .string(causationId.uuidString))
        #expect(attributes["agentstudio.command.id"] == .string(commandId.uuidString))
        #expect(attributes["agentstudio.pane.id"] == .string(paneId.uuidString))
        #expect(attributes["agentstudio.pane.kind"] == .string("terminal"))
    }

    @Test("high-volume activity-only events are excluded from default eventbus traces")
    func highVolumeActivityOnlyEventsAreExcludedFromDefaultEventBusTraces() {
        #expect(
            RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(
                .terminal(.scrollbarChanged(ScrollbarState(top: 0, bottom: 10, total: 100)))
            )
        )
        #expect(RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(.terminal(.titleChanged("prompt"))))
        #expect(RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(.terminal(.cwdChanged("/tmp"))))
        #expect(
            RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(
                .browser(.consoleMessage(level: .log, message: "render"))
            )
        )
        #expect(RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(.terminal(.bellRang)) == false)
        #expect(
            RuntimeEnvelopeTraceSummary.isHighVolumeActivityOnly(
                .terminal(.desktopNotificationRequested(title: "done", body: "ok"))
            ) == false
        )
    }
}
