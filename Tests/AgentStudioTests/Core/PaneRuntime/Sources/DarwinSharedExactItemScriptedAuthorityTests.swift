import AgentStudioGit
import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

extension DarwinSharedExactItemObserverTests {
    @Test(
        "scripted exact-item replacements invalidate composite authority",
        arguments: SharedExactItemReplacementMutation.allCases
    )
    func scriptedReplacementInvalidatesAuthority(
        mutation: SharedExactItemReplacementMutation
    ) async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-shared-scripted-replacement-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let worktreeRoot = fixtureRoot.appending(path: "worktree", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        let exactItem = externalParent.appending(path: "global-excludes")
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try "ignored.txt\n".write(to: exactItem, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let streamFactory = RecordingSharedExactItemStreamFactory()
        let client = DarwinFSEventStreamClient(
            localStreamFactory: { _ in NoopLocalFSEventStreamLifetime() },
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        defer { client.shutdown() }
        let worktreeId = UUIDv7.generate()
        _ = client.register(worktreeId: worktreeId, repoId: UUIDv7.generate(), rootPath: worktreeRoot)
        let observationPlan = makeSharedAuthorityObservationPlan(
            worktreeRoot: worktreeRoot,
            exactItem: exactItem
        )
        let barrier = try #require(
            await client.prepare(
                worktreeId: worktreeId,
                rootPath: worktreeRoot,
                observationPlan: observationPlan
            )
        )
        let authority = try #require((await client.commit(barrier)).scriptedAuthority)
        #expect(await client.renew(authority) == .authoritative(authority))

        try performScriptedReplacement(mutation, at: exactItem)
        try #require(
            streamFactory.emit(
                path: DarwinFSEventPathCanonicalizer.canonicalURL(exactItem).path,
                eventId: 101,
                flags: scriptedReplacementFlags(mutation)
            ),
            "fake shared stream did not retain its callback"
        )

        let renewal = await client.renew(authority)
        #expect(renewal == .requiresExact(.mutationObserved))
    }

    @Test("scripted exact-item callback between prepare and commit fails closed")
    func scriptedCallbackBetweenPrepareAndCommitFailsClosed() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-shared-scripted-commit-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let worktreeRoot = fixtureRoot.appending(path: "worktree", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        let exactItem = externalParent.appending(path: "global-excludes")
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try "ignored.txt\n".write(to: exactItem, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let streamFactory = RecordingSharedExactItemStreamFactory()
        let client = DarwinFSEventStreamClient(
            localStreamFactory: { _ in NoopLocalFSEventStreamLifetime() },
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        defer { client.shutdown() }
        let worktreeId = UUIDv7.generate()
        _ = client.register(worktreeId: worktreeId, repoId: UUIDv7.generate(), rootPath: worktreeRoot)
        let barrier = try #require(
            await client.prepare(
                worktreeId: worktreeId,
                rootPath: worktreeRoot,
                observationPlan: makeSharedAuthorityObservationPlan(
                    worktreeRoot: worktreeRoot,
                    exactItem: exactItem
                )
            )
        )

        // The direct prepare/commit seam supplies the ordering. No scheduler hold is needed.
        try #require(
            streamFactory.emit(
                path: DarwinFSEventPathCanonicalizer.canonicalURL(exactItem).path,
                eventId: 102
            )
        )
        let validation = await client.commit(barrier)
        #expect(validation == .requiresExact(.mutationObserved))
    }

