import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("Atom persistence boundary architecture")
struct AtomPersistenceBoundaryArchitectureTests {
    @Test("AtomRegistry contains no persistence revision authority")
    func atomRegistryContainsNoPersistenceRevisionAuthority() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let atomRegistryPath = projectRoot.appending(path: "Sources/AgentStudio/AtomRegistry.swift")

        // Act
        let source = try String(contentsOf: atomRegistryPath, encoding: .utf8)

        // Assert
        #expect(!source.contains("WorkspacePersistenceRevisionOwner"))
    }

    @Test("canonical atom files contain no persistence infrastructure")
    func canonicalAtomFilesContainNoPersistenceInfrastructure() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let atomDirectory = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/MainActor/Atoms"
        )
        let atomSourceFiles = try FileManager.default.contentsOfDirectory(
            at: atomDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter {
            $0.pathExtension == "swift"
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let forbiddenVocabulary = [
            "WorkspacePersistenceRevisionOwner",
            "WorkspacePersistenceTransaction",
            "WorkspacePersistenceSnapshot",
            "WorkspaceStateSnapshot",
            "SnapshotPagerParticipant",
            "makePersistenceSnapshotParticipant",
            "preparePersistenceMutation",
            "prepareSnapshotMutation",
            "prepareHydrate",
        ]
        var violations: [String] = []

        // Act
        for atomSourceFile in atomSourceFiles {
            let source = try String(contentsOf: atomSourceFile, encoding: .utf8)
            for forbiddenTerm in forbiddenVocabulary where source.contains(forbiddenTerm) {
                violations.append("\(atomSourceFile.lastPathComponent): \(forbiddenTerm)")
            }
            if atomSourceFile.lastPathComponent.contains("Persistence") {
                violations.append("\(atomSourceFile.lastPathComponent): persistence-owned filename")
            }
        }

        // Assert
        #expect(
            violations.isEmpty,
            Comment(
                rawValue:
                    "Canonical atoms may own state and local invariants only; move persistence infrastructure to "
                    + "State/MainActor/Persistence:\n"
                    + violations.joined(separator: "\n")
            )
        )
    }

    @Test("repository keyed pull request apply never discovers keys from the whole fact family")
    func repositoryKeyedPullRequestApplyUsesOwnedKeyIndex() throws {
        // Arrange
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let repoCacheAtomPath = projectRoot.appending(
            path: "Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift"
        )
        let source = try String(contentsOf: repoCacheAtomPath, encoding: .utf8)
        let keyedApplyStart = try #require(
            source.range(of: "package func applyPullRequestRepositoryProjection(")?.lowerBound
        )
        let keyedApplyEnd = try #require(
            source.range(
                of: "private static func materializedPullRequestProjection(",
                range: keyedApplyStart..<source.endIndex
            )?.lowerBound
        )
        let keyedApplySource = source[keyedApplyStart..<keyedApplyEnd]

        // Act
        let declaresRepositoryKeyIndex = source.contains(
            "private var pullRequestFactKeysByRepoId: [UUID: Set<RepoBranchKey>]"
        )
        let discoversKeysFromWholeFamily = keyedApplySource.contains(
            "pullRequestFactsMap.snapshot()"
        )

        // Assert
        #expect(declaresRepositoryKeyIndex)
        #expect(!discoversKeysFromWholeFamily)
    }
}
