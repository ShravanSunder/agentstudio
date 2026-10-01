import AgentStudioPrimitives
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCLIStore

@Suite("CLI store cleanup")
struct CLIStoreCleanupTests {
    @Test("only old handled rows are purged; unread rows survive any age")
    func cleanupKeepsRecentAndUnreadRows() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreCleanupFixture()
            defer { fixture.removeFiles() }
            let writer = try fixture.openWriter()
            let oldHandled = try fixture.append(to: writer)
            fixture.clock.advance(by: .seconds(43_200))
            let recentHandled = try fixture.append(to: writer)
            let unread = try fixture.append(to: writer, createdAt: fixture.originDate)
            fixture.clock.advance(by: .seconds(43_201))

            let removed = try writer.purgeHandledOutbox(
                expectedStoreID: writer.identity.storeID, through: recentHandled.id, now: fixture.now
            ).get()

            #expect(removed == 1)
            #expect(try writer.readOutbox(after: 0).get().entries == [recentHandled, unread])
            #expect(oldHandled.id < recentHandled.id)
            fixture.clock.advance(by: .seconds(30 * 86_400))
            #expect(
                try writer.purgeHandledOutbox(
                    expectedStoreID: writer.identity.storeID, through: recentHandled.id, now: fixture.now
                ).get() == 1)
            #expect(try writer.readOutbox(after: 0).get().entries == [unread])
        }
    }

    @Test("a handled row is kept at one day and removed only once older")
    func cleanupUsesStrictRetentionBoundary() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreCleanupFixture()
            defer { fixture.removeFiles() }
            let writer = try fixture.openWriter()
            let entry = try fixture.append(to: writer)
            fixture.clock.advance(by: .seconds(86_400))
            #expect(
                try writer.purgeHandledOutbox(
                    expectedStoreID: writer.identity.storeID, through: entry.id, now: fixture.now
                ).get() == 0)
            #expect(try writer.readOutbox(after: 0).get().entries == [entry])
            fixture.clock.advance(by: .seconds(1))
            #expect(
                try writer.purgeHandledOutbox(
                    expectedStoreID: writer.identity.storeID, through: entry.id, now: fixture.now
                ).get() == 1)
            #expect(try writer.readOutbox(after: 0).get().entries.isEmpty)
        }
    }

    @Test(
        "foreign or replaced stores with overlapping ids cannot consume another store's mark",
        arguments: [false, true])
    func cleanupRefusesAnotherStoreIdentity(replacedFile: Bool) async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreCleanupFixture()
            defer { fixture.removeFiles() }
            let original = try fixture.openWriter()
            let appRead = try fixture.append(to: original)
            let appStoreID = original.identity.storeID
            try original.databaseQueue.close()
            let writerURL: URL
            if replacedFile {
                try FileManager.default.moveItem(
                    at: fixture.storeURL, to: fixture.rootURL.appending(path: "old.sqlite"))
                writerURL = fixture.storeURL
            } else {
                writerURL = fixture.rootURL.appending(path: "foreign.sqlite")
            }
            let writer = try CLIStore.openWriter(url: writerURL, channel: .debug).get()
            let unread = try fixture.append(to: writer)
            fixture.clock.advance(by: .seconds(2 * 86_400))
            #expect(writer.identity.storeID != appStoreID)
            #expect(unread.id == appRead.id)

            #expect(
                try writer.purgeHandledOutbox(
                    expectedStoreID: appStoreID, through: appRead.id, now: fixture.now
                ).get() == 0)
            #expect(try writer.readOutbox(after: 0).get().entries == [unread])
        }
    }

    @Test("an empty handled prefix never deletes old unread notices")
    func zeroReadThroughKeepsUnreadRows() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreCleanupFixture()
            defer { fixture.removeFiles() }
            let writer = try fixture.openWriter()
            let unread = try fixture.append(to: writer)
            fixture.clock.advance(by: .seconds(60 * 86_400))
            #expect(
                try writer.purgeHandledOutbox(
                    expectedStoreID: writer.identity.storeID, through: 0, now: fixture.now
                ).get() == 0)
            #expect(try writer.readOutbox(after: 0).get().entries == [unread])
        }
    }

    @Test("the app's readonly handle cannot purge even a fully handled old row")
    func readonlyStoreCannotPurge() async throws {
        try await valueFromDedicatedThread {
            let fixture = try CLIStoreCleanupFixture()
            defer { fixture.removeFiles() }
            let writer = try fixture.openWriter()
            let entry = try fixture.append(to: writer)
            let reader = try CLIStore.openReader(url: fixture.storeURL, expectedChannel: .debug).get()
            fixture.clock.advance(by: .seconds(2 * 86_400))
            let result = reader.purgeHandledOutbox(
                expectedStoreID: writer.identity.storeID, through: entry.id, now: fixture.now)
            if case .failure(let failure) = result {
                #expect(failure == .readOnly)
            } else {
                Issue.record("App readonly handle purged CLI-owned rows")
            }
            #expect(try reader.readOutbox(after: 0).get().entries == [entry])
        }
    }
}

private struct CLIStoreCleanupFixture: Sendable {
    let rootURL: URL
    let storeURL: URL
    let clock = TestPushClock()
    let originDate = Date(timeIntervalSince1970: 1_700_000_000)
    let originInstant: TestPushClock.Instant

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: "cli-cleanup-\(UUIDv7.generate())")
        storeURL = rootURL.appending(path: "cli.sqlite")
        originInstant = clock.now
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    var now: Date {
        let elapsed = originInstant.duration(to: clock.now).components
        return originDate.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }

    func openWriter() throws -> CLIStore { try CLIStore.openWriter(url: storeURL, channel: .debug).get() }

    func append(to writer: CLIStore, createdAt: Date? = nil) throws -> CLIOutboxEntry {
        try writer.appendNotice(
            paneID: UUIDv7.generate(), messageID: UUIDv7.generate(), payloadJSON: "{}", createdAt: createdAt ?? now
        ).get()
    }

    func removeFiles() { try? FileManager.default.removeItem(at: rootURL) }
}
