import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxPromoter tracing")
struct InboxPromoterTraceTests {
    private struct TraceRecord: Decodable {
        let body: String
        let attributes: [String: TraceAttribute]
    }

    private enum TraceAttribute: Decodable, Equatable {
        case bool(Bool)
        case int(Int)
        case string(String)
        case other

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .int(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else {
                self = .other
            }
        }
    }

    @Test("promoted settled activity emits exact inbox promote trace contract")
    func promotedSettledActivityEmitsExactInboxPromoteTraceContract() async throws {
        let paneId = UUID()
        let activityId = UUID()
        let atom = InboxNotificationAtom()
        let traceRuntime = makeTraceRuntime(name: "inbox-promoter-promote", processIdentifier: 610)
        let promoter = InboxPromoter(
            inboxAtom: atom,
            autoClearPolicy: .init(),
            policySnapshot: {
                .init(
                    attendedPaneId: nil,
                    observedPaneIds: [],
                    pinnedToBottomByPaneId: [:]
                )
            },
            traceRuntime: traceRuntime,
            now: { Date(timeIntervalSince1970: 100) }
        )

        promoter.promoteSettledActivity(
            makeSettledActivity(burstWindowId: activityId, rowsAdded: 44),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        await promoter.drainTraceRecords()

        let record = try #require(
            try traceRecords(from: traceRuntime).first { $0.body == "inbox.promote" }
        )
        #expect(record.attributes["agentstudio.inbox.decision"] == .string("promote"))
        #expect(record.attributes["agentstudio.inbox.reason"] == .string("claim_appended"))
        #expect(
            record.attributes["agentstudio.inbox.kind"]
                == .string(InboxNotificationKind.unseenActivity.rawValue)
        )
        #expect(
            record.attributes["agentstudio.inbox.claim.lane"]
                == .string(InboxNotificationClaimLane.activity.rawValue)
        )
        #expect(
            record.attributes["agentstudio.inbox.claim.semantic"]
                == .string(InboxNotificationClaimSemantic.unseenActivity.rawValue)
        )
        #expect(record.attributes["agentstudio.inbox.notification.coalesced"] == .bool(false))
        #expect(record.attributes["agentstudio.inbox.read"] == .bool(false))
        #expect(record.attributes["agentstudio.pane.id"] == .string(paneId.uuidString))
        #expect(record.attributes["agentstudio.pane.observed"] == .bool(false))
        #expect(record.attributes["agentstudio.pane.pinned_to_bottom"] == .bool(false))
        #expect(record.attributes["terminal.activity.rows_added"] == .int(44))
        #expect(record.attributes["terminal.activity.threshold_rows"] == .int(30))
        #expect(record.attributes["terminal.activity.window_id"] == .string(activityId.uuidString))
        #expect(record.attributes["terminal.activity.source"] == .string("scrollbar"))
    }

    @Test("observed small activity suppression emits exact inbox promote trace contract")
    func observedSmallActivitySuppressionEmitsExactInboxPromoteTraceContract() async throws {
        let paneId = UUID()
        let activityId = UUID()
        let atom = InboxNotificationAtom()
        let traceRuntime = makeTraceRuntime(name: "inbox-promoter-suppress", processIdentifier: 611)
        let promoter = InboxPromoter(
            inboxAtom: atom,
            autoClearPolicy: .init(),
            policySnapshot: {
                .init(
                    attendedPaneId: nil,
                    observedPaneIds: [paneId],
                    pinnedToBottomByPaneId: [paneId: true]
                )
            },
            traceRuntime: traceRuntime,
            now: { Date(timeIntervalSince1970: 100) }
        )

        promoter.promoteSettledActivity(
            makeSettledActivity(burstWindowId: activityId, rowsAdded: 12),
            paneId: paneId,
            context: .init(paneId: paneId)
        )
        await promoter.drainTraceRecords()

        #expect(atom.notifications.isEmpty)
        let record = try #require(try traceRecords(from: traceRuntime).first { $0.body == "inbox.promote" })
        #expect(record.attributes["agentstudio.inbox.decision"] == .string("suppress"))
        #expect(record.attributes["agentstudio.inbox.reason"] == .string("observed_small_activity"))
        #expect(record.attributes["agentstudio.inbox.kind"] == .string(InboxNotificationKind.unseenActivity.rawValue))
        #expect(record.attributes["agentstudio.inbox.claim.lane"] == nil)
        #expect(record.attributes["agentstudio.inbox.notification.coalesced"] == .bool(false))
        #expect(record.attributes["agentstudio.inbox.read"] == .bool(true))
        #expect(record.attributes["agentstudio.pane.observed"] == .bool(true))
        #expect(record.attributes["agentstudio.pane.pinned_to_bottom"] == .bool(true))
        #expect(record.attributes["terminal.activity.rows_added"] == .int(12))
        #expect(record.attributes["terminal.activity.window_id"] == .string(activityId.uuidString))
    }

    private func makeTraceRuntime(name: String, processIdentifier: Int32) -> AgentStudioTraceRuntime {
        AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": temporaryTraceDirectoryURL().path,
                "AGENTSTUDIO_TRACE_FLUSH": "immediate",
                "AGENTSTUDIO_TRACE_NAME": name,
                "AGENTSTUDIO_TRACE_TAGS": "inbox",
            ]),
            processIdentifier: processIdentifier,
            sessionID: "inbox-promoter-trace-session",
            timeUnixNano: { 2000 }
        )
    }

    private func traceRecords(from traceRuntime: AgentStudioTraceRuntime) throws -> [TraceRecord] {
        let fileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents.split(separator: "\n").map { line in
            try JSONDecoder().decode(TraceRecord.self, from: Data(line.utf8))
        }
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-inbox-promoter-trace-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeSettledActivity(
        burstWindowId: UUID,
        rowsAdded: Int
    ) -> TerminalSettledActivity {
        .init(
            burstWindowId: burstWindowId,
            thresholdRows: 30,
            debounceMilliseconds: 750,
            startedAtMilliseconds: 1000,
            settledAtMilliseconds: 1750,
            eventCount: 2,
            rowsAdded: rowsAdded,
            baselineRows: 100,
            latestRows: 100 + rowsAdded,
            isPinnedToBottom: false
        )
    }
}
