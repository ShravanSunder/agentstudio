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
            upstream: "upstream/main",
            tags: ["default"]
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
        #expect(merged.tags == defaults.tags)
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
            upstream: "existing/upstream",
            tags: ["existing"]
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
            upstream: "default/upstream",
            tags: ["default"]
        )

        let merged = existing.fillingNilFields(from: defaults)

        #expect(merged == existing)
    }

    @Test("fillingNilFields falls back to default tags only when source tags are empty")
    func fillingNilFieldsTagMergeRules() {
        let defaults = PaneContextFacets(tags: ["default"])
        let emptyTags = PaneContextFacets(tags: [])
        let nonEmptyTags = PaneContextFacets(tags: ["explicit"])

        let mergedWithEmptyTags = emptyTags.fillingNilFields(from: defaults)
        let mergedWithNonEmptyTags = nonEmptyTags.fillingNilFields(from: defaults)

        #expect(mergedWithEmptyTags.tags == ["default"])
        #expect(mergedWithNonEmptyTags.tags == ["explicit"])
    }
}
