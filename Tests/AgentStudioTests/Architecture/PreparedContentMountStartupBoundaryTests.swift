import Foundation
import Testing

@Suite("Prepared content mount startup boundary")
struct PreparedContentMountStartupBoundaryTests {
    @Test("prepared owners are the only production initial mount authority")
    func preparedOwnersAreTheOnlyInitialMountAuthority() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles = try swiftSourceFiles(under: sourcesRoot)

        // Act
        let legacyRestoreFiles = try sourceFiles.filter { sourceFile in
            try String(contentsOf: sourceFile, encoding: .utf8).contains("restoreAllViews")
        }
        let initialRestoreCompletionCallers = try sourceFiles.filter { sourceFile in
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            return source.contains(".completeInitialRestore()")
        }

        // Assert
        #expect(legacyRestoreFiles.isEmpty)
        #expect(
            initialRestoreCompletionCallers.map(\.lastPathComponent)
                == ["WorkspacePreparedContentMountCoordinator.swift"]
        )
    }

    @Test("prepared terminal handler uses accepted descriptor without topology")
    func preparedTerminalHandlerUsesAcceptedDescriptorWithoutTopology() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+TerminalContentMounting.swift"
            ),
            encoding: .utf8
        )
        let preparedHandlerStart = try #require(
            source.range(of: "func mountPreparedTerminalContent(")
        )
        let preparedHandlerSource = String(source[preparedHandlerStart.lowerBound...])

        // Act / Assert
        #expect(preparedHandlerSource.contains("let pane = admission.descriptor.pane"))
        #expect(!preparedHandlerSource.contains("repositoryTopologyAtom"))
        #expect(!preparedHandlerSource.contains("registerPaneFilesystemContextIfNeeded"))
        #expect(!preparedHandlerSource.contains("store."))
    }

    private func swiftSourceFiles(under root: URL) throws -> [URL] {
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        return enumerator.compactMap { entry in
            guard let sourceFile = entry as? URL, sourceFile.pathExtension == "swift" else {
                return nil
            }
            return sourceFile
        }
    }
}
