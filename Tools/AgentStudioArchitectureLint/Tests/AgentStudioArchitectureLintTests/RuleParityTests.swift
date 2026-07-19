import Foundation
import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct RuleParityTests {
    @Test("bad fixture corpus exercises every migrated rule")
    func badFixtureCorpusExercisesEveryMigratedRule() throws {
        let diagnostics = try lintFixtureCorpus("Bad")
        let actualIDs = Set(diagnostics.map(\.ruleID))
        let expectedIDs = Set(ExpectedRuleInventory.rules.map(\.id))

        #expect(actualIDs.isSuperset(of: expectedIDs))
    }

    @Test("good fixture corpus stays clean")
    func goodFixtureCorpusStaysClean() throws {
        let diagnostics = try lintFixtureCorpus("Good")

        #expect(diagnostics.isEmpty)
    }

    @Test("forbidden architecture marker has dedicated fixture coverage")
    func forbiddenArchitectureMarkerHasDedicatedFixtureCoverage() throws {
        let markerFixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("App")
            .appendingPathComponent("BadForbiddenArchitectureMarker.swift")
            .path

        let diagnostics = try lint(files: [markerFixture])

        #expect(diagnostics.map(\.ruleID) == ["agentstudio_no_forbidden_architecture_marker"])
    }

    @Test("generic clock sleep rule handles relative AgentStudio source paths")
    func genericClockSleepRuleHandlesRelativeAgentStudioSourcePaths() {
        let allowedDiagnostics = GenericClockSleepRule().validate(
            context: context(
                path: "Sources/AgentStudio/Infrastructure/Extensions/FoundationExtensions.swift",
                source: """
                    import Foundation

                    enum AsyncDelay {
                        static func clock(_ clock: any Clock<Duration>) async throws {
                            try await clock.sleep(for: .milliseconds(1))
                        }
                    }
                    """
            )
        )
        let deniedDiagnostics = GenericClockSleepRule().validate(
            context: context(
                path: "Sources/AgentStudio/App/BadGenericClockSleep.swift",
                source: """
                    import Foundation

                    func waitOnTaskSleepFor() async throws {
                        try await Task.sleep(for: .milliseconds(1))
                    }
                    """
            )
        )

        #expect(allowedDiagnostics.isEmpty)
        #expect(deniedDiagnostics.map(\.ruleID) == ["agentstudio_no_generic_clock_sleep"])
    }

    @Test("test task sleep rule diagnoses every denied fixture call shape")
    func testTaskSleepRuleDiagnosesEveryDeniedFixtureCallShape() throws {
        let taskSleepFixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Tests")
            .appendingPathComponent("AgentStudioTests")
            .appendingPathComponent("BadTaskSleepTest.swift")
            .path

        let diagnostics = try lint(files: [taskSleepFixture])
            .filter { $0.ruleID == "agentstudio_no_task_sleep_in_tests" }

        #expect(diagnostics.map(\.line) == [5, 9, 13, 17, 23, 27, 31])
    }

    @Test("test task sleep rule scopes to workspace-relative test paths")
    func testTaskSleepRuleScopesToWorkspaceRelativeTestPaths() {
        let testDiagnostics = TestTaskSleepRule().validate(
            context: context(
                path: "Tests/AgentStudioTests/BadTaskSleepTest.swift",
                source: """
                    import Foundation

                    func waitsWithTaskSleep() async throws {
                        try await Task.sleep(nanoseconds: 1_000_000)
                    }
                    """
            )
        )
        let sourceDiagnostics = TestTaskSleepRule().validate(
            context: context(
                path: "Sources/AgentStudio/App/BadTaskSleepSource.swift",
                source: """
                    import Foundation

                    func waitsWithTaskSleep() async throws {
                        try await Task.sleep(nanoseconds: 1_000_000)
                    }
                    """
            )
        )
        let externalSourceUnderTestsParentDiagnostics = TestTaskSleepRule().validate(
            context: context(
                path: "/tmp/Tests/Project/Sources/AgentStudio/App/BadTaskSleepSource.swift",
                source: """
                    import Foundation

                    func waitsWithTaskSleep() async throws {
                        try await Task.sleep(nanoseconds: 1_000_000)
                    }
                    """
            )
        )

        #expect(testDiagnostics.map(\.ruleID) == ["agentstudio_no_task_sleep_in_tests"])
        #expect(sourceDiagnostics.isEmpty)
        #expect(externalSourceUnderTestsParentDiagnostics.isEmpty)
    }

    @Test("EventBus subscriber policy rule diagnoses every denied fixture call shape")
    func eventBusSubscriberPolicyRuleDiagnosesEveryDeniedFixtureCallShape() throws {
        let eventBusFixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("App")
            .appendingPathComponent("BadEventBusSubscriberPolicy.swift")
            .path

        let diagnostics = try lint(files: [eventBusFixture])
            .filter { $0.ruleID == "agentstudio_eventbus_subscriber_policy_required" }

        #expect(diagnostics.count == 10)
        #expect(
            diagnostics.map(\.message).contains(
                "Production EventBus subscriber call sites must pass an explicit BusSubscriberPolicy"))
        #expect(
            diagnostics.map(\.message).contains(
                "Production EventBus subscriber call sites must use BusSubscriberPolicy, not raw AsyncStream bufferingPolicy"
            ))
        #expect(
            diagnostics.map(\.message).contains(
                "Production EventBus wait helpers must pass an explicit BusSubscriberPolicy"))
        #expect(
            diagnostics.map(\.message).contains(
                "Production EventBus subscriber helpers must not provide default policy arguments"))
        #expect(
            diagnostics.map(\.message).contains(
                "Production EventBus subscriber helpers must not hide policy behind zero-argument overloads"))
    }

    @Test("Terminal local disposition publication rule diagnoses every local disposition")
    func terminalLocalDispositionPublicationRuleDiagnosesEveryLocalDisposition() throws {
        let fixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("Features")
            .appendingPathComponent("Terminal")
            .appendingPathComponent("Ghostty")
            .appendingPathComponent("BadTerminalLocalDispositionPublication.swift")
            .path

        let diagnostics = try lint(files: [fixture])
            .filter { $0.ruleID == "agentstudio_terminal_local_disposition_publication" }

        #expect(diagnostics.map(\.line) == [8, 11, 14, 17])
        #expect(
            Set(diagnostics.map(\.message)) == [
                "GhosttyActionDisposition local-only cases must contract locally before routeActionToTerminalRuntimeOnMainActor"
            ])
    }

    @Test("Terminal local disposition publication rule rejects fallthrough to the semantic edge")
    func terminalLocalDispositionPublicationRuleRejectsFallthroughToSemanticEdge() throws {
        let fixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("Features")
            .appendingPathComponent("Terminal")
            .appendingPathComponent("Ghostty")
            .appendingPathComponent("BadTerminalLocalDispositionFallthrough.swift")
            .path

        let diagnostics = try lint(files: [fixture])
            .filter { $0.ruleID == "agentstudio_terminal_local_disposition_publication" }

        #expect(diagnostics.map(\.line) == [9])
        #expect(
            diagnostics.map(\.message) == [
                "GhosttyActionDisposition local-only cases must end in a top-level return before semantic runtime publication"
            ])
    }

    @Test("Terminal local disposition publication rule rejects stored classifier results")
    func terminalLocalDispositionPublicationRuleRejectsStoredClassifierResults() throws {
        let fixture = fixtureRoot()
            .appendingPathComponent("Bad")
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("Features")
            .appendingPathComponent("Terminal")
            .appendingPathComponent("Ghostty")
            .appendingPathComponent("BadTerminalStoredDispositionClassification.swift")
            .path

        let diagnostics = try lint(files: [fixture])
            .filter { $0.ruleID == "agentstudio_terminal_local_disposition_publication" }

        #expect(diagnostics.map(\.line) == [3])
        #expect(
            diagnostics.map(\.message) == [
                "GhosttyActionDisposition.classify results must be consumed directly by a switch"
            ])
    }

    @Test("tooltip source rule scopes raw help to migrated dense controls")
    func tooltipSourceRuleScopesRawHelpToMigratedDenseControls() {
        let migratedDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift",
                source: """
                    import SwiftUI

                    struct DrawerIconBar: View {
                        var body: some View {
                            Button("Add") {}
                                .help("Add drawer pane")
                        }
                    }
                    """
            )
        )
        let sharedSearchDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/SharedComponents/SidebarSearchField.swift",
                source: """
                    import SwiftUI

                    struct SidebarSearchField: View {
                        let clearHelp: String?
                        var body: some View {
                            Button("Clear") {}
                                .help(clearHelp ?? "")
                        }
                    }
                    """
            )
        )

        #expect(migratedDiagnostics.map(\.ruleID) == ["agentstudio_toolbar_tooltip_source"])
        #expect(sharedSearchDiagnostics.isEmpty)
    }

    @Test("tooltip source rule allows non-dense help in migrated files")
    func tooltipSourceRuleAllowsNonDenseHelpInMigratedFiles() {
        let diagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift",
                source: """
                    import SwiftUI

                    struct DrawerIconBar: View {
                        var body: some View {
                            Text("Status")
                                .help("This is explanatory status help")
                        }
                    }
                    """
            )
        )

        #expect(diagnostics.isEmpty)
    }

    @Test("tooltip source rule blocks hover presenter tooltipText label")
    func tooltipSourceRuleBlocksHoverPresenterTooltipTextLabel() {
        let diagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift",
                source: """
                    struct DrawerIconBar {
                        func presenter() {
                            FloatingHoverTooltipPresenter(
                                activeTarget: "add",
                                anchorFrames: [:],
                                availableWidth: 100,
                                tooltipText: { _ in "Add drawer pane" }
                            )
                        }
                    }
                    """
            )
        )

        #expect(diagnostics.map(\.ruleID) == ["agentstudio_toolbar_tooltip_source"])
    }

    @Test("tooltip source rule blocks AppKit tooltip assignment but allows reads")
    func tooltipSourceRuleBlocksAppKitTooltipAssignmentButAllowsReads() {
        let assignmentDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/App/Windows/MainWindowController.swift",
                source: """
                    import AppKit

                    final class MainWindowController {
                        func configure(button: NSButton) {
                            button.toolTip = "Watch folder"
                        }
                    }
                    """
            )
        )
        let noSpaceAssignmentDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/App/Windows/MainWindowController.swift",
                source: """
                    import AppKit

                    final class MainWindowController {
                        func configure(button: NSButton) {
                            button.toolTip="Watch folder"
                        }
                    }
                    """
            )
        )
        let readDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/App/Windows/MainWindowController.swift",
                source: """
                    import AppKit

                    final class MainWindowController {
                        func read(button: NSButton) -> String? {
                            button.toolTip
                        }
                    }
                    """
            )
        )

        #expect(assignmentDiagnostics.map(\.ruleID) == ["agentstudio_toolbar_tooltip_source"])
        #expect(noSpaceAssignmentDiagnostics.map(\.ruleID) == ["agentstudio_toolbar_tooltip_source"])
        #expect(readDiagnostics.isEmpty)
    }

    @Test("tooltip source rule blocks command semantics from render boundaries")
    func tooltipSourceRuleBlocksCommandSemanticsFromRenderBoundaries() {
        let coreDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/Core/Actions/ControlTooltipSource.swift",
                source: """
                    struct BadControlTooltipSource {
                        let commandSpec: AppCommandSpec
                        let privilegeClass: IPCPrivilegeClass
                        let executeParams: IPCCommandExecuteParams
                    }
                    """
            )
        )
        let infrastructureDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/Infrastructure/ControlTooltipRenderValue.swift",
                source: """
                    struct BadControlTooltipRenderValue {
                        let commandIdentifier: IPCCommandIdentifier
                        let commandListResult: IPCCommandListResult
                    }
                    """
            )
        )
        let sharedComponentDiagnostics = TooltipSourceRule().validate(
            context: context(
                path: "Sources/AgentStudio/SharedComponents/BadTooltipComponent.swift",
                source: """
                    import SwiftUI

                    struct BadTooltipComponent: View {
                        let actionSpec: ActionSpec
                        let source: ControlTooltipSource
                        let commandIdentifier: IPCCommandIdentifier
                        let localAction: LocalActionSpec

                        var body: some View { Text("") }
                    }
                    """
            )
        )

        #expect(
            coreDiagnostics.map(\.ruleID) == [
                "agentstudio_toolbar_tooltip_source",
                "agentstudio_toolbar_tooltip_source",
                "agentstudio_toolbar_tooltip_source",
            ])
        #expect(
            infrastructureDiagnostics.map(\.ruleID) == [
                "agentstudio_toolbar_tooltip_source",
                "agentstudio_toolbar_tooltip_source",
            ])
        #expect(
            sharedComponentDiagnostics.map(\.ruleID) == [
                "agentstudio_toolbar_tooltip_source",
                "agentstudio_toolbar_tooltip_source",
                "agentstudio_toolbar_tooltip_source",
                "agentstudio_toolbar_tooltip_source",
            ])
    }

    private func lintFixtureCorpus(_ corpus: String) throws -> [ArchitectureDiagnostic] {
        let corpusRoot = fixtureRoot().appendingPathComponent(corpus)
        let files = try SourceFileDiscovery(fileManager: .default)
            .swiftFiles(under: [corpusRoot.path])
        return try lint(files: files, workspaceRootPath: corpusRoot.path)
    }

    private func lint(
        files: [String],
        workspaceRootPath: String = FileManager.default.currentDirectoryPath
    ) throws -> [ArchitectureDiagnostic] {
        let contexts = try files.map { file in
            let source = try String(contentsOfFile: file, encoding: .utf8)
            return ArchitectureLintContext(
                path: file,
                source: source,
                sourceFile: Parser.parse(source: source),
                workspaceRootPath: workspaceRootPath
            )
        }
        var diagnostics: [ArchitectureDiagnostic] = []
        for rule in ArchitectureRuleRegistry.rules {
            let preparedRule = rule.prepared(for: contexts)
            for context in contexts {
                diagnostics.append(contentsOf: preparedRule.validate(context: context))
            }
        }
        return diagnostics.sorted()
    }

    private func context(path: String, source: String) -> ArchitectureLintContext {
        ArchitectureLintContext(
            path: path,
            source: source,
            sourceFile: Parser.parse(source: source)
        )
    }

    private func fixtureRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }
}
