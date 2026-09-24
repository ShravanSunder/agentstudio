import AgentStudioCore
import AgentStudioInfrastructure
import Darwin
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge Files collection source")
struct BridgeFileCollectionSourceTests {
    @Test("two worktrees with equal relative paths and an opened document share one collection identity")
    func equalRelativePathsStayDistinctUnderOneIdentity() async throws {
        // Arrange
        let fixture = try await FileCollectionFixture()
        defer { fixture.remove() }
        let collection = fixture.makeCollection(
            members: [fixture.alpha, fixture.beta],
            openedDocuments: [fixture.notesLocation]
        )
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        let openEvents = await collector.events

        // Assert
        let accepted = openEvents.compactMap { event -> BridgeProductFileSourceIdentity? in
            guard case .sourceAccepted(let accepted) = event else { return nil }
            return accepted.source
        }
        let collectionSource = try #require(accepted.first)
        #expect(accepted.count == 1)
        #expect(collectionSource.collectionToken == "receiver-collection")
        #expect(
            memberGroupLists(in: openEvents) == [
                [
                    memberGroup("alpha", fixture.alpha.worktreeId),
                    memberGroup("beta", fixture.beta.worktreeId),
                ]
            ]
        )
        let windows = treeWindows(in: openEvents)
        #expect(windows.allSatisfy { $0.source == collectionSource })
        #expect(windows.map(\.startIndex) == contiguousStartIndexes(of: windows))
        #expect(windows.filter(\.finalWindow).count == 1)
        #expect(windows.last?.finalWindow == true)
        let rows = windows.flatMap(\.rows)
        #expect(windows.last?.totalRowCount == rows.count)
        let rowsByPath = Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0) })
        #expect(rowsByPath["alpha"]?.isDirectory == true)
        #expect(rowsByPath["alpha/src/app.ts"]?.parentPath == "alpha/src")
        #expect(rowsByPath["beta/src/app.ts"]?.depth == 2)
        #expect(rowsByPath["Open Files/notes.md"]?.documentLocation == fixture.notesLocation.canonicalPath)
        #expect(Set(rows.map(\.rowId)).count == rows.count)
        #expect(rowsByPath["alpha/src/app.ts"]?.fileId != rowsByPath["beta/src/app.ts"]?.fileId)

        // Act
        await collector.removeAll()
        try await collection.update(
            subscription: fixture.snapshot(
                revision: 1,
                foregroundPaths: ["alpha/src/app.ts", "beta/src/app.ts", "Open Files/notes.md"]
            ),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }

        // Assert
        let descriptors = availableDescriptors(in: await collector.events)
        #expect(Set(descriptors.keys) == ["alpha/src/app.ts", "beta/src/app.ts", "Open Files/notes.md"])
        #expect(Set(descriptors.values.map(\.descriptorId)).count == 3)
        #expect(descriptors.values.allSatisfy { $0.source == collectionSource })
        for (path, expectedContents) in [
            ("alpha/src/app.ts", "export const origin = 'alpha'\n"),
            ("beta/src/app.ts", "export const origin = 'beta'\n"),
            ("Open Files/notes.md", "# Notes outside Git\n"),
        ] {
            let descriptor = try #require(descriptors[path])
            let request = try fileContentRequest(descriptor: descriptor)
            let plan = try #require(
                await collection.contentReadPlan(for: request, productAdmission: fixture.productAdmission.context)
            )
            #expect(plan.descriptor == descriptor)
            #expect(try await readAll(plan) == expectedContents, "\(path)")
            #expect(
                await collection.authoritativePath(for: request, productAdmission: fixture.productAdmission.context)
                    == path
            )
        }
    }

    @Test("a displayed key resolves back to its document only at the live source generation")
    func displayedKeysResolveBackToDocuments() async throws {
        // Arrange
        let fixture = try await FileCollectionFixture()
        defer { fixture.remove() }
        let collection = fixture.makeCollection(
            members: [fixture.alpha, fixture.beta],
            openedDocuments: [fixture.notesLocation]
        )
        let collector = ProductFileMetadataEventCollector()
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        let source = try #require(
            await collector.events.compactMap { event -> BridgeProductFileSourceIdentity? in
                guard case .sourceAccepted(let accepted) = event else { return nil }
                return accepted.source
            }.first
        )
        let alphaRootPath = DarwinFSEventPathCanonicalizer.canonicalURL(fixture.alphaRoot).path
        let alphaApp = try #require(BridgeDocumentLocation(canonicalPath: "\(alphaRootPath)/src/app.ts"))

        // Act
        let memberFile = await collection.displayedDocument(
            displayPath: "alpha/src/app.ts",
            sourceId: source.sourceId,
            subscriptionGeneration: source.subscriptionGeneration
        )
        let openedDocument = await collection.displayedDocument(
            displayPath: "Open Files/notes.md",
            sourceId: source.sourceId,
            subscriptionGeneration: source.subscriptionGeneration
        )
        let groupRow = await collection.displayedDocument(
            displayPath: "alpha",
            sourceId: source.sourceId,
            subscriptionGeneration: source.subscriptionGeneration
        )
        let staleSource = await collection.displayedDocument(
            displayPath: "alpha/src/app.ts",
            sourceId: source.sourceId,
            subscriptionGeneration: source.subscriptionGeneration + 1
        )

        // Assert
        #expect(
            memberFile
                == .memberFile(worktreeId: fixture.alpha.worktreeId, relativePath: "src/app.ts", location: alphaApp)
        )
        #expect(openedDocument == .openedDocument(fixture.notesLocation))
        #expect(groupRow == nil, "group rows are presentation keys, not documents")
        #expect(staleSource == nil, "a receipt from another source generation never resolves")
        #expect(await collection.listing(displayPath: "alpha/src/app.ts") == .listed)
        #expect(await collection.listing(displayPath: "Open Files/notes.md") == .listed)
        #expect(
            await collection.listing(displayPath: "alpha/src/excluded.ts") == .notListed,
            "a finished enumeration proves an absent row"
        )
        #expect(await collection.displayPath(for: alphaApp) == "alpha/src/app.ts")
        #expect(await collection.displayPath(for: fixture.notesLocation) == "Open Files/notes.md")
        #expect(
            await collection.currentNavigationSource()
                == BridgeProductNavigationFileSource(
                    sourceId: source.sourceId,
                    subscriptionGeneration: source.subscriptionGeneration
                )
        )
    }

    @Test("one failing member leaves the other members browsable and reports the failure")
    func failingMemberLeavesOthersBrowsable() async throws {
        // Arrange
        let fixture = try await FileCollectionFixture()
        defer { fixture.remove() }
        let failingMember = BridgeFileCollectionMemberSource(
            worktreeId: fixture.beta.worktreeId,
            rootURL: fixture.beta.rootURL,
            memberCollectionToken: fixture.beta.memberCollectionToken,
            producer: BridgeUnavailablePaneProductFileMetadataSource()
        )
        let collection = fixture.makeCollection(members: [fixture.alpha, failingMember], openedDocuments: [])
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }

        // Assert
        let windows = treeWindows(in: await collector.events)
        let paths = Set(windows.flatMap(\.rows).map(\.path))
        #expect(paths.contains("alpha/src/app.ts"))
        #expect(paths.contains("beta"))
        #expect(windows.last?.finalWindow == true)
        #expect(
            await collection.memberAvailability(subscriptionId: "file-subscription-1") == [
                fixture.alpha.worktreeId: .available,
                fixture.beta.worktreeId: .failed,
            ]
        )
    }

    @Test("a nested worktree's files are listed once, under the deepest member")
    func nestedWorktreeFilesAreListedOnce() async throws {
        // Arrange
        let fixture = try await FileCollectionFixture()
        defer { fixture.remove() }
        let nestedRoot = fixture.alphaRoot.appending(path: ".worktrees/feature")
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        try Data("export const nested = true\n".utf8).write(to: nestedRoot.appending(path: "nested.ts"))
        let nested = fixture.memberSource(root: nestedRoot)
        let collection = fixture.makeCollection(members: [fixture.alpha, nested], openedDocuments: [])
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }

        // Assert
        let paths = Set(treeWindows(in: await collector.events).flatMap(\.rows).map(\.path))
        #expect(paths.contains("feature/nested.ts"))
        #expect(!paths.contains("alpha/.worktrees/feature/nested.ts"))
        #expect(paths.contains("alpha/src/app.ts"))
        #expect(
            memberGroupLists(in: await collector.events).last == [
                memberGroup("alpha", fixture.alpha.worktreeId, nestedRoots: [".worktrees/feature"]),
                memberGroup("feature", nested.worktreeId),
            ]
        )
    }

    @Test("adding and removing sources later arrives as deltas and revokes only the removed source")
    func membershipChangesArriveAsDeltas() async throws {
        // Arrange
        let fixture = try await FileCollectionFixture()
        defer { fixture.remove() }
        let collection = fixture.makeCollection(members: [fixture.alpha], openedDocuments: [])
        let collector = ProductFileMetadataEventCollector()
        try await collection.open(
            subscription: fixture.snapshot(revision: 0, foregroundPaths: []),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        try await collection.update(
            subscription: fixture.snapshot(revision: 1, foregroundPaths: ["alpha/src/app.ts"]),
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: fixture.foregroundWorkAdmission
        ) { event in await collector.append(event) }
        let alphaDescriptor = try #require(availableDescriptors(in: await collector.events)["alpha/src/app.ts"])
        await collector.removeAll()

        // Act
        try await collection.applyMembership(
            members: [fixture.alpha, fixture.beta],
            openedDocuments: [fixture.notesLocation]
        )
        let additionEvents = await collector.events
        await collector.removeAll()
        try await collection.applyMembership(members: [fixture.beta], openedDocuments: [])
        let removalEvents = await collector.events

        // Assert
        #expect(treeWindows(in: additionEvents).isEmpty)
        #expect(!additionEvents.contains { if case .sourceAccepted = $0 { true } else { false } })
        let addedPaths = Set(upsertedPaths(in: additionEvents))
        #expect(addedPaths.isSuperset(of: ["beta", "beta/src/app.ts", "Open Files", "Open Files/notes.md"]))
        #expect(addedPaths.allSatisfy { !$0.hasPrefix("alpha") })
        #expect(removedPaths(in: additionEvents).isEmpty)
        #expect(
            memberGroupLists(in: additionEvents) == [
                [memberGroup("alpha", fixture.alpha.worktreeId), memberGroup("beta", fixture.beta.worktreeId)]
            ]
        )
        #expect(memberGroupLists(in: removalEvents) == [[memberGroup("beta", fixture.beta.worktreeId)]])
        let addedPrefixes = memberGroupsEvents(in: additionEvents).flatMap(\.groups).map(\.identityPrefix)
        #expect(Set(addedPrefixes).count == 2)
        #expect(addedPrefixes.allSatisfy { $0.hasPrefix("m") && $0.hasSuffix(".") })
        #expect(memberGroupRevisions(in: additionEvents) == [1])
        #expect(memberGroupRevisions(in: removalEvents) == [2])

        let removed = Set(removedPaths(in: removalEvents))
        #expect(removed.isSuperset(of: ["alpha", "alpha/src/app.ts", "Open Files", "Open Files/notes.md"]))
        #expect(removed.allSatisfy { !$0.hasPrefix("beta") })
        #expect(
            removalEvents.contains {
                guard case .invalidated(let invalidation) = $0 else { return false }
                return invalidation.fileId == alphaDescriptor.fileId
            }
        )
        #expect(
            await collection.contentReadPlan(
                for: try fileContentRequest(descriptor: alphaDescriptor),
                productAdmission: fixture.productAdmission.context
            ) == nil
        )
    }
}

