import AgentStudioTestHarness
import Darwin
import Foundation
import Testing

@Suite("Harness receipt metadata")
struct HarnessReceiptTests {
    @Test("a cancelled first-arrival wait has a terminal receipt")
    func cancelledFirstArrivalRecordsSettlement() async throws {
        let logURL = try makeReceiptLogURL()
        defer { try? FileManager.default.removeItem(at: logURL) }
        let step = HeldStep<Int>("cancelled receipt", eventLog: HeldStepEventLog(path: logURL.path))
        let waiting = Task { try await step.firstArrival() }
        waiting.cancel()
        await #expect(throws: HeldStepNeverReached.self) { try await waiting.value }

        let records = try readReceiptRecords(logURL)
        let pending = try #require(records.first { $0.fields.first == "waiting" })
        let settled = try #require(records.first { $0.fields.first == "wait_settled" })
        #expect(settled.fields[1] == String(step.instanceID))
        #expect(settled.fields[3] == "cancelled")
        #expect(settled.fields[2] == String(try #require(pending.metadata?.waiterID)))
    }

    @Test("both loggers carry the monotonic clock and current framework identity")
    func recordsCarryClockAndFrameworkIdentity() async throws {
        let logURL = try makeReceiptLogURL()
        defer { try? FileManager.default.removeItem(at: logURL) }
        let step = HeldStep<Int>("metadata receipt", eventLog: HeldStepEventLog(path: logURL.path))
        let waiting = Task { try await step.firstArrival() }
        waiting.cancel()
        await #expect(throws: HeldStepNeverReached.self) { try await waiting.value }
        step.release()
        try await step.arrive(1)
        let log = ExpectationLog(path: logURL.path)
        let identifier = log.expecting(expectedCase: "closed", scope: "scope", test: "site", callSite: "site")
        log.settled(identifier, outcome: .matched)

        let records = try readReceiptRecords(logURL)
        #expect(
            Set(records.compactMap { $0.fields.first }) == [
                "waiting", "wait_settled", "arrived", "expecting", "settled",
            ])
        let expectedTestID = String(describing: try #require(Test.current).id)
        for record in records {
            let metadata = try #require(record.metadata)
            #expect(metadata.clockDomain == "CLOCK_UPTIME_RAW")
            #expect(try #require(metadata.seconds) >= 0)
            #expect((0..<1_000_000_000).contains(try #require(metadata.nanoseconds)))
            #expect(metadata.testID == expectedTestID)
            #expect(try #require(metadata.caseID).isEmpty == false)
        }
    }
}

@Suite("Harness parameterized receipt identity", ParameterizedReceiptScope())
struct HarnessParameterizedReceiptTests {
    @Test("equal arguments still have distinct framework case identities", arguments: ["same", "same"])
    func recordsFromParameterizedCases(label: String) throws {
        let logURL = try #require(ParameterizedReceiptContext.logURL)
        let log = ExpectationLog(path: logURL.path)
        let identifier = log.expecting(expectedCase: "closed", scope: label, test: "same site", callSite: "same site")
        log.settled(identifier, outcome: .matched)
    }
}

private struct ParameterizedReceiptScope: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    func provideScope(
        for _: Test, testCase _: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        let logURL = try makeReceiptLogURL()
        defer { try? FileManager.default.removeItem(at: logURL) }
        try await ParameterizedReceiptContext.$logURL.withValue(logURL) {
            try await function()
        }
        let pending = try readReceiptRecords(logURL).filter { $0.fields.first == "expecting" }
        #expect(pending.count == 2)
        #expect(Set(pending.map { $0.fields[3] }).count == 1)
        let identities = try pending.map { try #require($0.metadata?.caseID) }
        #expect(Set(identities).count == 2)
        #expect(Set(pending.compactMap { $0.metadata?.testID }).count == 1)
    }
}

private enum ParameterizedReceiptContext {
    @TaskLocal static var logURL: URL?
}

private struct ReceiptMetadata: Decodable {
    let clockDomain: String
    let seconds: Int64?
    let nanoseconds: Int?
    let testID: String?
    let caseID: String?
    let waiterID: UInt64?
}

private struct ReceiptRecord {
    let fields: [String]
    let metadata: ReceiptMetadata?
}

private func readReceiptRecords(_ logURL: URL) throws -> [ReceiptRecord] {
    try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n").map { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        return ReceiptRecord(
            fields: fields,
            metadata: fields.last.flatMap {
                try? JSONDecoder().decode(ReceiptMetadata.self, from: Data($0.utf8))
            })
    }
}

private func makeReceiptLogURL() throws -> URL {
    var template = Array((NSTemporaryDirectory() + "f2-harness-receipt-XXXXXX").utf8CString)
    let descriptor = mkstemp(&template)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    close(descriptor)
    let pathBytes = template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    guard let logPath = String(bytes: pathBytes, encoding: .utf8) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return URL(fileURLWithPath: logPath)
}
