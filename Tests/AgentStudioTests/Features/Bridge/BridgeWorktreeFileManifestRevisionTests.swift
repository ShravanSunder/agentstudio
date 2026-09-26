import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge File manifest keyed revisions")
struct BridgeWorktreeFileManifestRevisionTests {
    @Test("descriptor attempts mint with the current File row and reject stale success and unavailable")
    func descriptorAttemptsAreGuardedByTheIndex() async throws {
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let foreground = await BridgePaneRefreshWorkAdmissionTestContext.foreground().admission
        let index = BridgeWorktreeFileManifestIndex(
            generation: 1, rootURL: fixture.rootURL, productAdmission: fixture.productAdmission.context
        )
        let row = testRow(path: fixture.demandedPath)
        let source = try testSource()
        let first = try testPayload(path: row.path, descriptorID: "descriptor-a", source: source)
        let second = try testPayload(path: row.path, descriptorID: "descriptor-b", source: source)
        #expect(
            await index.appendEnumeratedRows(
                [row], productAdmission: fixture.productAdmission.context,
                foregroundWorkAdmission: foreground
            ))
        let oldAttempt = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 1,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        let newAttempt = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 1,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        #expect(oldAttempt != nil && newAttempt != nil)
        if let oldAttempt, let newAttempt {
            #expect(!(await index.acceptDescriptorOutcome(first, for: oldAttempt)))
            #expect(await index.acceptDescriptorOutcome(second, for: newAttempt))
        }
        let installed = await index.captureKeyedSnapshot()
        #expect(installed.targetRevision == 2)
        #expect(installed.records.first?.descriptorOutcome == second)
        #expect(installed.records.first?.revision == 2)

        let staleUnavailable = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 2,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        #expect(
            await index.invalidateDescriptor(
                for: row.path, productAdmission: fixture.productAdmission.context
            ))
        if let staleUnavailable {
            let unavailable = try testPayload(
                path: row.path, descriptorID: "descriptor-unavailable", source: source,
                unavailable: true
            )
            #expect(!(await index.acceptDescriptorOutcome(unavailable, for: staleUnavailable)))
        }
        #expect((await index.captureKeyedSnapshot()).records.first?.descriptorOutcome == nil)

        let beforeDelete = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 2,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        _ = await index.removePaths(
            [row.path], productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: foreground
        )
        #expect(
            await index.appendEnumeratedRows(
                [row], productAdmission: fixture.productAdmission.context,
                foregroundWorkAdmission: foreground
            ))
        if let beforeDelete {
            #expect(!(await index.acceptDescriptorOutcome(first, for: beforeDelete)))
        }
        #expect((await index.captureKeyedSnapshot()).records.first?.descriptorOutcome == nil)

        let currentAttempt = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 2,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        if let currentAttempt {
            #expect(await index.acceptDescriptorOutcome(first, for: currentAttempt))
        }
        // A failed downstream emit has no rollback operation on the canonical index.
        #expect((await index.captureKeyedSnapshot()).records.first?.descriptorOutcome == first)
    }

    @Test("a retained A remains issued after B installs until lease release or revocation")
    func retainedDescriptorLeaseKeepsExactIssuedIdentity() async throws {
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let foreground = await BridgePaneRefreshWorkAdmissionTestContext.foreground().admission
        let index = BridgeWorktreeFileManifestIndex(
            generation: 1, rootURL: fixture.rootURL, productAdmission: fixture.productAdmission.context
        )
        let row = testRow(path: fixture.demandedPath)
        let source = try testSource()
        let first = try testPayload(path: row.path, descriptorID: "descriptor-a", source: source)
        let second = try testPayload(path: row.path, descriptorID: "descriptor-b", source: source)
        #expect(
            await index.appendEnumeratedRows(
                [row], productAdmission: fixture.productAdmission.context,
                foregroundWorkAdmission: foreground
            ))
        let firstAttempt = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 1,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        if let firstAttempt { #expect(await index.acceptDescriptorOutcome(first, for: firstAttempt)) }
        let canonicalKey = fixture.demandedFileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let retained = await index.retainCurrentDescriptor(
            for: canonicalKey, productAdmission: fixture.productAdmission.context
        )
        #expect(retained != nil)
        let secondAttempt = await index.reserveDescriptorAttempt(
            for: row.path, source: source, memberIncarnation: "default", interestRevision: 2,
            productAdmission: fixture.productAdmission.context, foregroundWorkAdmission: foreground
        )
        if let secondAttempt { #expect(await index.acceptDescriptorOutcome(second, for: secondAttempt)) }
        if case .available(let firstDescriptor) = first.availability {
            #expect(
                await index.issuedDescriptorOutcome(
                    matching: firstDescriptor, productAdmission: fixture.productAdmission.context
                ) == first)
            if let retained { await index.releaseRetainedDescriptor(retained) }
            #expect(
                await index.issuedDescriptorOutcome(
                    matching: firstDescriptor, productAdmission: fixture.productAdmission.context
                ) == nil)
        }
        let secondLease = await index.retainCurrentDescriptor(
            for: canonicalKey, productAdmission: fixture.productAdmission.context
        )
        #expect(secondLease != nil)
        #expect(await index.retainedDescriptorLeaseCount == 1)
        fixture.productAdmission.close()
        await index.revokeRetainedDescriptors()
        #expect(await index.retainedDescriptorLeaseCount == 0)
    }

    @Test("one index mints revisions during accepted writes and freezes a tombstone with its target")
    func revisionsAndTombstonesFollowCommittedState() async throws {
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let foreground = await BridgePaneRefreshWorkAdmissionTestContext.foreground().admission
        let index = BridgeWorktreeFileManifestIndex(
            generation: 1,
            rootURL: fixture.rootURL,
            productAdmission: fixture.productAdmission.context
        )
        let original = BridgeWorktreeTreeRowMetadata(
            rowId: "file-row-1",
            path: fixture.demandedPath,
            name: fixture.demandedPath,
            parentPath: nil,
            depth: 0,
            isDirectory: false,
            fileId: "file-1",
            fileClass: .source,
            sizeBytes: 4,
            lineCount: 1,
            changeStatus: nil
        )
        let admitted = await index.appendEnumeratedRows(
            [original],
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: foreground
        )
        #expect(admitted)
        let first = await index.captureKeyedSnapshot()
        let canonicalKey = fixture.demandedFileURL.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(first.targetRevision == 1)
        #expect(first.records.first?.key == canonicalKey)
        #expect(first.records.first?.revision == 1)

        let duplicate = await index.upsertRows([original], productAdmission: fixture.productAdmission.context)
        #expect(duplicate)
        #expect((await index.captureKeyedSnapshot()).targetRevision == 1)

        let changed = BridgeWorktreeTreeRowMetadata(
            rowId: original.rowId,
            path: original.path,
            name: original.name,
            parentPath: original.parentPath,
            depth: original.depth,
            isDirectory: original.isDirectory,
            fileId: original.fileId,
            fileClass: original.fileClass,
            sizeBytes: 8,
            lineCount: 2,
            changeStatus: "modified"
        )
        let updated = await index.upsertRows([changed], productAdmission: fixture.productAdmission.context)
        #expect(updated)
        #expect((await index.captureKeyedSnapshot()).records.first?.revision == 2)

        let removed = await index.removePaths(
            [fixture.demandedPath],
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: foreground
        )
        guard case .applied = removed else {
            Issue.record("Expected an admitted File removal")
            return
        }
        let afterDelete = await index.captureKeyedSnapshot()
        #expect(afterDelete.targetRevision == 3)
        #expect(afterDelete.records.isEmpty)
        #expect(afterDelete.tombstoneRevisionByKey[canonicalKey] == 3)

        let completed = await index.markEnumerationComplete(
            productAdmission: fixture.productAdmission.context,
            foregroundWorkAdmission: foreground
        )
        let canonicalRoot = fixture.rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let certified = await index.certifyCompleteAbsence(
            in: canonicalRoot,
            upTo: afterDelete.targetRevision
        )
        let afterCertification = await index.captureKeyedSnapshot()
        #expect(completed && certified)
        #expect(afterCertification.tombstoneRevisionByKey.isEmpty)
        #expect(afterCertification.absenceFloorRevisionByRange[canonicalRoot] == 3)
        #expect(!(await index.acceptsExistingRevision(2, for: canonicalKey)))
        #expect(await index.acceptsExistingRevision(4, for: canonicalKey))

        fixture.productAdmission.close()
        let staleAccepted = await index.upsertRows([changed], productAdmission: fixture.productAdmission.context)
        let afterStaleInput = await index.captureKeyedSnapshot()
        #expect(!staleAccepted)
        #expect(afterStaleInput.targetRevision == 3)
    }
}