// MARK: - Helpers

/// Group lists as `path|worktree|nested roots`; identity prefixes are digests
/// of canonical roots, so they are checked separately for distinctness.
private func memberGroupLists(in events: [BridgeProductFileMemberGroupsEvent]) -> [[String]] {
    events.map { event in
        event.groups.map { group in
            "\(group.groupPath)|\(group.worktreeId)|\(group.nestedMemberRelativeRoots.joined(separator: ","))"
        }
    }
}

private func memberGroupLists(in events: [BridgeProductFileMetadataEvent]) -> [[String]] {
    memberGroupLists(in: memberGroupsEvents(in: events))
}

private func memberGroupsEvents(in events: [BridgeProductFileMetadataEvent]) -> [BridgeProductFileMemberGroupsEvent] {
    events.compactMap { event in
        guard case .memberGroups(let memberGroups) = event else { return nil }
        return memberGroups
    }
}

private func memberGroupRevisions(in events: [BridgeProductFileMetadataEvent]) -> [Int] {
    events.compactMap { event in
        guard case .memberGroups(let memberGroups) = event else { return nil }
        return memberGroups.membershipRevision
    }
}

private func memberGroup(_ groupPath: String, _ worktreeId: UUID, nestedRoots: [String] = []) -> String {
    "\(groupPath)|\(worktreeId.uuidString.lowercased())|\(nestedRoots.joined(separator: ","))"
}

