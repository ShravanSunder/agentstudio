import Foundation
import Testing

@testable import AgentStudioTestSupport

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

    @Test("no terminal creation path reads the launch presentation flag")
    func noTerminalCreationPathReadsTheLaunchPresentationFlag() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles = try swiftSourceFiles(under: sourcesRoot)

        // Act
        let filesReadingLaunchPresentationFlag = try sourceFiles.filter { sourceFile in
            try String(contentsOf: sourceFile, encoding: .utf8).contains("isInitialRestorePending")
        }

        // Assert: `isInitialRestorePending` is reduced to a read-only launch
        // presentation fact. `ViewRegistry` owns it; `FlatPaneStripContent`
        // is its one remaining presentation consumer. No terminal (or any
        // other) creation path may read it.
        #expect(
            Set(filesReadingLaunchPresentationFlag.map(\.lastPathComponent))
                == ["ViewRegistry.swift", "FlatPaneStripContent.swift"]
        )
    }

    @Test("every terminal surface creation call site passes an authority")
    func everyTerminalSurfaceCreationCallSitePassesAnAuthority() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles = try swiftSourceFiles(under: sourcesRoot)
        let creationCallSignatures = ["createTopologyIndependentTerminalView(", "mountCurrentTerminalContent("]

        // Act: this is a text scan and can pass for the wrong reason on its
        // own — the compiler carries the real weight, since neither creation
        // primitive has a default `authority` argument, so a call site that
        // skips the custody question does not build.
        var callSitesMissingAuthority: [String] = []
        for sourceFile in sourceFiles {
            let lines = try String(contentsOf: sourceFile, encoding: .utf8).components(separatedBy: "\n")
            for (lineIndex, line) in lines.enumerated() {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let isCreationCall =
                    creationCallSignatures.contains { trimmedLine.contains($0) }
                    && !trimmedLine.hasPrefix("func ")
                    && !trimmedLine.hasPrefix("///")
                guard isCreationCall else { continue }
                let followingWindow = lines[lineIndex..<min(lineIndex + 10, lines.count)].joined(separator: "\n")
                if !followingWindow.contains("authority:") {
                    callSitesMissingAuthority.append("\(sourceFile.lastPathComponent):\(lineIndex + 1)")
                }
            }
        }

        // Assert
        #expect(callSitesMissingAuthority.isEmpty)
    }

    @Test("TerminalSurfaceCreationAuthority has exactly three producers")
    func terminalSurfaceCreationAuthorityHasExactlyThreeProducers() throws {
        // Arrange: a file only counts as a producer if it both references
        // the type by name and constructs a value on some non-comment,
        // non-pattern-match line — `.prepared(` and `.released(` alone are
        // too common (other, unrelated types share those case names
        // elsewhere in the codebase), and `case .prepared(...)`/
        // `case .released(...)` are pattern matches over an existing value,
        // not a new one being minted.
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles = try swiftSourceFiles(under: sourcesRoot)
        let constructionSignatures = [".released(", ".prepared(claim"]

        // Act
        let producerFiles = try sourceFiles.filter { sourceFile in
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            guard source.contains("TerminalSurfaceCreationAuthority") else { return false }
            let lines = source.components(separatedBy: "\n")
            return lines.contains { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                guard !trimmedLine.hasPrefix("///"), !trimmedLine.hasPrefix("//") else { return false }
                guard
                    !trimmedLine.contains("case .released("),
                    !trimmedLine.contains("case .prepared(")
                else {
                    return false
                }
                return constructionSignatures.contains { trimmedLine.contains($0) }
            }
        }

        // Assert: the port's successful claim, the registry's own release
        // rule, and the coordinator's pre-boot fallback (no cohort exists
        // yet to claim the pane, so nothing can be waiting on this
        // question — matching the registry's own "no entry, or a stale
        // generation" release rule) are the only three legal producers.
        #expect(
            Set(producerFiles.map(\.lastPathComponent))
                == [
                    "PreparedTerminalMountAdmissionPort.swift",
                    "ViewRegistry.swift",
                    "WorkspaceSurfaceCoordinator+ViewLifecycle.swift",
                ]
        )
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
