import Foundation
import Testing

@Suite("Atom persistence boundary architecture")
struct AtomPersistenceBoundaryArchitectureTests {
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
}
