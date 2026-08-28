import AgentStudioGit
import CoreServices
import Foundation

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

final class SharedExactItemRealStreamFixture: @unchecked Sendable {
    let firstWorktreeId = UUIDv7.generate()
    let secondWorktreeId = UUIDv7.generate()
    let firstRepositoryPath: URL
    let secondRepositoryPath: URL
    let externalParentPath: String
    let includedConfigurationPath: URL
    let excludesFilePath: URL
    let unrelatedSiblingPath: URL
    let nativeStreamRecorder: NativeSharedExactItemStreamRecorder
    let readRecorder = GitPhysicalReadRecorder()
    let provider: AgentStudioGitWorkingTreeStatusProvider

    private let fixtureRoot: URL
    private let streamClient: DarwinFSEventStreamClient
    private let exactItemParent: SharedExactItemParent
    private var sentinelWriteSequence = 0

    init(nativeSharedStreamIsEnabled: Bool) throws {
        fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-shared-real-stream-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        firstRepositoryPath = fixtureRoot.appending(path: "first-repository", directoryHint: .isDirectory)
        secondRepositoryPath = fixtureRoot.appending(path: "second-repository", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        exactItemParent = SharedExactItemParent(initialURL: externalParent)
        includedConfigurationPath = externalParent.appending(path: "included.gitconfig")
        unrelatedSiblingPath = externalParent.appending(path: "unrelated.txt")
        excludesFilePath = externalParent.appending(path: "global-excludes")

        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try "[core]\n\tfilemode = false\n".write(
            to: includedConfigurationPath,
            atomically: true,
            encoding: .utf8
        )
        try "ignored.txt\n".write(
            to: excludesFilePath,
            atomically: true,
            encoding: .utf8
        )
        try Self.initializeRepository(
            at: firstRepositoryPath,
            includedConfigurationPath: includedConfigurationPath,
            excludesFilePath: excludesFilePath
        )
        try Self.initializeRepository(
            at: secondRepositoryPath,
            includedConfigurationPath: includedConfigurationPath,
            excludesFilePath: excludesFilePath
        )

        externalParentPath = DarwinFSEventPathCanonicalizer.canonicalURL(externalParent).path
        nativeStreamRecorder = NativeSharedExactItemStreamRecorder(
            nativeSharedStreamIsEnabled: nativeSharedStreamIsEnabled
        )
        streamClient = DarwinFSEventStreamClient(
            sharedExactItemStreamFactory: nativeStreamRecorder.makeStream
        )
        provider = Self.makeProvider(
            continuityWitness: streamClient,
            readRecorder: readRecorder,
            exactItemParent: exactItemParent
        )

        streamClient.register(
            worktreeId: firstWorktreeId,
            repoId: UUIDv7.generate(),
            rootPath: firstRepositoryPath
        )
        streamClient.register(
            worktreeId: secondWorktreeId,
            repoId: UUIDv7.generate(),
            rootPath: secondRepositoryPath
        )
    }

    func establishAuthority(
        worktreeId: UUID,
        repositoryPath: URL
    ) async -> GitCleanContinuityAuthority? {
        let result = await provider.exactCleanStatusFactsResult(
            for: worktreeId,
            rootPath: repositoryPath
        )
        guard case .available(let facts) = result else { return nil }
        return facts.exactCleanAuthority
    }

    func collectFullGitRefreshBatches(
        expectedWorktreeIds: Set<UUID>
    ) -> Task<[UUID: FSEventBatch], Never> {
        let streamClient = streamClient
        return Task {
            var batchByWorktreeId: [UUID: FSEventBatch] = [:]
            for await ingressItem in streamClient.events() {
                if case .activityProcessingFence(let fenceID) = ingressItem {
                    streamClient.acknowledgeActivityProcessingFence(fenceID)
                    continue
                }
                guard case .batch(let batch) = ingressItem else { continue }
                guard expectedWorktreeIds.contains(batch.worktreeId) else { continue }
                guard batch.requiresFullGitRefresh else { continue }
                batchByWorktreeId[batch.worktreeId] = batch
                if batchByWorktreeId.keys.count == expectedWorktreeIds.count {
                    return batchByWorktreeId
                }
            }
            return batchByWorktreeId
        }
    }

    func awaitLocalStreamSentinelBarrier() async throws -> Bool {
        sentinelWriteSequence += 1
        let sentinelPathByWorktreeId = [
            firstWorktreeId: Self.sentinelPath(in: firstRepositoryPath),
            secondWorktreeId: Self.sentinelPath(in: secondRepositoryPath),
        ]
        let batchTask = collectLocalSentinelBatches(
            expectedPathByWorktreeId: sentinelPathByWorktreeId.mapValues {
                DarwinFSEventPathCanonicalizer.canonicalURL($0).path
            }
        )

        for sentinelPath in sentinelPathByWorktreeId.values {
            try "sentinel \(sentinelWriteSequence)\n".write(
                to: sentinelPath,
                atomically: false,
                encoding: .utf8
            )
        }

        let observedWorktreeIds = await firstCompletedValue(
            from: batchTask,
            timeout: .seconds(5)
        )
        return observedWorktreeIds == Set(sentinelPathByWorktreeId.keys)
    }

    func waitForNativeCallback(at path: URL) async -> Bool {
        let expectedPath = DarwinFSEventPathCanonicalizer.canonicalURL(path).path
        let callbackTask = Task {
            await nativeStreamRecorder.waitForCallback(at: expectedPath)
            return true
        }
        return await firstCompletedValue(from: callbackTask, timeout: .seconds(5)) == true
    }

    func waitForNativeCallbackUnderExternalParent() async -> Bool {
        let callbackTask = Task {
            await nativeStreamRecorder.waitForCallback(under: externalParentPath)
            return true
        }
        return await firstCompletedValue(from: callbackTask, timeout: .seconds(5)) == true
    }

    func waitForNativeRootChangedCallback() async -> Bool {
        let callbackTask = Task {
            await nativeStreamRecorder.waitForRootChangedCallback()
            return true
        }
        return await firstCompletedValue(from: callbackTask, timeout: .seconds(5)) == true
    }

    func perform(_ mutation: SharedExactItemReplacementMutation) throws {
        switch mutation {
        case .delete:
            try FileManager.default.removeItem(at: includedConfigurationPath)
        case .rename:
            try FileManager.default.moveItem(
                at: includedConfigurationPath,
                to: includedConfigurationPath.deletingLastPathComponent().appending(
                    path: "renamed.gitconfig"
                )
            )
        case .atomicReplacement:
            try "[core]\n\tfilemode = true\n".write(
                to: includedConfigurationPath,
                atomically: true,
                encoding: .utf8
            )
        }
    }

    func replaceExternalParent() throws -> URL {
        let replacementParent = fixtureRoot.appending(
            path: "external-replacement",
            directoryHint: .isDirectory
        )
        try FileManager.default.moveItem(
            at: includedConfigurationPath.deletingLastPathComponent(),
            to: replacementParent
        )
        return replacementParent
    }

    func pointRepositoriesToExternalParent(_ replacementParent: URL) throws {
        let replacementConfiguration = replacementParent.appending(path: includedConfigurationPath.lastPathComponent)
        let replacementExcludes = replacementParent.appending(path: excludesFilePath.lastPathComponent)
        for repositoryPath in [firstRepositoryPath, secondRepositoryPath] {
            let git = IsolatedGitProcess(repositoryPath: repositoryPath)
            try git.run(["config", "include.path", replacementConfiguration.path])
            try git.run(["config", "core.excludesFile", replacementExcludes.path])
        }
        exactItemParent.replace(with: replacementParent)
    }

    func rebindWorktreeRegistrations() {
        for (worktreeId, repositoryPath) in [
            (firstWorktreeId, firstRepositoryPath),
            (secondWorktreeId, secondRepositoryPath),
        ] {
            streamClient.unregister(worktreeId: worktreeId)
            streamClient.register(
                worktreeId: worktreeId,
                repoId: UUIDv7.generate(),
                rootPath: repositoryPath
            )
        }
    }

    func firstCompletedValue<TValue: Sendable>(
        from task: Task<TValue, Never>,
        timeout: Duration
    ) async -> TValue? {
        await withTaskGroup(of: TValue?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await AsyncDelay.taskSleep.wait(timeout)
                return nil
            }
            guard let firstValue = await group.next() else { return nil }
            group.cancelAll()
            task.cancel()
            return firstValue
        }
    }