private func treeWindows(in events: [BridgeProductFileMetadataEvent]) -> [BridgeProductFileTreeWindowEvent] {
    events.compactMap { event in
        guard case .treeWindow(let window) = event else { return nil }
        return window
    }
}

private func contiguousStartIndexes(of windows: [BridgeProductFileTreeWindowEvent]) -> [Int] {
    var next = 0
    return windows.map { window in
        defer { next += window.rows.count }
        return next
    }
}

private func upsertedPaths(in events: [BridgeProductFileMetadataEvent]) -> [String] {
    events.flatMap { event -> [String] in
        guard case .treeDelta(let delta) = event else { return [] }
        return delta.operations.flatMap { operation -> [String] in
            guard case .upsertRows(let rows) = operation else { return [] }
            return rows.map(\.path)
        }
    }
}

private func removedPaths(in events: [BridgeProductFileMetadataEvent]) -> [String] {
    events.flatMap { event -> [String] in
        guard case .treeDelta(let delta) = event else { return [] }
        return delta.operations.flatMap { operation -> [String] in
            guard case .removeRows(let paths, _) = operation else { return [] }
            return paths
        }
    }
}

private func availableDescriptors(
    in events: [BridgeProductFileMetadataEvent]
) -> [String: BridgeProductFileContentDescriptor] {
    var descriptors: [String: BridgeProductFileContentDescriptor] = [:]
    for event in events {
        guard case .descriptorReady(let ready) = event,
            case .available(let descriptor) = ready.payload.availability
        else { continue }
        descriptors[ready.payload.path] = descriptor
    }
    return descriptors
}

