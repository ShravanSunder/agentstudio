import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
final class TemplateTests {

    // MARK: - TerminalTemplate

    @Test

    func test_terminalTemplate_defaults() {
        let template = TerminalTemplate()
        #expect(template.title == "Terminal")
        #expect((template.agent) == nil)
        #expect(template.provider == .zmx)
        #expect((template.relativeWorkingDir) == nil)
    }

    @Test

    func test_terminalTemplate_instantiate() {
        let worktreeId = UUID()
        let repoId = UUID()
        let template = TerminalTemplate(
            title: "Claude Agent",
            agent: .claude,
            provider: .zmx
        )

        let pane = template.instantiate(worktreeId: worktreeId, repoId: repoId)

        #expect(pane.title == "Claude Agent")
        #expect(pane.agent == .claude)
        #expect(pane.provider == .zmx)
        #expect(pane.worktreeId == worktreeId)
        #expect(pane.repoId == repoId)
    }

    @Test

    func test_terminalTemplate_codable_roundTrip() throws {
        let template = TerminalTemplate(
            title: "Dev",
            agent: .claude,
            provider: .ghostty,
            relativeWorkingDir: "src"
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(TerminalTemplate.self, from: data)

        #expect(decoded.id == template.id)
        #expect(decoded.title == "Dev")
        #expect(decoded.agent == .claude)
        #expect(decoded.relativeWorkingDir == "src")
    }

    // MARK: - WorktreeTemplate

    @Test

    func test_worktreeTemplate_defaults() {
        let template = WorktreeTemplate()
        #expect(template.name == "Default")
        #expect(template.terminals.count == 1)
        #expect(template.createPolicy == .manual)
        #expect(template.splitDirection == .horizontal)
    }

    @Test

    func test_worktreeTemplate_instantiate_single() {
        let worktreeId = UUID()
        let repoId = UUID()
        let template = WorktreeTemplate(
            name: "Simple",
            terminals: [TerminalTemplate(title: "Shell")]
        )

        let (panes, tab) = template.instantiate(worktreeId: worktreeId, repoId: repoId)

        #expect(panes.count == 1)
        #expect(panes[0].title == "Shell")
        #expect(tab.paneIds.count == 1)
        #expect(tab.paneIds[0] == panes[0].id)
        #expect(!(tab.isSplit))
    }

    @Test

    func test_worktreeTemplate_instantiate_multi_horizontal() {
        let worktreeId = UUID()
        let repoId = UUID()
        let template = WorktreeTemplate(
            name: "Dev Setup",
            terminals: [
                TerminalTemplate(title: "Editor"),
                TerminalTemplate(title: "Tests"),
                TerminalTemplate(title: "Server"),
            ],
            splitDirection: .horizontal
        )

        let (panes, tab) = template.instantiate(worktreeId: worktreeId, repoId: repoId)

        #expect(panes.count == 3)
        #expect(tab.paneIds.count == 3)
        #expect(tab.isSplit)
        #expect(tab.activePaneId == panes[0].id)
        // All pane IDs should be present in the layout
        for pane in panes {
            #expect(tab.paneIds.contains(pane.id))
        }
    }

    @Test

    func test_worktreeTemplate_codable_roundTrip() throws {
        let template = WorktreeTemplate(
            name: "Full Stack",
            terminals: [
                TerminalTemplate(title: "Frontend", agent: nil),
                TerminalTemplate(title: "Backend", agent: .claude),
            ],
            createPolicy: .onCreate,
            splitDirection: .vertical
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(WorktreeTemplate.self, from: data)

        #expect(decoded.id == template.id)
        #expect(decoded.name == "Full Stack")
        #expect(decoded.terminals.count == 2)
        #expect(decoded.createPolicy == .onCreate)
        #expect(decoded.splitDirection == .vertical)
    }

    // MARK: - CreatePolicy

    @Test

    func test_createPolicy_codable() throws {
        let policies: [CreatePolicy] = [.onCreate, .onActivate, .manual]

        for policy in policies {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(CreatePolicy.self, from: data)
            #expect(decoded == policy)
        }
    }

    // MARK: - Provider/Lifetime Coherence

    @Test

    func test_persistent_pane_requires_zmx_provider() {
        // Invariant: persistent lifetime implies zmx provider.
        // A .ghostty + .persistent pane would claim persistence but have no zmx backend.
        let template = TerminalTemplate()
        let pane = template.instantiate(worktreeId: UUID(), repoId: UUID())

        #expect(pane.provider == .zmx, "Persistent panes must use zmx provider")
        #expect(pane.lifetime == .persistent)
    }

    @Test

    func test_worktreeTemplate_instantiate_produces_zmx_persistent() {
        let template = WorktreeTemplate(
            name: "Test",
            terminals: [TerminalTemplate(title: "Shell")]
        )
        let (panes, _) = template.instantiate(worktreeId: UUID(), repoId: UUID())

        for pane in panes {
            #expect(pane.provider == .zmx, "All template-instantiated panes must use zmx")
            #expect(pane.lifetime == .persistent)
        }
    }

    // MARK: - Hashable

    @Test

    func test_terminalTemplate_hashable() {
        let t1 = TerminalTemplate(title: "A")
        let t2 = TerminalTemplate(title: "B")
        let set: Set<TerminalTemplate> = [t1, t2, t1]
        #expect(set.count == 2)
    }

    @Test

    func test_worktreeTemplate_hashable() {
        let wt1 = WorktreeTemplate(name: "A")
        let wt2 = WorktreeTemplate(name: "B")
        let set: Set<WorktreeTemplate> = [wt1, wt2, wt1]
        #expect(set.count == 2)
    }
}