    func requiresExact(_ result: GitExactCleanRenewalResult) -> Bool {
        guard case .requiresExact = result else { return false }
        return true
    }

    func remove() {
        streamClient.shutdown()
        try? FileManager.default.removeItem(at: fixtureRoot)
    }

    private static func initializeRepository(
        at repositoryPath: URL,
        includedConfigurationPath: URL,
        excludesFilePath: URL
    ) throws {
        try FileManager.default.createDirectory(at: repositoryPath, withIntermediateDirectories: true)
        let git = IsolatedGitProcess(repositoryPath: repositoryPath)
        try git.run(["init"])
        try "initial\n".write(
            to: repositoryPath.appending(path: "README.md"),
            atomically: true,
            encoding: .utf8
        )
        try git.run(["add", "README.md"])
        try git.run(["commit", "-m", "initial"])
        try git.run(["config", "include.path", includedConfigurationPath.path])
        try git.run(["config", "core.excludesFile", excludesFilePath.path])
    }

    private static func makeProvider(
        continuityWitness: DarwinFSEventStreamClient,
        readRecorder: GitPhysicalReadRecorder,
        exactItemParent: SharedExactItemParent
    ) -> AgentStudioGitWorkingTreeStatusProvider {
        let gitClient = AgentStudioGit.LibGit2AgentStudioGitLocalClient()
        return AgentStudioGitWorkingTreeStatusProvider(
            physicalGate: AgentStudioGitStatusPhysicalGate(),
            continuityWitness: continuityWitness,
            statusObservationPlanReader: { repositoryPath in
                readRecorder.recordObservationPlanRead()
                let resolvedPlan = try await gitClient.statusObservationPlan(for: repositoryPath)
                let canonicalRepositoryPath = DarwinFSEventPathCanonicalizer.canonicalURL(
                    repositoryPath
                ).path
                let currentExactItemParent = exactItemParent.currentURL
                let productionScopes = resolvedPlan.scopes.filter { scope in
                    switch scope.kind {
                    case .item:
                        path(scope.path, isWithin: currentExactItemParent)
                    case .subtree:
                        DarwinFSEventPathCanonicalizer.canonicalURL(scope.path).path
                            == canonicalRepositoryPath
                    }
                }
                return AgentStudioGit.GitStatusObservationPlan(
                    identity: AgentStudioGit.GitStatusObservationIdentity(
                        rawValue:
                            productionScopes
                            .map { "\($0.kind.rawValue):\($0.path.path)" }
                            .sorted()
                            .joined(separator: "\u{0}")
                    ),
                    scopes: productionScopes,
                    support: resolvedPlan.support
                )
            },
            verifiedStatusFactsReader: { repositoryPath, options, observationPlan in
                readRecorder.recordVerifiedFactsRead()
                let resolvedPlan = try await gitClient.statusObservationPlan(for: repositoryPath)
                let resolvedRead = try await gitClient.statusFacts(
                    for: repositoryPath,
                    options: options,
                    observationPlan: resolvedPlan
                )
                return AgentStudioGit.GitStatusFactsRead(
                    facts: resolvedRead.facts,
                    exactCleanBaseline: resolvedRead.exactCleanBaseline.flatMap { _ in
                        observationPlan.map {
                            AgentStudioGit.GitExactCleanBaseline(
                                observationIdentity: $0.identity
                            )
                        }
                    }
                )
            },
            statusFactsReader: { repositoryPath, options in
                readRecorder.recordOrdinaryFactsRead()
                return try await gitClient.statusFacts(
                    for: repositoryPath,
                    options: options
                ).facts
            },
            lineDetailReader: { repositoryPath in
                readRecorder.recordLineDetailRead()
                return try await gitClient.exactLineCountDetail(for: repositoryPath)
            },
            statusReader: { repositoryPath, options in
                readRecorder.recordCompleteStatusRead()
                return try await gitClient.completeStatus(
                    for: repositoryPath,
                    options: options
                )
            }
        )
    }