private func testRow(path: String) -> BridgeWorktreeTreeRowMetadata {
    .init(
        rowId: "file-row-1", path: path, name: path, parentPath: nil, depth: 0,
        isDirectory: false, fileId: "file-1", fileClass: .source, sizeBytes: 4,
        lineCount: 1, changeStatus: nil
    )
}

private func testSource() throws -> BridgeProductFileSourceIdentity {
    let data = Data(
        """
        {"repoId":"00000000-0000-4000-8000-000000000001","rootRevisionToken":null,
        "sourceCursor":"source-cursor-1","sourceId":"source-1","subscriptionGeneration":1,
        "worktreeId":"00000000-0000-4000-8000-000000000002"}
        """.utf8
    )
    return try BridgeProductStrictJSON.decode(BridgeProductFileSourceIdentity.self, from: data)
}

private func testPayload(
    path: String,
    descriptorID: String,
    source: BridgeProductFileSourceIdentity,
    unavailable: Bool = false
) throws -> BridgeProductFileDescriptorReadyPayload {
    let descriptor = try BridgeProductFileContentDescriptor(
        declaredByteLength: 4, descriptorId: descriptorID,
        expectedSha256: String(repeating: "a", count: 64), fileId: "file-1",
        maximumBytes: 4, source: source,
        window: BridgeProductFileContentWindow(maximumBytes: 4, maximumLines: 10)
    )
    return try .init(
        availability: unavailable ? .unavailable(.unreadable) : .available(descriptor),
        encoding: unavailable ? nil : .utf8,
        endsMidLine: false,
        endsWithNewline: !unavailable,
        estimatedContentHeightPixels: nil,
        fileExtension: "txt",
        fileId: "file-1",
        language: nil,
        modifiedAtUnixMilliseconds: nil,
        path: path,
        payloadByteCount: unavailable ? 0 : 4,
        payloadLineCount: unavailable ? 0 : 1,
        rowId: "file-row-1",
        sizeBytes: 4,
        source: source,
        totalLineCount: unavailable ? nil : 1,
        truncationKind: .complete,
        virtualizedExtentKind: unavailable ? .unavailable : .exactLineCount
    )
}
