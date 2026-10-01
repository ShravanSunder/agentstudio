import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import AgentStudioTestHarness
import Foundation
import GRDB
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore

@MainActor
@Suite("Pane CLI outbox drain", .serialized)
struct PaneCLIOutboxDrainTests {
    @Test("one queued message becomes late evidence and advances the cursor without changing the outbox")
    func queuedMessageIsAdmittedLateAndReadThrough() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(paneID: paneID, line: harness.messageLine(text: "deploy finished"))

            let report = await harness.drain()

            #expect(report.admittedEntryCount == 1)
            #expect(report.retryableEntryCount == 0)
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.rows() == [entry])
            let snapshot = try await harness.snapshot(paneID: paneID)
            #expect(snapshot.messages.count == 1)
            #expect(snapshot.messages.first?.text == "deploy finished")
            #expect(snapshot.messages.first?.freshness == .late)
            #expect(snapshot.messages.first?.attribution == .unattributed)
        }
    }

    @Test("duplicate message id and a restarted drain produce one durable occurrence")
    func duplicateMessageIsAdmittedOnce() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let line = try harness.messageLine(text: "duplicate", correlationID: UUIDv7.generate())
            let first = try await harness.append(paneID: paneID, line: line)
            let duplicate = try await harness.append(paneID: paneID, line: line)

            let report = await harness.drain()
            let restarted = try await harness.restartedDrain()

            #expect(first == duplicate)
            #expect(report.admittedEntryCount == 1)
            #expect(restarted.admittedEntryCount == 0)
            #expect(try await harness.cursor() == first.id)
            #expect(try await harness.snapshot(paneID: paneID).messages.count == 1)
        }
    }

    @Test("malformed envelopes are refused while later valid notices advance the prefix")
    func malformedEnvelopeIsSkipped() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            _ = try await harness.append(paneID: paneID, line: #"{"not":"a json-rpc request"}"#)
            let survivor = try await harness.append(paneID: paneID, line: harness.messageLine(text: "survivor"))

            let report = await harness.drain()

            #expect(report.malformedEntryCount == 1)
            #expect(report.admittedEntryCount == 1)
            #expect(try await harness.cursor() == survivor.id)
            #expect(try await harness.rows().count == 2)
            #expect(try await harness.snapshot(paneID: paneID).messages.map(\.text) == ["survivor"])
        }
    }

    @Test("provider events in the outbox never reach Sessions admission")
    func providerEventIsNeverAdmitted() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(paneID: paneID, line: harness.providerEventLine())

            let report = await harness.drain()

            #expect(report.malformedEntryCount == 1)
            #expect(report.admittedEntryCount == 0)
            #expect(harness.refusalRecorder.reasons == [.ineligibleMethod])
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.snapshot(paneID: paneID).currentBinding == nil)
        }
    }

    @Test("a wire handle naming another pane is refused for the row's pane")
    func foreignHandleIsRefused() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(
                paneID: paneID,
                line: harness.messageLine(text: "wrong pane", handle: UUIDv7.generate().uuidString))

            let report = await harness.drain()

            #expect(report.malformedEntryCount == 1)
            #expect(harness.refusalRecorder.reasons == [.foreignPane])
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.snapshot(paneID: paneID).messages.isEmpty)
        }
    }

    @Test("datastore failure leaves the cursor and row intact for the next readiness")
    func datastoreFailureRetainsUnreadEntry() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(paneID: paneID, line: harness.messageLine(text: "retry me"))
            await harness.sqliteAccess.setRejectsWrites(true)

            let failed = await harness.drain()

            #expect(failed.admittedEntryCount == 0)
            #expect(failed.retryableEntryCount == 1)
            #expect(try await harness.cursor() == 0)
            #expect(try await harness.rows() == [entry])
            await harness.sqliteAccess.setRejectsWrites(false)
            let retried = try await harness.restartedDrain()
            #expect(retried.admittedEntryCount == 1)
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.snapshot(paneID: paneID).messages.count == 1)
        }
    }

    @Test("an unbound pane's deliberate report stays unread until the pane binds")
    func unboundDeliberateReportWaitsForBinding() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(
                paneID: paneID,
                line: harness.reportLine(kind: .needsYou, explanation: "approve the plan"))

            let beforeBinding = await harness.drain()

            #expect(beforeBinding.retryableEntryCount == 1)
            #expect(beforeBinding.refusedEntryCount == 0)
            #expect(try await harness.cursor() == 0)
            #expect(try await harness.rows() == [entry])
            try await harness.bindPane(paneID: paneID)
            let afterBinding = await harness.drain()
            #expect(afterBinding.admittedEntryCount == 1)
            #expect(afterBinding.retryableEntryCount == 0)
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.snapshot(paneID: paneID).currentAttention.count == 1)
        }
    }

    @Test("an over-limit payload is refused without holding its valid neighbour")
    func overLimitEnvelopeIsSkipped() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            _ = try await harness.append(
                paneID: paneID,
                line: harness.messageLine(
                    text: String(repeating: "x", count: AppPolicies.IPC.offlineNoticeMaximumPayloadBytes)))
            let survivor = try await harness.append(paneID: paneID, line: harness.messageLine(text: "survivor"))

            let report = await harness.drain()

            #expect(report.malformedEntryCount == 1)
            #expect(report.admittedEntryCount == 1)
            #expect(try await harness.cursor() == survivor.id)
            #expect(try await harness.rows().count == 2)
            #expect(try await harness.snapshot(paneID: paneID).messages.map(\.text) == ["survivor"])
        }
    }

    @Test("a CLI write lock does not hold the app's readonly drain")
    func heldCLIWriterDoesNotBlockTheReader() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(
                paneID: paneID, line: harness.messageLine(text: "committed before lock"))
            let held = HeldStep<Void>("CLI writer transaction holds the write lock")
            let writer = harness.writer
            let lockOwner = Task {
                try await valueFromDedicatedThread {
                    try writer.databaseQueue.write { _ in try held.arriveBlocking(()) }
                }
            }
            do {
                try await held.firstArrival()
                let report = await harness.drain()
                #expect(report.admittedEntryCount == 1)
                #expect(try await harness.cursor() == entry.id)
                held.release()
                try await lockOwner.value
            } catch {
                held.release()
                _ = try? await lockOwner.value
                throw error
            }
        }
    }

    @Test("queued needs-you and done from before relaunch become history")
    func deliberateReportsSurviveRelaunch() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            try await harness.bindPane(paneID: paneID)
            try await harness.simulateRelaunch()
            let stateAfterRelaunch = try await harness.snapshot(paneID: paneID).state
            _ = try await harness.append(
                paneID: paneID, line: harness.reportLine(kind: .needsYou, explanation: "approve the plan"))
            let last = try await harness.append(paneID: paneID, line: harness.reportLine(kind: .done, explanation: nil))

            let report = await harness.drain()

            #expect(report.admittedEntryCount == 2)
            #expect(report.refusedEntryCount == 0)
            #expect(try await harness.cursor() == last.id)
            let snapshot = try await harness.snapshot(paneID: paneID)
            #expect(snapshot.state == stateAfterRelaunch)
            #expect(snapshot.currentAttention.isEmpty)
            #expect(snapshot.results.count == 1)
            #expect(snapshot.results.first?.freshness == .late)
            #expect(snapshot.historicalOccurrenceIds.count == 2)
        }
    }

    @Test("a partial drain advances only the handled prefix and keeps later rows ordered")
    func partialDrainPreservesUnreadPrefix() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let handled = try await harness.append(paneID: paneID, line: harness.messageLine(text: "first"))
            let retry = try await harness.append(
                paneID: paneID, line: harness.reportLine(kind: .needsYou, explanation: "bind first"))
            let later = try await harness.append(
                paneID: paneID, line: harness.messageLine(text: "must stay behind retry"))

            let report = await harness.drain()

            #expect(report.admittedEntryCount == 1)
            #expect(report.retryableEntryCount == 1)
            #expect(try await harness.cursor() == handled.id)
            #expect(try await harness.rows() == [handled, retry, later])
            #expect(try await harness.snapshot(paneID: paneID).messages.map(\.text) == ["first"])
        }
    }

    @Test("a concurrent CLI append during partial drain is never lost")
    func concurrentAppendDuringPartialDrainSurvives() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let handled = try await harness.append(paneID: paneID, line: harness.messageLine(text: "first"))
            let retry = try await harness.append(
                paneID: paneID, line: harness.reportLine(kind: .needsYou, explanation: "bind first"))
            let appendedLine = try harness.reportLine(kind: .needsYou, explanation: "second approval")

            async let drained = harness.drain()
            async let appended = harness.append(paneID: paneID, line: appendedLine)
            let (report, last) = try await (drained, appended)

            #expect(report.admittedEntryCount == 1)
            #expect(report.retryableEntryCount == 1)
            #expect(try await harness.cursor() == handled.id)
            #expect(try await harness.rows() == [handled, retry, last])
        }
    }

    @Test("cursor commit failure rolls back the notice effect too")
    func cursorAndNoticeCommitAtomically() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(paneID: paneID, line: harness.messageLine(text: "atomic message"))
            await harness.sqliteAccess.failCursorCommit()

            let report = await harness.drain()

            #expect(report.admittedEntryCount == 0)
            #expect(report.retryableEntryCount == 1)
            #expect(try await harness.cursor() == 0)
            #expect(try await harness.snapshot(paneID: paneID).messages.isEmpty)
            #expect(try await harness.rows() == [entry])
        }
    }

    @Test("a store from a foreign release channel is refused without cursor progress")
    func foreignStoreIsRefused() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(paneID: paneID, line: harness.messageLine(text: "foreign channel"))
            let writer = harness.writer
            try await valueFromDedicatedThread {
                try writer.databaseQueue.write { database in
                    try database.execute(sql: "UPDATE cli_store_identity SET channel = 'beta'")
                }
            }

            let report = await harness.drain()

            #expect(report.refusedStoreCount == 1)
            #expect(harness.refusalRecorder.reasons == [.foreignStore])
            #expect(report.admittedEntryCount == 0)
            #expect(try await harness.cursor() == 0)
            #expect(try await harness.rows() == [entry])
        }
    }

    @Test("old NDJSON files are admitted once and removed; no new spool path remains")
    func legacyFilesAreImportedOnceAndRemoved() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            try harness.writeLegacyFile(paneID: paneID, lines: [harness.messageLine(text: "legacy notice")])

            let first = await harness.drain()
            let restarted = try await harness.restartedDrain()

            #expect(first.importedLegacyLineCount == 1)
            #expect(restarted.importedLegacyLineCount == 0)
            #expect(!FileManager.default.fileExists(atPath: harness.legacyFileURL(paneID: paneID).path))
            #expect(try await harness.snapshot(paneID: paneID).messages.map(\.text) == ["legacy notice"])
            // The app must not insert the imported envelope into the CLI file.
            #expect(try await harness.rows().isEmpty)
        }
    }

    @Test("an unknown stored kind is dispositioned with telemetry and cursor progress")
    func unknownStoredKindAdvancesTheRefusedPrefix() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            let entry = try await harness.append(paneID: paneID, line: harness.messageLine(text: "future kind"))
            let writer = harness.writer
            try await valueFromDedicatedThread {
                try writer.databaseQueue.write { database in
                    try database.execute(
                        sql: "UPDATE cli_outbox SET kind = 'future-kind' WHERE id = ?", arguments: [entry.id])
                }
            }

            let report = await harness.drain()

            #expect(report.malformedEntryCount == 1)
            #expect(harness.refusalRecorder.reasons == [.unknownKind])
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.snapshot(paneID: paneID).messages.isEmpty)
            let storedCount = try await valueFromDedicatedThread {
                try writer.databaseQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cli_outbox") }
            }
            #expect(storedCount == 1)
        }
    }

    @Test("a forged offline clear never reaches the live deliberate-report mutation")
    func offlineClearCannotClearAttention() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            try await harness.bindPane(paneID: paneID)
            _ = try await harness.admission.recordDeliberateReport(
                paneId: paneID,
                params: IPCSessionReportParams(
                    handle: "self", kind: .needsYou, explanation: "keep attention",
                    correlationId: UUIDv7.generate()))
            let attention = try await harness.snapshot(paneID: paneID).currentAttention
            #expect(attention.count == 1)
            let entry = try await harness.append(
                paneID: paneID, line: harness.reportLine(kind: .clearNeedsYou, explanation: nil))

            let report = await harness.drain()

            #expect(report.malformedEntryCount == 1)
            #expect(harness.refusalRecorder.reasons == [.ineligibleVariant])
            #expect(try await harness.cursor() == entry.id)
            #expect(try await harness.snapshot(paneID: paneID).currentAttention == attention)
        }
    }

    @Test("an unbound legacy report survives first-start import until it can be admitted")
    func legacyRetryIsNotDiscarded() async throws {
        try await withPaneCLIOutboxDrainHarness { harness in
            let paneID = UUIDv7.generate()
            try harness.writeLegacyFile(
                paneID: paneID, lines: [harness.reportLine(kind: .needsYou, explanation: "legacy approval")])

            _ = await harness.drain()

            #expect(FileManager.default.fileExists(atPath: harness.legacyFileURL(paneID: paneID).path))
            try await harness.bindPane(paneID: paneID)
            let retried = try await harness.restartedDrain()
            #expect(retried.importedLegacyLineCount == 1)
            #expect(!FileManager.default.fileExists(atPath: harness.legacyFileURL(paneID: paneID).path))
            #expect(try await harness.snapshot(paneID: paneID).currentAttention.count == 1)
        }
    }
}