    private func collectLocalSentinelBatches(
        expectedPathByWorktreeId: [UUID: String]
    ) -> Task<Set<UUID>, Never> {
        let streamClient = streamClient
        return Task {
            var observedWorktreeIds: Set<UUID> = []
            for await ingressItem in streamClient.events() {
                if case .activityProcessingFence(let fenceID) = ingressItem {
                    streamClient.acknowledgeActivityProcessingFence(fenceID)
                    continue
                }
                guard case .batch(let batch) = ingressItem else { continue }
                guard let expectedPath = expectedPathByWorktreeId[batch.worktreeId] else {
                    continue
                }
                guard
                    batch.paths.contains(where: {
                        DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath($0) == expectedPath
                    })
                else {
                    continue
                }
                observedWorktreeIds.insert(batch.worktreeId)
                if observedWorktreeIds.count == expectedPathByWorktreeId.count {
                    return observedWorktreeIds
                }
            }
            return observedWorktreeIds
        }
    }

    private static func sentinelPath(in repositoryPath: URL) -> URL {
        repositoryPath
            .appending(path: ".git", directoryHint: .isDirectory)
            .appending(path: "agentstudio-real-stream-sentinel")
    }

    private static func path(_ candidate: URL, isWithin root: URL) -> Bool {
        let canonicalCandidate = DarwinFSEventPathCanonicalizer.canonicalURL(candidate).path
        let canonicalRoot = DarwinFSEventPathCanonicalizer.canonicalURL(root).path
        return canonicalCandidate == canonicalRoot
            || canonicalCandidate.hasPrefix(canonicalRoot + "/")
    }
}

