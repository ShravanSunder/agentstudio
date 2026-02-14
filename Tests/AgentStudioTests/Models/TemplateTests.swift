import XCTest
@testable import AgentStudio

final class TemplateTests: XCTestCase {

    // MARK: - TerminalTemplate

    func test_terminalTemplate_defaults() {
        let template = TerminalTemplate()
        XCTAssertEqual(template.title, "Terminal")
        XCTAssertNil(template.agent)
        XCTAssertEqual(template.provider, .ghostty)
        XCTAssertNil(template.relativeWorkingDir)
    }

    func test_terminalTemplate_instantiate() {
        let worktreeId = UUID()
        let repoId = UUID()
        let template = TerminalTemplate(
            title: "Claude Agent",
            agent: .claude,
            provider: .zmx
        )

        let pane = template.instantiate(worktreeId: worktreeId, repoId: repoId)

        XCTAssertEqual(pane.title, "Claude Agent")
        XCTAssertEqual(pane.agent, .claude)
        XCTAssertEqual(pane.provider, .zmx)
        XCTAssertEqual(pane.worktreeId, worktreeId)
        XCTAssertEqual(pane.repoId, repoId)
    }

    func test_terminalTemplate_codable_roundTrip() throws {
        let template = TerminalTemplate(
            title: "Dev",
            agent: .claude,
            provider: .ghostty,
            relativeWorkingDir: "src"
        )

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(TerminalTemplate.self, from: data)

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertEqual(decoded.title, "Dev")
        XCTAssertEqual(decoded.agent, .claude)
        XCTAssertEqual(decoded.relativeWorkingDir, "src")
    }

    // MARK: - WorktreeTemplate

    func test_worktreeTemplate_defaults() {
        let template = WorktreeTemplate()
        XCTAssertEqual(template.name, "Default")
        XCTAssertEqual(template.terminals.count, 1)
        XCTAssertEqual(template.createPolicy, .manual)
        XCTAssertEqual(template.splitDirection, .horizontal)
    }

    func test_worktreeTemplate_instantiate_single() {
        let worktreeId = UUID()
        let repoId = UUID()
        let template = WorktreeTemplate(
            name: "Simple",
            terminals: [TerminalTemplate(title: "Shell")]
        )

        let (panes, tab) = template.instantiate(worktreeId: worktreeId, repoId: repoId)

        XCTAssertEqual(panes.count, 1)
        XCTAssertEqual(panes[0].title, "Shell")
        XCTAssertEqual(tab.paneIds.count, 1)
        XCTAssertEqual(tab.paneIds[0], panes[0].id)
        XCTAssertFalse(tab.isSplit)
    }

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

        XCTAssertEqual(panes.count, 3)
        XCTAssertEqual(tab.paneIds.count, 3)
        XCTAssertTrue(tab.isSplit)
        XCTAssertEqual(tab.activePaneId, panes[0].id)
        // All pane IDs should be present in the layout
        for pane in panes {
            XCTAssertTrue(tab.paneIds.contains(pane.id))
        }
    }


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

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertEqual(decoded.name, "Full Stack")
        XCTAssertEqual(decoded.terminals.count, 2)
        XCTAssertEqual(decoded.createPolicy, .onCreate)
        XCTAssertEqual(decoded.splitDirection, .vertical)
    }

    // MARK: - CreatePolicy

    func test_createPolicy_codable() throws {
        let policies: [CreatePolicy] = [.onCreate, .onActivate, .manual]

        for policy in policies {
            let data = try JSONEncoder().encode(policy)
            let decoded = try JSONDecoder().decode(CreatePolicy.self, from: data)
            XCTAssertEqual(decoded, policy)
        }
    }

    // MARK: - Hashable

    func test_terminalTemplate_hashable() {
        let t1 = TerminalTemplate(title: "A")
        let t2 = TerminalTemplate(title: "B")
        let set: Set<TerminalTemplate> = [t1, t2, t1]
        XCTAssertEqual(set.count, 2)
    }

    func test_worktreeTemplate_hashable() {
        let wt1 = WorktreeTemplate(name: "A")
        let wt2 = WorktreeTemplate(name: "B")
        let set: Set<WorktreeTemplate> = [wt1, wt2, wt1]
        XCTAssertEqual(set.count, 2)
    }
}