    @Test("shared sibling preserves two authorities and exact hit invalidates both")
    func scriptedSharedFanoutPreservesSiblingAndInvalidatesExactHit() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-shared-scripted-fanout-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        let exactItem = externalParent.appending(path: "global-excludes")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try "ignored.txt\n".write(to: exactItem, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let streamFactory = RecordingSharedExactItemStreamFactory()
        let client = DarwinFSEventStreamClient(
            localStreamFactory: { _ in NoopLocalFSEventStreamLifetime() },
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        defer { client.shutdown() }
        let registrations = [
            (worktreeId: UUIDv7.generate(), root: firstRoot),
            (worktreeId: UUIDv7.generate(), root: secondRoot),
        ]
        for registration in registrations {
            _ = client.register(
                worktreeId: registration.worktreeId,
                repoId: UUIDv7.generate(),
                rootPath: registration.root
            )
        }
        var authorities: [UUID: GitCleanContinuityAuthority] = [:]
        for registration in registrations {
            let barrier = try #require(
                await client.prepare(
                    worktreeId: registration.worktreeId,
                    rootPath: registration.root,
                    observationPlan: makeSharedAuthorityObservationPlan(
                        worktreeRoot: registration.root,
                        exactItem: exactItem
                    )
                )
            )
            let authority = try #require(
                (await client.commit(barrier)).scriptedAuthority
            )
            authorities[registration.worktreeId] = authority
        }
        #expect(streamFactory.startCount == 1)

