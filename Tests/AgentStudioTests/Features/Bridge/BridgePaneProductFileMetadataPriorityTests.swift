import Foundation
import Testing

@testable import AgentStudio

@Suite("Bridge pane product File metadata priority")
struct BridgePaneProductFileMetadataPriorityTests {
    @Test("foreground descriptor reconciles before visible descriptors")
    func foregroundDescriptorReconcilesBeforeVisibleDescriptors() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 40, demandedIndex: 39)
        defer { fixture.remove() }
        let source = fixture.makeSource(treeRowRefresher: { rootURL, relativePaths, includeAncestors in
            let refreshed = await BridgeWorktreeFileMaterializer.refreshTreeRows(
                rootURL: rootURL,
                relativePaths: relativePaths,
                includeAncestorDirectories: includeAncestors
            )
            return BridgeWorktreeRefreshedTreeRows(
                rows: refreshed.rows.sorted { $0.path < $1.path },
                missingPaths: refreshed.missingPaths
            )
        })
        let openSnapshot = try fixture.openSnapshot()
        try await source.open(
            subscription: openSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let visiblePaths = (0..<39).map { String(format: "File-%04d.swift", $0) }
        let updateSnapshot = try fixture.updatedSnapshot(
            from: openSnapshot,
            visiblePaths: visiblePaths
        )
        let collector = ProductFileMetadataEventCollector()

        // Act
        try await source.update(
            subscription: updateSnapshot,
            productAdmission: fixture.productAdmission.context
        ) { event in
            await collector.append(event)
        }

        // Assert
        let descriptorPaths = (await collector.events).compactMap { event -> String? in
            guard case .descriptorReady(let ready) = event else { return nil }
            return ready.payload.path
        }
        #expect(descriptorPaths.count == 40)
        #expect(descriptorPaths.first == fixture.demandedPath)
    }
}
