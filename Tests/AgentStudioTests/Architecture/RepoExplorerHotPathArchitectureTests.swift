import Foundation
import Testing

@Suite("RepoExplorerHotPathArchitectureTests")
struct RepoExplorerHotPathArchitectureTests {
    @Test("RepoExplorer model files are pure and do not read atoms")
    func repoExplorerModelFilesDoNotReadAtoms() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let modelsDirectory = projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/Models")
        let modelFiles = try FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }

        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerSnapshot.swift"))
        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerProjection.swift"))
        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerRowIndex.swift"))
        #expect(modelFiles.map(\.lastPathComponent).contains("RepoExplorerProjectionWorker.swift"))

        for file in modelFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("atom("), "\(file.lastPathComponent) must stay free of atom reads")
        }
    }

    @Test("RepoExplorerView renders from row index instead of walking groups per row")
    func repoExplorerViewRendersFromRowIndex() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("RepoExplorerRowIndex"))
        #expect(source.contains("RepoExplorerProjectionWorker()"))
        #expect(!source.contains("private var sidebarProjection: SidebarProjection"))
        #expect(!source.contains("private var sidebarRowIndex: RepoExplorerRowIndex"))
        #expect(!source.contains("private func resolvedWorktreeContext("))
        #expect(!source.contains(".id(sidebarProjectionFingerprint)"))
    }
}