        let siblingPath = externalParent.appending(path: "unrelated")
        try #require(
            streamFactory.emit(
                path: DarwinFSEventPathCanonicalizer.canonicalURL(siblingPath).path,
                eventId: 210
            )
        )
        for registration in registrations {
            let authority = try #require(authorities[registration.worktreeId])
            #expect(await client.renew(authority) == .authoritative(authority))
        }

        try #require(
            streamFactory.emit(
                path: DarwinFSEventPathCanonicalizer.canonicalURL(exactItem).path,
                eventId: 211,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
            )
        )
        for registration in registrations {
            let authority = try #require(authorities[registration.worktreeId])
            #expect(await client.renew(authority) == .requiresExact(.mutationObserved))
        }
    }

    @Test("RootChanged invalidates both authorities; rebind renews new generations without status reads")
    func scriptedRootChangedAndRebindReplaceAuthorityGenerations() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-shared-scripted-rebind-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        let exactItem = externalParent.appending(path: "global-excludes")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try "ignored.txt\n".write(to: exactItem, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let streamFactory = RecordingSharedExactItemStreamFactory()
        let client = DarwinFSEventStreamClient(
            localStreamFactory: { _ in NoopLocalFSEventStreamLifetime() },
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        defer { client.shutdown() }
        let registrations = [
            (worktreeId: UUIDv7.generate(), root: firstRoot),
            (worktreeId: UUIDv7.generate(), root: secondRoot),
        ]
        var originalAuthorities: [UUID: GitCleanContinuityAuthority] = [:]
        for registration in registrations {
            _ = client.register(
                worktreeId: registration.worktreeId,
                repoId: UUIDv7.generate(),
                rootPath: registration.root
            )
            let barrier = try #require(
                await client.prepare(
                    worktreeId: registration.worktreeId,
                    rootPath: registration.root,
                    observationPlan: makeSharedAuthorityObservationPlan(
                        worktreeRoot: registration.root,
                        exactItem: exactItem
                    )
                )
            )
            let authority = try #require(
                (await client.commit(barrier)).scriptedAuthority
            )
            originalAuthorities[registration.worktreeId] = authority
        }

        try #require(
            streamFactory.emit(
                path: DarwinFSEventPathCanonicalizer.canonicalURL(externalParent).path,
                eventId: 300,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
            )
        )
        for registration in registrations {
            let originalAuthority = try #require(originalAuthorities[registration.worktreeId])
            guard case .requiresExact = await client.renew(originalAuthority) else {
                Issue.record("RootChanged must invalidate each dependent authority")
                continue
            }
        }

        let readRecorder = GitPhysicalReadRecorder()
        let provider = AgentStudioGitWorkingTreeStatusProvider(
            physicalGate: AgentStudioGitStatusPhysicalGate(),
            continuityWitness: client,
            statusReader: { _, _ in
                readRecorder.recordCompleteStatusRead()
                throw ScriptedStatusReadError()
            }
        )

        for registration in registrations {
            client.unregister(worktreeId: registration.worktreeId)
            _ = client.register(
                worktreeId: registration.worktreeId,
                repoId: UUIDv7.generate(),
                rootPath: registration.root
            )
            let barrier = try #require(
                await client.prepare(
                    worktreeId: registration.worktreeId,
                    rootPath: registration.root,
                    observationPlan: makeSharedAuthorityObservationPlan(
                        worktreeRoot: registration.root,
                        exactItem: exactItem
                    )
                )
            )
            let replacementAuthority = try #require(
                (await client.commit(barrier)).scriptedAuthority
            )
            let originalAuthority = try #require(originalAuthorities[registration.worktreeId])
            #expect(replacementAuthority.registrationGeneration != originalAuthority.registrationGeneration)
            #expect(await client.renew(originalAuthority) == .requiresExact(.registrationReplaced))
            #expect(await client.renew(replacementAuthority) == .authoritative(replacementAuthority))
            #expect(
                await provider.renewExactCleanAuthority(replacementAuthority)
                    == .renewed(replacementAuthority)
            )
        }
        #expect(readRecorder.snapshot.completeStatusReadCount == 0)
    }

    @Test("pre-armed native callback match survives a burst beyond the diagnostic ring")
    func nativeCallbackMatchSurvivesBurst() async throws {
        let recorder = NativeSharedExactItemStreamRecorder(nativeSharedStreamIsEnabled: false)
        let expectedPath = "/private/tmp/unique-shared-callback"
        let matchingEvents = recorder.armCallbackEvent(at: expectedPath)
        recorder.recordCallbackEvents([
            DarwinSharedExactItemRawEvent(path: expectedPath, eventId: 401, flags: 0)
        ])
        for eventID in FSEventStreamEventId(402)...FSEventStreamEventId(442) {
            recorder.recordCallbackEvents([
                DarwinSharedExactItemRawEvent(
                    path: "/private/tmp/unrelated-\(eventID)",
                    eventId: eventID,
                    flags: 0
                )
            ])
        }

        let matchedEventID = try #require(await recorder.awaitCallbackEvent(matchingEvents))
        #expect(matchedEventID == 401)
    }

    private func makeSharedAuthorityObservationPlan(
        worktreeRoot: URL,
        exactItem: URL
    ) -> AgentStudioGit.GitStatusObservationPlan {
        AgentStudioGit.GitStatusObservationPlan(
            identity: AgentStudioGit.GitStatusObservationIdentity(rawValue: "scripted-shared-dependent"),
            scopes: [
                AgentStudioGit.GitStatusObservationScope(kind: .subtree, path: worktreeRoot),
                AgentStudioGit.GitStatusObservationScope(kind: .item, path: exactItem),
            ],
            support: .supported
        )
    }

    private func performScriptedReplacement(
        _ mutation: SharedExactItemReplacementMutation,
        at exactItem: URL
    ) throws {
        switch mutation {
        case .delete:
            try FileManager.default.removeItem(at: exactItem)
        case .rename:
            try FileManager.default.moveItem(
                at: exactItem,
                to: exactItem.deletingLastPathComponent().appending(path: "renamed-excludes")
            )
        case .atomicReplacement:
            try "another-ignored.txt\n".write(to: exactItem, atomically: true, encoding: .utf8)
        }
    }

    private func scriptedReplacementFlags(
        _ mutation: SharedExactItemReplacementMutation
    ) -> FSEventStreamEventFlags {
        switch mutation {
        case .delete: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)
        case .rename: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)
        case .atomicReplacement: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        }
    }

}

extension GitCleanContinuityAuthorityValidation {
    fileprivate var scriptedAuthority: GitCleanContinuityAuthority? {
        guard case .authoritative(let authority) = self else { return nil }
        return authority
    }
}

private struct ScriptedStatusReadError: Error {}
