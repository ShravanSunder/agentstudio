import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioSessions
import AgentStudioTestHarness
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("PaneContext Sessions bridge integration")
struct PaneContextSessionsBridgeTests {
    private static let replacementWorkKinds: [AgentStudioCore.AgentLineWork?] = [
        .working(.indeterminate), .working(.step(current: 1, total: 2)), .blockedOnYou(action: "Choose a response"),
        .done, .failed(summary: "A line failure"), nil,
    ]

    @Test(
        "a real committed ask summary changes Sessions with its declared reason",
        arguments: [AskReason.approval, .question, .blocked])
    func summaryPushPreservesReason(reason: AskReason) async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let request = fixture.ask(writer: try fixture.sender(binding), reason: reason)
            #expect(await fixture.service.send(request) == .created(request.messageId))
            #expect(
                try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .needsYou(reason))
        }
    }

    @Test("a delayed older real summary cannot restore attention after dismiss")
    func staleSummaryIsIgnored() async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let request = fixture.ask(writer: try fixture.sender(binding), reason: .question)
            #expect(await fixture.service.send(request) == .created(request.messageId))
            let older = try #require(await fixture.service.openAskSummaries().first)
            #expect(older.question == 1)
            #expect(
                try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .needsYou(.question))
            #expect(await fixture.service.dismiss(messageId: request.messageId, paneId: fixture.paneId) == .done)
            let latest = try #require(await fixture.service.openAskSummaries().first)
            #expect(latest.sequence > older.sequence)
            #expect(latest.question == 0)
            #expect(try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .unknown)
            await fixture.bridge.receiveOpenAskSummary(older)
            #expect(try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .unknown)
        }
    }

    @Test("lazy Sessions open reads the service's persisted ask summary")
    func lazyOpenLoadsRealSummary() async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let request = fixture.ask(writer: try fixture.sender(binding), reason: .approval)
            #expect(await fixture.service.send(request) == .created(request.messageId))
            await fixture.ingestion.finish()
            let reopened = fixture.makeIngestion()
            fixture.bridge.connect(service: fixture.service, ingestion: reopened)
            do {
                #expect(try await reopened.sessionSummary(paneId: fixture.paneId.uuid)?.status == .needsYou(.approval))
                await reopened.finish()
            } catch {
                await reopened.finish()
                throw error
            }
        }
    }

    @Test("a monitoring line refines working, and the Sessions end callback marks that line stale")
    func lineAndSessionEndReachTheirOwners() async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let writer = try fixture.sender(binding)
            _ = try await fixture.ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    .init(
                        admittedContext: try fixture.activityContext(binding), occurrenceId: UUIDv7.generate(),
                        turnId: "turn", subject: .root, kind: .activityStarted, occurredAt: fixture.time.now,
                        sourceCursor: nil)))
            let epoch = try await fixture.epoch(writer: writer, stream: .line)
            #expect(
                await fixture.service.setLine(
                    .init(
                        paneId: fixture.paneId, writer: writer,
                        line: .init(
                            summary: "Watching checks", work: .monitoring("checks"), detail: nil, refs: [],
                            lifetime: .untilReplaced), writeNumber: .init(epoch: epoch, counter: 1))) == .applied)
            #expect(
                try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .working(.monitoring)
            )
            #expect(try await fixture.detail().agentLine?.stale == false)
            _ = try await fixture.ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .sourceEnded(
                    .init(
                        paneId: fixture.paneId.uuid, sourceGenerationId: binding.sourceGenerationId,
                        endedAt: fixture.time.now)))
            #expect(try await fixture.detail().agentLine?.stale == true)
            #expect(try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .idle(.ended))
        }
    }

    @Test(
        "non-monitoring and cleared lines remove the monitoring refinement without replacing the Sessions turn",
        arguments: replacementWorkKinds)
    func replacementLineClearsMonitoring(work: AgentStudioCore.AgentLineWork?) async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let writer = try fixture.sender(binding)
            _ = try await fixture.ingestion.submit(
                correlationId: UUIDv7.generate(),
                mutation: .recordEvidence(
                    .init(
                        admittedContext: try fixture.activityContext(binding), occurrenceId: UUIDv7.generate(),
                        turnId: "turn", subject: .root, kind: .activityStarted, occurredAt: fixture.time.now,
                        sourceCursor: nil)))
            let epoch = try await fixture.epoch(writer: writer, stream: .line)
            #expect(
                await fixture.service.setLine(
                    .init(
                        paneId: fixture.paneId, writer: writer,
                        line: .init(
                            summary: "Watching checks", work: .monitoring("checks"), detail: nil, refs: [],
                            lifetime: .untilReplaced), writeNumber: .init(epoch: epoch, counter: 1))) == .applied)
            #expect(
                try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .working(.monitoring)
            )
            let replacementLine: AgentLineInput? = work.map {
                .init(summary: "Current work", work: $0, detail: nil, refs: [], lifetime: .untilReplaced)
            }
            #expect(
                await fixture.service.setLine(
                    .init(
                        paneId: fixture.paneId, writer: writer, line: replacementLine,
                        writeNumber: .init(epoch: epoch, counter: 2))) == .applied)
            #expect(
                try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid)?.status == .working(.active))
            #expect(try await fixture.detail().agentLine?.work == work)
        }
    }

    @Test("readDetail receives the current binding summary from real Sessions")
    func detailUsesSessionsSummary() async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let expected = try #require(try await fixture.ingestion.sessionSummary(paneId: fixture.paneId.uuid))
            #expect(expected.bindingGeneration == binding.bindingGenerationId)
            #expect(try await fixture.detail().session == expected)
        }
    }

    @Test("a replacement during a held service write is refused by the real Sessions transaction read")
    func writerRecheckUsesSessionsRepository() async throws {
        try await withPaneContextSessionsBridge { fixture in
            let binding = try await fixture.bindConversation("first")
            let writer = try fixture.sender(binding)
            #expect(
                try await fixture.sqliteAccess.read {
                    try PaneContextSessionsBridge.currentBindingGeneration(paneId: fixture.paneId, in: $0)
                } == binding.bindingGenerationId)
            let epoch = try await fixture.epoch(writer: writer, stream: .title)
            let held = HeldStep<Void>("bridge committing old writer", cancellation: .holdThroughCancellation)
            await fixture.sqliteAccess.holdNextWrite(held)
            let pending = Task {
                await fixture.service.setTitle(
                    .init(
                        paneId: fixture.paneId, writer: writer, text: "Old writer title",
                        writeNumber: .init(epoch: epoch, counter: 1)))
            }
            do {
                try await held.firstArrival()
                let replacement = try await fixture.bindConversation("second")
                #expect(replacement.bindingGenerationId != binding.bindingGenerationId)
                held.release()
                #expect(await pending.value == .stale(.writerReplaced))
                #expect(try await fixture.detail().agentTitle == nil)
                #expect(
                    try await fixture.sqliteAccess.read {
                        try PaneContextSessionsBridge.currentBindingGeneration(paneId: fixture.paneId, in: $0)
                    } == replacement.bindingGenerationId)
            } catch {
                held.retire()
                _ = await pending.value
                throw error
            }
        }
    }
}
