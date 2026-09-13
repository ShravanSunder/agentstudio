import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("Watched folder topology admission")
struct WatchedFolderTopologyAdmissionTests {
    enum Scenario: CaseIterable, Sendable {
        case knownCheckout, ancestor, newDirectory, insideCheckout, metadataOnly, outsideRoot, ordinaryFile, gitMarker

        var shouldScan: Bool {
            switch self {
            case .knownCheckout, .ancestor, .newDirectory, .gitMarker: true
            case .insideCheckout, .metadataOnly, .outsideRoot, .ordinaryFile: false
            }
        }
    }

    @Test(
        "directory admission respects scan boundaries without scanning ordinary checkout changes",
        arguments: Scenario.allCases)
    func directoryAdmissionRespectsKnownCheckoutBoundary(_ scenario: Scenario) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "topology-admission-\(UUIDv7.generate())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registration = FSEventRegistrationToken(
            sourceID: .init(kind: .watchedParentMembership, rootID: UUIDv7.generate()),
            registrationGeneration: 1, rootGeneration: 1)
        let descriptor = try FilesystemSourceConfiguration.registerRoot(
            from: .hostAuthorized(
                .init(registration: registration, authorizedBoundary: root, registeredRoot: root)))
        let known = root.appending(path: "container/known")
        let changedDirectory = UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed)
        let event: (URL, UInt32) =
            switch scenario {
            case .knownCheckout: (known, changedDirectory)
            case .ancestor: (root.appending(path: "container"), changedDirectory)
            case .newDirectory: (root.appending(path: "new"), changedDirectory)
            case .insideCheckout: (known.appending(path: "Sources/Renamed"), changedDirectory)
            case .metadataOnly: (known, UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemModified))
            case .outsideRoot: (root.deletingLastPathComponent().appending(path: "outside"), changedDirectory)
            case .ordinaryFile: (root.appending(path: "notes.txt"), UInt32(kFSEventStreamEventFlagItemCreated))
            case .gitMarker: (known.appending(path: ".git/HEAD"), UInt32(kFSEventStreamEventFlagItemModified))
            }
        let batch = FSEventBatch(
            worktreeId: UUIDv7.generate(), paths: [event.0.path],
            observations: [.init(path: event.0.path, eventID: 1, flags: event.1)])

        #expect(
            WatchedFolderTopologyAdmission.shouldScan(
                batch, root: descriptor, knownGroups: [.init(clonePath: known, linkedWorktreePaths: [])])
                == scenario.shouldScan)
    }

    @Test("directory topology evidence survives ingress overflow with retained or discarded paths", arguments: [1, 4])
    func directoryEvidenceSurvivesOverflow(pathLimit: Int) {
        let buffer = DarwinFSEventIngressBuffer(capacity: 1, maximumRetainedOverflowPathsPerRegistration: pathLimit)
        let sourceID = UUIDv7.generate()
        buffer.yield(.init(worktreeId: sourceID, paths: ["/watched/ordinary.txt"]))
        buffer.yield(
            .init(
                worktreeId: sourceID, paths: ["/watched/old", "/watched/new"],
                observations: [
                    .init(
                        path: "/watched/old", eventID: 2,
                        flags: UInt32(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed))
                ]))
        buffer.finish()

        let recoveries = buffer.consumeOverflowRecoveries()
        #expect(recoveries.count == 1)
        #expect(recoveries.first?.requiresWatchedFolderScan == true)
        #expect((recoveries.first?.paths == nil) == (pathLimit == 1))
        #expect(buffer.consumeOverflowRecoveries().isEmpty)
    }
}