private func readAll(_ plan: BridgePaneProductFileContentReadPlan) async throws -> String? {
    let reader = try await BridgePaneProductFileContentSource.openReadSession(plan)
    var data = Data()
    while let chunk = try await reader.nextChunk(maximumByteCount: 64 * 1024) { data.append(chunk) }
    await reader.close()
    return String(bytes: data, encoding: .utf8)
}

private func fileContentRequest(
    descriptor: BridgeProductFileContentDescriptor
) throws -> BridgeProductFileContentRequest {
    let data = try JSONSerialization.data(
        withJSONObject: [
            "contentKind": "file.content",
            "contentRequestId": "collection-content-request-1",
            "descriptor": JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)),
            "kind": "content.open",
            "leaseId": "collection-content-lease-1",
            "operationCorrelationId": NSNull(),
            "paneSessionId": "pane-session-1",
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ],
        options: [.sortedKeys]
    )
    let decoded = try BridgeProductStrictJSON.decode(BridgeProductContentRequest.self, from: data)
    guard case .fileContent(let request) = decoded else {
        throw ProductFileSourceFixtureError.invalidContentRequest
    }
    return request
}

private struct FileCollectionFixture {
    let baseURL: URL
    let alphaRoot: URL
    let alpha: BridgeFileCollectionMemberSource
    let beta: BridgeFileCollectionMemberSource
    let notesLocation: BridgeDocumentLocation
    let productAdmission: BridgeProductAdmissionTestContext
    let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission

