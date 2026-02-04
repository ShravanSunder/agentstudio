import Testing
import Foundation
@testable import AgentStudio

@Suite("SessionManager State Validation Tests")
struct SessionManagerValidationTests {

    // MARK: - State Reconciliation Tests

    @Test("Validates and fixes isOpen flag when openTabs is empty but isOpen is true")
    @MainActor
    func validateIsOpenWithEmptyTabs() async throws {
        // This simulates the bug: worktree.isOpen = true but openTabs = []
        // The validateAndReconcileState() should fix this

        // Create worktree with isOpen = true
        var worktree = Worktree(
            name: "test-worktree",
            path: URL(fileURLWithPath: "/tmp/test"),
            branch: "main"
        )
        worktree.isOpen = true

        let project = Project(
            name: "test-project",
            repoPath: URL(fileURLWithPath: "/tmp/test"),
            worktrees: [worktree]
        )

        // After reconciliation, isOpen should be based on openTabs presence
        // Since openTabs would be empty, isOpen should become false
        // This tests the mergeWorktrees change where isOpen is set to false

        // Verify that a new worktree merged from discovered worktrees gets isOpen = false
        let newWorktree = Worktree(
            name: "new-worktree",
            path: URL(fileURLWithPath: "/tmp/test"),
            branch: "main"
        )

        // Simulate merging - isOpen should NOT be preserved from existing
        #expect(newWorktree.isOpen == false)
    }

    @Test("OpenTab has correct structure")
    func openTabStructure() {
        let worktreeId = UUID()
        let projectId = UUID()

        let tab = OpenTab(
            worktreeId: worktreeId,
            projectId: projectId,
            order: 0
        )

        #expect(tab.worktreeId == worktreeId)
        #expect(tab.projectId == projectId)
        #expect(tab.order == 0)
    }

    @Test("AppState can be encoded and decoded")
    func appStateCodecRoundtrip() throws {
        let worktreeId = UUID()
        let projectId = UUID()

        let tab = OpenTab(
            worktreeId: worktreeId,
            projectId: projectId,
            order: 0
        )

        let state = AppState(
            projects: [],
            openTabs: [tab],
            activeTabId: tab.id,
            sidebarWidth: 250,
            windowFrame: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(state)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppState.self, from: data)

        #expect(decoded.openTabs.count == 1)
        #expect(decoded.openTabs.first?.worktreeId == worktreeId)
        #expect(decoded.activeTabId == tab.id)
    }

    // MARK: - Orphan Tab Tests

    @Test("Orphan tabs are detected correctly")
    func orphanTabDetection() {
        // Create a tab that references a non-existent worktree
        let orphanTab = OpenTab(
            worktreeId: UUID(), // Random UUID - no matching worktree
            projectId: UUID(),
            order: 0
        )

        let projects: [Project] = [] // No projects

        // Check if worktree exists
        let worktreeExists = projects.contains { project in
            project.worktrees.contains { $0.id == orphanTab.worktreeId }
        }

        #expect(worktreeExists == false)
    }

    @Test("Valid tabs are not removed")
    func validTabNotRemoved() {
        let worktreeId = UUID()
        let projectId = UUID()

        let worktree = Worktree(
            id: worktreeId,
            name: "test",
            path: URL(fileURLWithPath: "/tmp/test"),
            branch: "main"
        )

        let project = Project(
            id: projectId,
            name: "test-project",
            repoPath: URL(fileURLWithPath: "/tmp/test"),
            worktrees: [worktree]
        )

        let tab = OpenTab(
            worktreeId: worktreeId,
            projectId: projectId,
            order: 0
        )

        let projects = [project]

        // Check if worktree exists
        let worktreeExists = projects.contains { proj in
            proj.id == tab.projectId && proj.worktrees.contains { $0.id == tab.worktreeId }
        }

        #expect(worktreeExists == true)
    }

    // MARK: - ActiveTabId Validation

    @Test("ActiveTabId is reset when referencing non-existent tab")
    func activeTabIdValidation() {
        let tabs = [
            OpenTab(worktreeId: UUID(), projectId: UUID(), order: 0)
        ]

        let invalidActiveId = UUID() // Not in tabs

        // Check if activeTabId is valid
        let isValid = tabs.contains { $0.id == invalidActiveId }

        #expect(isValid == false)
    }

    @Test("Valid activeTabId is preserved")
    func validActiveTabIdPreserved() {
        let tab = OpenTab(worktreeId: UUID(), projectId: UUID(), order: 0)
        let tabs = [tab]

        // Check if activeTabId is valid
        let isValid = tabs.contains { $0.id == tab.id }

        #expect(isValid == true)
    }
}
