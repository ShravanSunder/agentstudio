import Foundation
import Testing

@testable import AgentStudioTestSupport

@Suite("DerivedValueProductionAdoptionArchitectureTests")
struct DerivedValueProductionAdoptionArchitectureTests {
    @Test("production has one approved DerivedValue constructor")
    func productionHasOneApprovedDerivedValueConstructor() throws {
        let sources = try productionSwiftSources()
        let constructorOwners = sources.filter { source in
            source.contents.contains("DerivedValue<WorkspaceRichTabSnapshot>(")
        }

        #expect(
            constructorOwners.map(\.relativePath) == [
                "Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift"
            ])
    }

    @Test("rich tab snapshot has one production consumer")
    func richTabSnapshotHasOneProductionConsumer() throws {
        let sources = try productionSwiftSources()
        let referenceOwners = sources.filter { source in
            source.contents.contains("richTabSnapshot")
        }

        #expect(
            Set(referenceOwners.map(\.relativePath)) == [
                "Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift",
                "App/Panes/TabBar/TabBarAdapter.swift",
            ])
    }

    @Test("keyed and persistence paths do not consume the fleet snapshot")
    func keyedAndPersistencePathsDoNotConsumeFleetSnapshot() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let layoutSource = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift"
            ),
            encoding: .utf8
        )
        let keyedReadBody = try #require(
            layoutSource.slice(
                from: "package func tab(_ id: UUID)",
                to: "package func tabContaining(paneId: UUID)"
            )
        )
        #expect(!keyedReadBody.contains("richTabSnapshot"))

        let persistenceSources = try productionSwiftSources().filter {
            $0.relativePath.contains("/Persistence/")
                || $0.relativePath.contains("/SQLite/")
        }
        #expect(persistenceSources.allSatisfy { !$0.contents.contains("richTabSnapshot") })
    }

    private func productionSwiftSources() throws -> [(relativePath: String, contents: String)] {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourcesRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        var sources: [(relativePath: String, contents: String)] = []

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let relativePath = String(fileURL.path.dropFirst(sourcesRoot.path.count + 1))
            sources.append(
                (
                    relativePath: relativePath,
                    contents: try String(contentsOf: fileURL, encoding: .utf8)
                ))
        }
        return sources
    }
}

extension String {
    fileprivate func slice(from startMarker: String, to endMarker: String) -> String? {
        guard let start = range(of: startMarker)?.lowerBound,
            let end = range(of: endMarker, range: start..<endIndex)?.lowerBound
        else {
            return nil
        }
        return String(self[start..<end])
    }
}