    init() async throws {
        baseURL = FileManager.default.temporaryDirectory
            .appending(path: "bridge-file-collection-\(UUIDv7.generate().uuidString)")
        alphaRoot = baseURL.appending(path: "alpha")
        let betaRoot = baseURL.appending(path: "beta")
        let looseDirectory = baseURL.appending(path: "outside-git")
        for directory in [alphaRoot.appending(path: "src"), betaRoot.appending(path: "src"), looseDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("export const origin = 'alpha'\n".utf8).write(to: alphaRoot.appending(path: "src/app.ts"))
        try Data("export const origin = 'beta'\n".utf8).write(to: betaRoot.appending(path: "src/app.ts"))
        let notesURL = looseDirectory.appending(path: "notes.md")
        try Data("# Notes outside Git\n".utf8).write(to: notesURL)
        notesLocation = try #require(
            BridgeDocumentLocation(canonicalPath: Self.canonicalPath(notesURL))
        )
        productAdmission = try BridgeProductAdmissionTestContext.make()
        foregroundWorkAdmission = await BridgePaneRefreshWorkAdmissionTestContext.foreground().admission
        alpha = Self.memberSource(root: alphaRoot)
        beta = Self.memberSource(root: betaRoot)
    }

    func remove() {
        try? FileManager.default.removeItem(at: baseURL)
    }

    func memberSource(root: URL) -> BridgeFileCollectionMemberSource {
        Self.memberSource(root: root)
    }

    func makeCollection(
        members: [BridgeFileCollectionMemberSource],
        openedDocuments: [BridgeDocumentLocation]
    ) -> BridgeFileCollectionSource {
        BridgeFileCollectionSource(
            collectionToken: "receiver-collection",
            members: members,
            openedDocuments: openedDocuments
        )
    }

    func snapshot(revision: Int, foregroundPaths: [String]) throws -> BridgeProductSubscriptionSnapshot {
        BridgeProductSubscriptionSnapshot(
            subscription: .fileMetadata(BridgeProductFileSourceSpec(currentCollectionToken: "receiver-collection")),
            subscriptionId: "file-subscription-1",
            subscriptionKind: .fileMetadata,
            workerDerivationEpoch: 1,
            interestRevision: revision,
            interestSha256: String(repeating: "0", count: 64),
            interestState: .fileMetadata(
                interests: foregroundPaths.isEmpty
                    ? []
                    : [try BridgeProductFileMetadataInterestStateGroup(lane: .foreground, paths: foregroundPaths)],
                pathScope: []
            ),
            hasStagedUpdate: false
        )
    }

    private static func memberSource(root: URL) -> BridgeFileCollectionMemberSource {
        let worktree = Worktree(
            id: UUIDv7.generate(),
            repoId: UUIDv7.generate(),
            name: root.lastPathComponent,
            path: root
        )
        return BridgeFileCollectionMemberSource(
            worktreeId: worktree.id,
            rootURL: root,
            memberCollectionToken: worktree.stableKey,
            producer: BridgePaneProductFileMetadataSource(
                authority: .init(paneId: UUIDv7.generate(), worktree: worktree),
                gitReadContext: makeBridgeGitReadContext(rootURL: root),
                constructionCoordinator: BridgeWorktreeProductConstructionCoordinator(),
                statusProvider: ProductFileSourceStatusProvider(),
                ignorePolicyLoader: loadTestBridgeFileIgnorePolicy
            )
        )
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.path.withCString { pointer in
            guard let resolved = Darwin.realpath(pointer, nil) else { return url.path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }
}
