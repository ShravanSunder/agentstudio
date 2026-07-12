import Foundation
import SwiftParser
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct RuntimeSignalPlaneRuleTests {
    private let ruleID = "agentstudio_runtime_signal_plane"
    private let protectedStateMessage =
        "Admission protected-state regions must use indexed O(1) access or loops bounded by typed lease or cleanup quanta"
    private let protectedRegionTokenMessage =
        "Admission protected-region token must remain noncopyable, borrowed by the wrapper, and unable to return a noncopyable result"
    private let journalLexicalOwnershipMessage =
        "OrderedFactJournal raw state, lock, and protected token access must remain in its lexical owner"
    private let journalOwnerResponsibilityMessage =
        "OrderedFactJournal owner may contain only lexical raw-custody declarations and typed owner entrypoints"

    @Test("Admission protected-state rule rejects uncounted history and declared-slot traversal")
    func rejectsUnboundedProtectedStateTraversal() throws {
        let journalFixture = fixturePath(
            corpus: "Bad",
            fileName: "BadOrderedFactJournalProtectedState.swift"
        )
        let gatherFixture = fixturePath(
            corpus: "Bad",
            fileName: "BadBoundedGatherProtectedState.swift"
        )

        let diagnostics = try lint(files: [journalFixture, gatherFixture])
            .filter { $0.ruleID == ruleID && $0.message == protectedStateMessage }
        let diagnosticsByFileName = Dictionary(grouping: diagnostics) { diagnostic in
            URL(fileURLWithPath: diagnostic.path).lastPathComponent
        }

        #expect(
            diagnosticsByFileName["BadOrderedFactJournalProtectedState.swift"]?.map(\.line)
                == [3]
        )
        #expect(
            diagnosticsByFileName["BadBoundedGatherProtectedState.swift"]?.map(\.line)
                == [5]
        )
        #expect(diagnostics.map(\.message) == [protectedStateMessage, protectedStateMessage])
    }

    @Test("Admission protected-state rule allows indexed access and typed bounded loops")
    func allowsIndexedAndTypedBoundedProtectedStateWork() throws {
        let fixture = fixturePath(
            corpus: "Good",
            fileName: "GoodAdmissionProtectedState.swift"
        )

        let diagnostics = try lint(files: [fixture])
            .filter { $0.ruleID == ruleID }

        #expect(diagnostics.isEmpty)
    }

    @Test("Admission protected-state manifest covers every initial protected category")
    func protectedStateManifestCoversEveryCategory() {
        let manifest = RuntimeSignalPlaneRule.admissionProtectedRegionManifest
        let actualCategories = Set(manifest.map(\.category))
        let expectedCategories = Set(
            RuntimeSignalPlaneRule.AdmissionProtectedRegionCategory.allCases
        )
        let declarationNames = manifest.map(\.declarationName)

        #expect(actualCategories == expectedCategories)
        #expect(Set(declarationNames).count == declarationNames.count)
        #expect(declarationNames.contains("captureReplayState"))
        #expect(declarationNames.contains("diagnostics"))
        #expect(declarationNames.contains("ageMeasurement"))
        #expect(declarationNames.contains("performCleanup"))
        #expect(declarationNames.contains("invalidate"))
    }

    @Test("Admission protected-state rule rejects untyped and non-dominating quantum lookalikes")
    func rejectsQuantumLookalikes() {
        let untypedDiagnostics = validate(
            source: """
                extension BoundedGatherMailbox {
                    func detachCleanup(state: inout State, quantum: Int) {
                        var releasedEntryCount = 0
                        while releasedEntryCount < quantum.maximumEntries {
                            releasedEntryCount += 1
                        }
                    }
                }
                """
        )
        let nonDominatingDiagnostics = validate(
            source: """
                extension BoundedGatherMailbox {
                    func detachCleanup(
                        state: inout State,
                        quantum: AdmissionCleanupQuantum
                    ) {
                        var releasedEntryCount = 0
                        while quantum.maximumEntries < releasedEntryCount {
                            releasedEntryCount += 1
                        }
                    }
                }
                """
        )

        #expect(untypedDiagnostics.map(\.line) == [4])
        #expect(nonDominatingDiagnostics.map(\.line) == [7])
    }

    @Test("Admission protected-state rule permits replay materialization after the lock capture")
    func permitsPostLockReplayMaterialization() {
        let diagnostics = validate(
            source: """
                func replay(capture: ReplayCapture) -> [SequencedFact<Fact>] {
                        return capture.nodes.map(\\.sequencedFact)
                }
                """
        )

        #expect(diagnostics.isEmpty)
    }

    @Test("Admission protected-region token shape remains stable-language and noncopyable")
    func enforcesProtectedRegionTokenShape() throws {
        let goodFixture = fixturePath(
            corpus: "Good",
            fileName: "GoodAdmissionProtectedRegionTokenShape.swift"
        )
        let badFixtures = [
            "BadCopyableAdmissionProtectedRegionToken.swift",
            "BadUnborrowedAdmissionProtectedRegionToken.swift",
            "BadNoncopyableAdmissionProtectedRegionResult.swift",
        ].map { fixturePath(corpus: "Bad", fileName: $0) }

        let goodDiagnostics = try lint(files: [goodFixture])
            .filter { $0.ruleID == ruleID }
        let badDiagnostics = try lint(files: badFixtures)
            .filter { $0.ruleID == ruleID }

        #expect(goodDiagnostics.isEmpty)
        #expect(badDiagnostics.count == 3)
        #expect(badDiagnostics.map(\.message) == Array(repeating: protectedRegionTokenMessage, count: 3))
    }

    @Test("Journal lexical ownership follows arbitrary Admission files and local type aliases")
    func rejectsJournalRawAccessOutsideOwner() throws {
        let fixtures = [
            "UnexpectedTelemetryVocabulary.swift",
            "BadAliasedOrderedFactJournalEscape.swift",
        ].map { fixturePath(corpus: "Bad", fileName: $0) }

        let diagnostics = try lint(files: fixtures)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.count == 2)
        #expect(
            Set(diagnostics.map { URL(fileURLWithPath: $0.path).lastPathComponent })
                == Set(["UnexpectedTelemetryVocabulary.swift", "BadAliasedOrderedFactJournalEscape.swift"])
        )
    }

    @Test("Journal owner rejects external responsibility declarations")
    func rejectsNonCustodyResponsibilitiesInJournalOwner() throws {
        let fixtures = [
            "BadJournalOwnerPortDeclaration.swift",
            "BadJournalOwnerPublicContract.swift",
            "BadJournalOwnerPureMechanic.swift",
            "BadJournalOwnerReplayMaterializer.swift",
        ].map { fixturePath(corpus: "Bad", fileName: $0) }

        let diagnostics = try lint(files: fixtures)
            .filter { $0.ruleID == ruleID && $0.message == journalOwnerResponsibilityMessage }

        #expect(diagnostics.count == 4)
        #expect(Set(diagnostics.map(\.line)) == Set([4]))
    }

    @Test("Journal ownership allows the owner shape and other Admission family vocabulary")
    func allowsJournalOwnerAndOtherFamilyRawVocabulary() throws {
        let fixtures = [
            "GoodOrderedFactJournalLexicalOwner.swift",
            "GoodOtherAdmissionFamilyRawOwner.swift",
        ].map { fixturePath(corpus: "Good", fileName: $0) }

        let diagnostics = try lint(files: fixtures)
            .filter { $0.ruleID == ruleID }

        #expect(diagnostics.isEmpty)
    }

    @Test("Journal aliases resolve across files without diagnosing raw-free alias declarations")
    func resolvesJournalAliasesAcrossFiles() throws {
        let goodFixtures = [
            "GoodOrderedFactJournalAliasDeclaration.swift",
            "GoodOrderedFactJournalAliasConsumer.swift",
        ].map { fixturePath(corpus: "Good", fileName: $0) }
        let badFixtures = [
            "BadOrderedFactJournalAliasDeclaration.swift",
            "BadOrderedFactJournalAliasConsumers.swift",
        ].map { fixturePath(corpus: "Bad", fileName: $0) }

        let goodDiagnostics = try lint(files: goodFixtures)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }
        let badDiagnostics = try lint(files: badFixtures)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(goodDiagnostics.isEmpty)
        #expect(badDiagnostics.count == 3)
        #expect(
            Set(badDiagnostics.map { URL(fileURLWithPath: $0.path).lastPathComponent })
                == Set(["BadOrderedFactJournalAliasConsumers.swift"])
        )
        #expect(badDiagnostics.map(\.line) == [3, 5, 13])
    }

    @Test("Journal direct token signatures are rejected at every lexical depth")
    func rejectsNestedJournalTokenConsumers() throws {
        let goodFixture = fixturePath(
            corpus: "Good",
            fileName: "GoodNestedJournalStorage.swift"
        )
        let badFixture = fixturePath(
            corpus: "Bad",
            fileName: "BadNestedJournalTokenConsumers.swift"
        )

        let goodDiagnostics = try lint(files: [goodFixture])
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }
        let badDiagnostics = try lint(files: [badFixture])
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(goodDiagnostics.isEmpty)
        #expect(badDiagnostics.map(\.line) == [2, 4, 13, 15])
    }

    @Test("Journal aliases retain qualified namespace and lexical identity")
    func resolvesQualifiedJournalAliasesWithoutBasenameContamination() throws {
        let files = workspaceFixturePaths(name: "QualifiedAliases")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.count == 2)
        #expect(
            Set(diagnostics.map { URL(fileURLWithPath: $0.path).lastPathComponent })
                == Set(["AliasConsumers.swift"])
        )
        #expect(diagnostics.map(\.line) == [9, 36])
    }

    @Test("Journal direct signature classification covers initializers and subscripts")
    func rejectsInitializerAndSubscriptJournalTokenConsumers() throws {
        let files = workspaceFixturePaths(name: "DirectSignatures")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [2, 10])
    }

    @Test("Journal aliases resolve relative qualified names before global collisions")
    func resolvesRelativeQualifiedJournalAliases() throws {
        let files = workspaceFixturePaths(name: "RelativeAliases")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.count == 1)
        #expect(
            URL(fileURLWithPath: diagnostics[0].path).lastPathComponent
                == "RelativeAliasConsumers.swift"
        )
        #expect(diagnostics.map(\.line) == [3])
    }

    @Test("Journal aliases remain isolated across executable lexical scopes")
    func isolatesExecutableScopeAliases() throws {
        let files = workspaceFixturePaths(name: "LocalScopes")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [7, 17])
    }

    @Test("Journal namespace aliases resolve in extension targets")
    func resolvesNamespaceAliasesInExtensionTargets() throws {
        let files = workspaceFixturePaths(name: "NamespaceExtensionAlias")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [2])
    }

    @Test("Protected token aliases and lexical shadows resolve by identity")
    func resolvesProtectedTokenAliasesAndShadows() throws {
        let files = workspaceFixturePaths(name: "TokenAliases")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [1, 10, 12, 21, 51])
    }

    @Test("AgentStudio module-qualified journal and token identities retain enforcement")
    func recognizesAgentStudioModuleQualifiedJournalAndToken() throws {
        let files = workspaceFixturePaths(name: "ModuleQualified")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        let diagnosticsByFile = Dictionary(grouping: diagnostics) {
            URL(fileURLWithPath: $0.path).lastPathComponent
        }
        #expect(
            diagnosticsByFile["ModuleQualifiedConsumers.swift"]?.map(\.line)
                == [1, 10, 18, 48]
        )
        #expect(
            diagnosticsByFile["ModuleQualifiedTokenConsumers.swift"]?.map(\.line)
                == [1, 10, 12, 21, 33, 41]
        )
        #expect(
            diagnosticsByFile["ModuleQualifiedTokenNamespaceAliasConsumers.swift"]?.map(\.line)
                == [7]
        )
    }

    @Test("Executable branch clauses isolate aliases while preserving same-branch resolution")
    func isolatesExecutableBranchAliases() throws {
        let files = workspaceFixturePaths(name: "BranchScopes")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [8, 18, 35, 45])
    }

    @Test("Journal extension State matching remains identity aware")
    func distinguishesOtherStateFromJournalState() throws {
        let files = workspaceFixturePaths(name: "OtherState")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [7, 13, 15, 29])
    }

    @Test("Raw lock aliases and lexical shadows resolve by identity")
    func resolvesRawLockAliasesAndShadows() throws {
        let files = workspaceFixturePaths(name: "RawLockIdentity")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        #expect(diagnostics.map(\.line) == [3, 9])
    }

    @Test("Generic parameters shadow protected identities throughout their lexical scope")
    func recognizesGenericParameterShadowsAndCanonicalControls() throws {
        let files = workspaceFixturePaths(name: "GenericParameterShadows")

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID && $0.message == journalLexicalOwnershipMessage }

        let diagnosticsByFile = Dictionary(grouping: diagnostics) {
            URL(fileURLWithPath: $0.path).lastPathComponent
        }
        #expect(diagnosticsByFile["CleanGenericParameterShadows.swift"] == nil)
        #expect(diagnosticsByFile["CanonicalGenericParameterControls.swift"]?.map(\.line) == [1, 9, 15])
    }

    @Test("Journal ownership scans the dynamically discovered production Admission inventory")
    func scansProductionAdmissionInventory() throws {
        let admissionDirectory = projectRoot()
            .appending(path: "Sources/AgentStudio/Core/RuntimeEventSystem/Admission")
        let files = try SourceFileDiscovery(fileManager: .default)
            .swiftFiles(under: [admissionDirectory.path])

        let diagnostics = try lint(files: files)
            .filter { $0.ruleID == ruleID }
        let ownerCount = try files.reduce(into: 0) { count, file in
            let source = try String(contentsOfFile: file, encoding: .utf8)
            let sourceFile = Parser.parse(source: source)
            if RuntimeSignalPlaneRule.containsTopLevelOrderedFactJournalOwner(
                in: sourceFile
            ) {
                count += 1
            }
        }

        #expect(files.isEmpty == false)
        #expect(
            files.contains {
                URL(fileURLWithPath: $0).lastPathComponent == "OrderedFactJournal.swift"
            }
        )
        #expect(ownerCount == 1)
        #expect(diagnostics.isEmpty)
    }

    private func fixturePath(corpus: String, fileName: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(corpus)
            .appendingPathComponent("Sources")
            .appendingPathComponent("AgentStudio")
            .appendingPathComponent("Core")
            .appendingPathComponent("RuntimeEventSystem")
            .appendingPathComponent("Admission")
            .appendingPathComponent(fileName)
            .path
    }

    private func projectRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.lastPathComponent != "Tools" {
            directory.deleteLastPathComponent()
        }
        return directory.deletingLastPathComponent()
    }

    private func workspaceFixturePaths(name: String) -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Workspace")
            .appendingPathComponent(name)
        return try! SourceFileDiscovery(fileManager: .default).swiftFiles(under: [root.path])
    }

    private func lint(files: [String]) throws -> [ArchitectureDiagnostic] {
        let workspaceRootPath = fixtureOrProjectWorkspaceRoot(for: files)
        let contexts = try files.map { file in
            let source = try String(contentsOfFile: file, encoding: .utf8)
            return ArchitectureLintContext(
                path: file,
                source: source,
                sourceFile: Parser.parse(source: source),
                workspaceRootPath: workspaceRootPath,
                enforcesProductionAdmissionOwnerCardinality: false
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

    private func fixtureOrProjectWorkspaceRoot(for files: [String]) -> String {
        guard let firstFile = files.first else { return projectRoot().path }
        let marker = "/Sources/AgentStudio/"
        guard let markerRange = firstFile.range(of: marker) else {
            return projectRoot().path
        }
        return String(firstFile[..<markerRange.lowerBound])
    }

    private func validate(source: String) -> [ArchitectureDiagnostic] {
        let path =
            "Sources/AgentStudio/Core/RuntimeEventSystem/Admission/RuntimeSignalPlaneFixture.swift"
        let context = ArchitectureLintContext(
            path: path,
            source: source,
            sourceFile: Parser.parse(source: source),
            enforcesProductionAdmissionOwnerCardinality: false
        )
        let rule = RuntimeSignalPlaneRule().prepared(for: [context])
        return rule.validate(context: context).sorted()
    }
}
