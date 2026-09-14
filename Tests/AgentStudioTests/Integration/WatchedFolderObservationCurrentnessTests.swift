import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@Suite("Watched folder observation currentness")
struct WatchedFolderObservationCurrentnessTests {
    @Test("only overlapping source supersession invalidates a dependent observation", arguments: [true, false])
    func otherSourceSupersessionRequiresOverlappingCoverage(overlaps: Bool) async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            path: "watched-observation-currentness-\(UUIDv7.generate())")
        let firstRoot = temporaryRoot.appending(path: "first")
        let secondRoot = overlaps ? firstRoot.appending(path: "nested") : temporaryRoot.appending(path: "second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let firstWatch = WatchedPath(path: firstRoot)
        let secondWatch = WatchedPath(path: secondRoot)
        let scans = ControllableWatchedFolderScanSchedulerResults()
        scans.setResults([firstWatch: [], secondWatch: []])
        let filesystem = FilesystemActor(
            bus: EventBus<RuntimeEnvelope>(), fseventStreamClient: ControllableFSEventStreamClient(),
            watchedFolderScanScheduler: scans.makeScheduler())
        do {
            _ = await filesystem.refreshWatchedFolders([firstWatch, secondWatch])
            let receipts = await filesystem.currentWatchedFolderObservationReceipts()
            #expect(receipts.count == 2)
            // The last result captured the other source after its initial authoritative result.
            let retained = try #require(receipts.max { $0.sequence < $1.sequence })
            let other = try #require(receipts.first { $0.sequence != retained.sequence })
            let registrations = await filesystem.watchedFolderScanState.registrationsBySourceID
            let registration = try #require(registrations[other.observation.registration.sourceID])

            await filesystem.handleWatchedFolderFSEvent(
                FSEventBatch(
                    worktreeId: registration.legacyCallbackRoutingID,
                    paths: [registration.watchedPath.path.appending(path: ".git/index").path]))

            let remainsCurrent = await filesystem.areCurrentWatchedFolderObservations([retained.observation])
            #expect(remainsCurrent == !overlaps)
        } catch {
            await filesystem.shutdown()
            throw error
        }
        await filesystem.shutdown()
    }
}