final class SharedExactItemParent: @unchecked Sendable {
    private let lock = NSLock()
    private var parentURL: URL

    init(initialURL: URL) {
        parentURL = initialURL
    }

    var currentURL: URL {
        lock.withLock { parentURL }
    }

    func replace(with replacementURL: URL) {
        lock.withLock {
            parentURL = replacementURL
        }
    }
}

final class NativeSharedExactItemStreamRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let nativeSharedStreamIsEnabled: Bool
    private let callbackEvents: AsyncStream<DarwinSharedExactItemRawEvent>
    private let callbackEventsContinuation: AsyncStream<DarwinSharedExactItemRawEvent>.Continuation
    private var startCountByParentPath: [String: Int] = [:]

    init(nativeSharedStreamIsEnabled: Bool) {
        self.nativeSharedStreamIsEnabled = nativeSharedStreamIsEnabled
        (callbackEvents, callbackEventsContinuation) = AsyncStream.makeStream(
            of: DarwinSharedExactItemRawEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
    }

    func startCount(forParentPath parentPath: String) -> Int {
        lock.withLock { startCountByParentPath[parentPath, default: 0] }
    }

    func makeStream(
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64,
        eventHandler: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        lock.withLock {
            startCountByParentPath[parentKey.parentPath, default: 0] += 1
        }
        guard nativeSharedStreamIsEnabled else { return nil }
        return DarwinSharedExactItemNativeStream.start(
            parentKey: parentKey,
            streamGeneration: streamGeneration,
            eventHandler: { [weak self] rawEvents in
                eventHandler(rawEvents)
                for rawEvent in rawEvents {
                    self?.callbackEventsContinuation.yield(rawEvent)
                }
            }
        )
    }

    func waitForCallback(at expectedPath: String) async {
        for await event in callbackEvents
        where DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath(event.path) == expectedPath {
            return
        }
    }

    func waitForCallback(under parentPath: String) async {
        for await event in callbackEvents {
            let normalizedPath = DarwinFSEventPathNormalizer.lexicallyNormalizedAbsolutePath(
                event.path
            )
            if normalizedPath == parentPath || normalizedPath.hasPrefix(parentPath + "/") {
                return
            }
        }
    }

    func waitForRootChangedCallback() async {
        for await event in callbackEvents
        where event.flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            return
        }
    }
}

struct GitPhysicalReadSnapshot: Sendable, Equatable {
    let observationPlanReadCount: Int
    let verifiedFactsReadCount: Int
    let ordinaryFactsReadCount: Int
    let lineDetailReadCount: Int
    let completeStatusReadCount: Int
}

final class GitPhysicalReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var observationPlanReadCount = 0
    private var verifiedFactsReadCount = 0
    private var ordinaryFactsReadCount = 0
    private var lineDetailReadCount = 0
    private var completeStatusReadCount = 0

    var snapshot: GitPhysicalReadSnapshot {
        lock.withLock {
            GitPhysicalReadSnapshot(
                observationPlanReadCount: observationPlanReadCount,
                verifiedFactsReadCount: verifiedFactsReadCount,
                ordinaryFactsReadCount: ordinaryFactsReadCount,
                lineDetailReadCount: lineDetailReadCount,
                completeStatusReadCount: completeStatusReadCount
            )
        }
    }

    func recordObservationPlanRead() {
        lock.withLock { observationPlanReadCount += 1 }
    }

    func recordVerifiedFactsRead() {
        lock.withLock { verifiedFactsReadCount += 1 }
    }

    func recordOrdinaryFactsRead() {
        lock.withLock { ordinaryFactsReadCount += 1 }
    }

    func recordLineDetailRead() {
        lock.withLock { lineDetailReadCount += 1 }
    }

    func recordCompleteStatusRead() {
        lock.withLock { completeStatusReadCount += 1 }
    }
}

private struct IsolatedGitProcess {
    let repositoryPath: URL

    func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments =
            [
                "git",
                "-c", "user.name=AgentStudio Test",
                "-c", "user.email=agentstudio@example.invalid",
                "-c", "commit.gpgsign=false",
                "-c", "init.defaultBranch=main",
            ] + arguments
        process.currentDirectoryURL = repositoryPath
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "GIT_CONFIG_XDG": "/dev/null",
                "GIT_TERMINAL_PROMPT": "0",
                "LC_ALL": "C",
            ]
        ) { _, testValue in testValue }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let standardError = Pipe()
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""
            throw IsolatedGitProcessError(
                arguments: arguments,
                exitCode: process.terminationStatus,
                errorText: errorText
            )
        }
    }
}

private struct IsolatedGitProcessError: Error {
    let arguments: [String]
    let exitCode: Int32
    let errorText: String
}
