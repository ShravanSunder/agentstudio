import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product File metadata totality")
struct BridgePaneProductFileMetadataTotalityTests {
    @Test("admitted interest invalidates when refresh cannot rebuild its manifest row")
    func admittedInterestInvalidatesWhenRefreshOmitsManifestRow() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource(treeRowRefresher: { _, _, _ in
            BridgeWorktreeRefreshedTreeRows(rows: [], missingPaths: [])
        })
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await source.update(
            subscription: fixture.updatedSnapshot(from: openSnapshot),
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }

        // Assert
        let invalidatedPaths = (await collector.events).compactMap { event -> String? in
            guard case .invalidated(let invalidated) = event else { return nil }
            return invalidated.path
        }
        #expect(invalidatedPaths == [fixture.demandedPath])
    }

    @Test("admitted file interest invalidates when the path becomes a directory")
    func admittedFileInterestInvalidatesWhenPathBecomesDirectory() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        try FileManager.default.removeItem(at: fixture.demandedFileURL)
        try FileManager.default.createDirectory(
            at: fixture.demandedFileURL,
            withIntermediateDirectories: false
        )
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await source.update(
            subscription: fixture.updatedSnapshot(from: openSnapshot),
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }

        // Assert
        let invalidatedPaths = (await collector.events).compactMap { event -> String? in
            guard case .invalidated(let invalidated) = event else { return nil }
            return invalidated.path
        }
        #expect(invalidatedPaths == [fixture.demandedPath])
    }
}
