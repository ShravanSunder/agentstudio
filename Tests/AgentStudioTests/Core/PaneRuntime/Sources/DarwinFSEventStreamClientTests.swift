import AgentStudioGit
import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinFSEventStreamClient")
struct DarwinFSEventStreamClientTests {
    @Test("event classification retains an in-root symlink object whose target is outside the root")
    func eventClassificationRetainsInRootSymlinkObject() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevent-classifier-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let rootPath = fixtureRoot.appending(path: "repo", directoryHint: .isDirectory)
        let outsideTargetPath = fixtureRoot.appending(path: "outside-target")
        let symlinkPath = rootPath.appending(path: "README.md")
        try FileManager.default.createDirectory(at: rootPath, withIntermediateDirectories: true)
        try Data().write(to: outsideTargetPath)
        try FileManager.default.createSymbolicLink(
            at: symlinkPath,
            withDestinationURL: outsideTargetPath
        )

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: [(path: symlinkPath.path, eventId: 40, flags: 0)],
            ordinaryPaths: [symlinkPath.path],
            rootPath: rootPath.path,
            observationScopes: [
                AgentStudioGit.GitStatusObservationScope(kind: .subtree, path: rootPath)
            ]
        )

        #expect(classification.rawEvents.map(\.hasRelevantMutation) == [true])
        #expect(classification.ordinaryPaths == [symlinkPath.path])
    }

    @Test("event classification normalizes lexical callback path spellings")
    func eventClassificationNormalizesLexicalCallbackPathSpellings() {
        let rootPath = "/tmp/repo"
        let canonicalChangedPath = "/tmp/repo/Sources/Changed.swift"
        let callbackPathSpellings = [
            "/tmp//repo/Sources/Changed.swift",
            "/tmp/repo/./Sources/Changed.swift",
            "/tmp/repo/Generated/../Sources/Changed.swift",
        ]

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: callbackPathSpellings.enumerated().map { index, path in
                (path: path, eventId: FSEventStreamEventId(index + 41), flags: 0)
            },
            ordinaryPaths: callbackPathSpellings,
            rootPath: rootPath,
            observationScopes: [
                AgentStudioGit.GitStatusObservationScope(
                    kind: .item,
                    path: URL(fileURLWithPath: canonicalChangedPath)
                )
            ]
        )

        #expect(classification.rawEvents.map(\.hasRelevantMutation) == [true, true, true])
        #expect(classification.ordinaryPaths == callbackPathSpellings)
    }

    @Test("event classification excludes sibling prefixes and the loss sentinel")
    func eventClassificationExcludesSiblingPrefixesAndLossSentinel() {
        let rootPath = "/tmp/repo"
        let siblingPrefixPath = "/tmp/repository/Sources/Changed.swift"

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: [
                (path: siblingPrefixPath, eventId: 41, flags: 0),
                (path: "/", eventId: 42, flags: 0),
            ],
            ordinaryPaths: [siblingPrefixPath, "/"],
            rootPath: rootPath,
            observationScopes: [
                AgentStudioGit.GitStatusObservationScope(
                    kind: .subtree,
                    path: URL(fileURLWithPath: rootPath)
                )
            ]
        )

        #expect(classification.rawEvents.map(\.hasRelevantMutation) == [false, false])
        #expect(classification.ordinaryPaths.isEmpty)
    }

    @Test("event classification normalizes each unique callback path once")
    func eventClassificationNormalizesEachUniqueCallbackPathOnce() {
        let rootPath = "/tmp/repo"
        let changedPath = "/tmp/repo/Sources/Changed.swift"
        let ignoredPath = "/tmp/outside/Other.swift"
        var normalizationCountByPath: [String: Int] = [:]

        let classification = DarwinFSEventPathClassifier.classify(
            rawEvents: [
                (path: changedPath, eventId: 41, flags: 0),
                (path: ignoredPath, eventId: 42, flags: 0),
            ],
            ordinaryPaths: [changedPath, ignoredPath],
            rootPath: rootPath,
            observationScopes: [
                AgentStudioGit.GitStatusObservationScope(
                    kind: .subtree,
                    path: URL(fileURLWithPath: rootPath)
                )
            ],
            normalize: { path in
                normalizationCountByPath[path, default: 0] += 1
                return path
            }
        )

        #expect(normalizationCountByPath == [changedPath: 1, ignoredPath: 1])
        #expect(classification.rawEvents.map(\.hasRelevantMutation) == [true, false])
        #expect(classification.ordinaryPaths == [changedPath])
    }

    @Test("continuity ledger rejects a baseline when mutation crosses its barrier")
    func continuityLedgerRejectsMutationAcrossBaselineBarrier() throws {
        let ledger = GitCleanContinuityLedger()
        let registrationId = UUIDv7.generate()
        let identity = AgentStudioGit.GitStatusObservationIdentity(rawValue: "identity-a")

        ledger.register(registrationId: registrationId, identity: identity)
        let preparation = try #require(ledger.beginBarrier(registrationId: registrationId, identity: identity))
        ledger.recordMutation(registrationId: registrationId, eventId: 41)

        #expect(ledger.commitBarrier(preparation) == .requiresExact(.mutationObserved))
    }

    @Test("continuity ledger rejects loss and discontinuity flags fail closed")
    func continuityLedgerRejectsLossFlags() throws {
        let lossFlags: [FSEventStreamEventFlags] = [
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped),
            FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
            FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
        ]

        for flags in lossFlags {
            let ledger = GitCleanContinuityLedger()
            let registrationId = UUIDv7.generate()
            let identity = AgentStudioGit.GitStatusObservationIdentity(rawValue: "identity-\(flags)")
            ledger.register(registrationId: registrationId, identity: identity)
            let preparation = try #require(
                ledger.beginBarrier(registrationId: registrationId, identity: identity)
            )

            ledger.recordRawEvent(
                registrationId: registrationId,
                eventId: 42,
                flags: flags,
                hasRelevantMutation: false
            )

            #expect(ledger.commitBarrier(preparation) == .requiresExact(.eventStreamUncertain))
        }
    }

    @Test("continuity ledger renews only the same registration identity and epochs")
    func continuityLedgerRenewsStableAuthority() throws {
        let ledger = GitCleanContinuityLedger()
        let registrationId = UUIDv7.generate()
        let identity = AgentStudioGit.GitStatusObservationIdentity(rawValue: "identity-a")
        ledger.register(registrationId: registrationId, identity: identity)
        let preparation = try #require(ledger.beginBarrier(registrationId: registrationId, identity: identity))
        guard case .authoritative(let authority) = ledger.commitBarrier(preparation) else {
            Issue.record("stable barrier did not mint authority")
            return
        }

        let renewed = ledger.renew(authority)

        #expect(renewed == .authoritative(authority))
        ledger.register(
            registrationId: registrationId,
            identity: AgentStudioGit.GitStatusObservationIdentity(rawValue: "identity-b")
        )
        #expect(ledger.renew(authority) == .requiresExact(.identityChanged))
    }

    @Test("filesystem ingress does not retain more fine batches than its configured capacity")
    func ingressRetainsAtMostConfiguredFineBatchCapacity() async throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 2)
        let worktreeId = UUID()
        ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: ["first"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: ["second"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: worktreeId, paths: ["third"]))
        ingressBuffer.finish()

        var retainedBatches: [FSEventBatch] = []
        for await batch in ingressBuffer.events() {
            retainedBatches.append(batch)
        }

        #expect(retainedBatches.count <= 2)
        #expect(ingressBuffer.consumeOverflowRecoveries().map(\.worktreeId) == [worktreeId])
    }

    @Test("overflow debt coalesces per affected worktree and stays isolated")
    func overflowDebtCoalescesPerAffectedWorktree() {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 1)
        let retainedWorktreeId = UUID()
        let overflowedWorktreeId = UUID()
        let otherOverflowedWorktreeId = UUID()

        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["first"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["second"]))
        ingressBuffer.yield(FSEventBatch(worktreeId: otherOverflowedWorktreeId, paths: ["other"]))

        let recoveries = ingressBuffer.consumeOverflowRecoveries()
        #expect(Set(recoveries.map(\.worktreeId)) == [overflowedWorktreeId, otherOverflowedWorktreeId])
        #expect(recoveries.first { $0.worktreeId == overflowedWorktreeId }?.paths == ["first", "second"])
        #expect(recoveries.first { $0.worktreeId == otherOverflowedWorktreeId }?.paths == ["other"])
        #expect(ingressBuffer.consumeOverflowRecoveries().isEmpty)
        ingressBuffer.finish()
    }

    @Test("overflow recovery preserves known path scope")
    func overflowRecoveryPreservesKnownPathScope() throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 1)
        let retainedWorktreeId = UUIDv7.generate()
        let overflowedWorktreeId = UUIDv7.generate()

        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(
            FSEventBatch(
                worktreeId: overflowedWorktreeId,
                paths: ["Sources/First.swift", "Sources/Second.swift"]
            )
        )

        let recovery = try #require(ingressBuffer.consumeOverflowRecoveries().first)
        #expect(recovery.worktreeId == overflowedWorktreeId)
        #expect(recovery.paths == ["Sources/First.swift", "Sources/Second.swift"])
        ingressBuffer.finish()
    }

    @Test("overflow recovery becomes coarse when retained path scope exceeds its bound")
    func overflowRecoveryBecomesCoarseWhenScopeExceedsBound() throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: 1,
            maximumRetainedOverflowPathsPerRegistration: 2
        )
        let retainedWorktreeId = UUIDv7.generate()
        let overflowedWorktreeId = UUIDv7.generate()
        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(
            FSEventBatch(
                worktreeId: overflowedWorktreeId,
                paths: ["one", "two", "three"]
            )
        )
        ingressBuffer.yield(FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["later"]))

        let recovery = try #require(ingressBuffer.consumeOverflowRecoveries().first)
        #expect(recovery.worktreeId == overflowedWorktreeId)
        #expect(recovery.paths == nil)
        #expect(recovery.containsGitTopologyPath == false)
        ingressBuffer.finish()
    }

    @Test("coarse overflow recovery retains git topology classification")
    func coarseOverflowRecoveryRetainsGitTopologyClassification() throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: 1,
            maximumRetainedOverflowPathsPerRegistration: 2
        )
        let retainedWorktreeId = UUIDv7.generate()
        let overflowedWorktreeId = UUIDv7.generate()
        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(
            FSEventBatch(
                worktreeId: overflowedWorktreeId,
                paths: ["one", "two", "three", "repo/.git/HEAD"]
            )
        )

        let recovery = try #require(ingressBuffer.consumeOverflowRecoveries().first)
        #expect(recovery.paths == nil)
        #expect(recovery.containsGitTopologyPath)
        ingressBuffer.finish()
    }

    @Test("already-coarse overflow recovery upgrades when a later batch contains git topology")
    func coarseOverflowRecoveryUpgradesForLaterGitTopologyBatch() throws {
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: 1,
            maximumRetainedOverflowPathsPerRegistration: 2
        )
        let retainedWorktreeId = UUIDv7.generate()
        let overflowedWorktreeId = UUIDv7.generate()
        ingressBuffer.yield(FSEventBatch(worktreeId: retainedWorktreeId, paths: ["retained"]))
        ingressBuffer.yield(
            FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["one", "two", "three"])
        )
        ingressBuffer.yield(
            FSEventBatch(worktreeId: overflowedWorktreeId, paths: ["repo/.git/HEAD"])
        )

        let recovery = try #require(ingressBuffer.consumeOverflowRecoveries().first)
        #expect(recovery.paths == nil)
        #expect(recovery.containsGitTopologyPath)
        ingressBuffer.finish()
    }

    @Test("shutdown terminates ingress without minting new overflow debt")
    func shutdownTerminatesIngressWithoutNewDebt() {
        let ingressBuffer = DarwinFSEventIngressBuffer(capacity: 1)
        ingressBuffer.finish()

        ingressBuffer.yield(FSEventBatch(worktreeId: UUID(), paths: ["post-shutdown"]))

        #expect(ingressBuffer.consumeOverflowRecoveries().isEmpty)
    }

    @Test("conforms to FSEventStreamClient protocol")
    func conformsToProtocol() {
        let client: any FSEventStreamClient = DarwinFSEventStreamClient()
        _ = client.events()
        client.shutdown()
    }

    @Test("register/unregister lifecycle is idempotent")
    func registerUnregisterLifecycleIsIdempotent() async {
        let client = DarwinFSEventStreamClient()
        let worktreeId = UUID()
        let repoId = UUID()
        let rootPath = URL(fileURLWithPath: "/tmp/darwin-fsevents-\(UUID().uuidString)")

        client.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        client.register(worktreeId: worktreeId, repoId: repoId, rootPath: rootPath)
        client.unregister(worktreeId: worktreeId)
        client.unregister(worktreeId: worktreeId)

        client.shutdown()
    }

    @Test("shutdown is idempotent and blocks future registration")
    func shutdownIsIdempotent() async {
        let client = DarwinFSEventStreamClient()
        client.shutdown()
        client.shutdown()

        client.register(
            worktreeId: UUID(),
            repoId: UUID(),
            rootPath: URL(fileURLWithPath: "/tmp/darwin-fsevents-post-shutdown-\(UUID().uuidString)")
        )
        client.unregister(worktreeId: UUID())
    }
}
