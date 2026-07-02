import Foundation
import Testing

@testable import AgentStudio

@Suite("PaneContextFacets")
struct PaneContextFacetsTests {
    @Test("fillingNilFields fills nil and empty fields from defaults")
    func fillingNilFieldsFillsMissingValues() {
        let defaults = PaneContextFacets(
            repoId: UUID(),
            repoName: "agent-studio",
            worktreeId: UUID(),
            worktreeName: "main",
            cwd: URL(fileURLWithPath: "/tmp/default"),
            parentFolder: "dev",
            organizationName: "askluna",
            origin: "origin",
            upstream: "upstream/main"
        )
        let base = PaneContextFacets.empty

        let merged = base.fillingNilFields(from: defaults)

        #expect(merged.repoId == defaults.repoId)
        #expect(merged.repoName == defaults.repoName)
        #expect(merged.worktreeId == defaults.worktreeId)
        #expect(merged.worktreeName == defaults.worktreeName)
        #expect(merged.cwd == defaults.cwd)
        #expect(merged.parentFolder == defaults.parentFolder)
        #expect(merged.organizationName == defaults.organizationName)
        #expect(merged.origin == defaults.origin)
        #expect(merged.upstream == defaults.upstream)
    }

    @Test("fillingNilFields does not overwrite existing non-nil values")
    func fillingNilFieldsPreservesExistingValues() {
        let existing = PaneContextFacets(
            repoId: UUID(),
            repoName: "existing-repo",
            worktreeId: UUID(),
            worktreeName: "feature-branch",
            cwd: URL(fileURLWithPath: "/tmp/existing"),
            parentFolder: "existing-parent",
            organizationName: "existing-org",
            origin: "existing-origin",
            upstream: "existing/upstream"
        )
        let defaults = PaneContextFacets(
            repoId: UUID(),
            repoName: "default-repo",
            worktreeId: UUID(),
            worktreeName: "default-worktree",
            cwd: URL(fileURLWithPath: "/tmp/default"),
            parentFolder: "default-parent",
            organizationName: "default-org",
            origin: "default-origin",
            upstream: "default/upstream"
        )

        let merged = existing.fillingNilFields(from: defaults)

        #expect(merged == existing)
    }

}
