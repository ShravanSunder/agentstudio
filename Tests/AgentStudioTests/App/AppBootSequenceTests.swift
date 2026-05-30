import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct AppBootSequenceTests {
    @Test("boot sequence exposes the architecture-ordered steps")
    func orderedStepsMatchesArchitectureContract() {
        #expect(
            WorkspaceBootSequence.orderedSteps == [
                .loadCanonicalStore,
                .loadCacheStore,
                .loadUIStore,
                .establishRuntimeBus,
                .startFilesystemActor,
                .startGitProjector,
                .startForgeActor,
                .startCacheCoordinator,
                .triggerInitialTopologySync,
                .armPersistenceObservation,
                .readyForReactiveSidebar,
            ])
    }

    @Test("boot runner executes all steps in declared order")
    func runExecutesOrderedSequence() {
        var recorded: [WorkspaceBootStep] = []
        WorkspaceBootSequence.run { step in
            recorded.append(step)
        }
        #expect(recorded == WorkspaceBootSequence.orderedSteps)
    }

    @Test("every boot step explains why it exists")
    func bootStepsDocumentTheirPurpose() {
        for step in WorkspaceBootSequence.orderedSteps {
            #expect(!step.purpose.isEmpty, "Missing boot purpose for \(step.rawValue)")
        }
    }

    @Test("boot observation step arms every autosaving persistence store")
    func bootObservationStepArmsEveryAutosavingPersistenceStore() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let appDelegateSource = try String(
            contentsOf: projectRoot.appending(path: "Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift"),
            encoding: .utf8
        )

        #expect(appDelegateSource.contains("case .armPersistenceObservation:"))
        #expect(appDelegateSource.contains("bootArmPersistenceObservation()"))
        #expect(appDelegateSource.contains("repoCacheStore.startObserving()"))
        #expect(appDelegateSource.contains("sidebarCacheStore.startObserving()"))
        #expect(appDelegateSource.contains("uiStateStore.startObserving()"))
        #expect(appDelegateSource.contains("assertBootPersistenceObservationArmed()"))
    }

    @Test("production code avoids generic clock-based sleep overloads")
    func productionCodeAvoidsGenericClockBasedSleep() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let sourceRoot = projectRoot.appending(path: "Sources/AgentStudio")
        let sourceFiles =
            FileManager.default
            .enumerator(at: sourceRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var offenders: [String] = []

        for sourceFile in sourceFiles {
            let relativePath = sourceFile.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            guard relativePath != "Sources/AgentStudio/Infrastructure/Extensions/FoundationExtensions.swift" else {
                continue
            }
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for (lineIndex, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where Self.isGenericClockSleep(line) {
                offenders.append("\(relativePath):\(lineIndex + 1): \(line)")
            }
        }

        #expect(
            offenders.isEmpty,
            """
            macOS 26.4 release startup reproduced swift_task_dealloc crashes in the \
            generic clock-based sleep path. Use Duration.nanosecondsForTaskSleep \
            with Task.sleep(nanoseconds:) for production sleeps instead.

            \(offenders.joined(separator: "\n"))
            """
        )
    }

    private static func isGenericClockSleep(_ line: Substring) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard !trimmedLine.hasPrefix("//") else { return false }
        return trimmedLine.contains("Task.sleep(for:")
            || trimmedLine.contains(".sleep(for:")
    }
}
