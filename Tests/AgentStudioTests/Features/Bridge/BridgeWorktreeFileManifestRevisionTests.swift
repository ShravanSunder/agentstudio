import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge File manifest keyed revisions")
struct BridgeWorktreeFileManifestRevisionTests {
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
