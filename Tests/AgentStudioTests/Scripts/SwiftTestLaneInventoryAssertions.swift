import AgentStudioTestSupport
import Foundation
import Testing

enum SwiftTestLaneInventoryAssertions {
    static func assertCompleteAndDisjoint() async throws {
        let rows = try await readInventoryRows()
        try assertInventoryRowsExistAndCoverRealProcessSuites(rows)
        let filters = try await readLaneFilterPatterns()
        assertGeneratedSelectorsAssignEachListedTypeOnce(rows, filters: filters)
        assertUnlistedOrdinarySuitesStayFast(filters)
        try assertKnownSuiteLaneOwners(rows)
        try await assertLargeProcessGlobalRowsMatchTheInventory(rows)
    }

    private static func readInventoryRows() async throws -> [SuiteLaneInventoryRow] {
        let inventoryOutput = try await runBash(
            "source scripts/swift-test-helpers.sh\n"
                + "swift_test_suite_lane_inventory"
        )
        return
            try inventoryOutput
            .split(whereSeparator: \.isNewline)
            .map { line -> SuiteLaneInventoryRow in
                let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 3 else {
                    throw SwiftLaneInventoryAssertionsError.malformedRow(String(line))
                }
                return SuiteLaneInventoryRow(lane: fields[0], suiteTypePath: fields[1], mode: fields[2])
            }
    }

    private static func assertInventoryRowsExistAndCoverRealProcessSuites(
        _ rows: [SuiteLaneInventoryRow]
    ) throws {
        let suitePaths = rows.map(\.suiteTypePath)
        let allowedLanes: Set<String> = ["fast", "large", "webkit", "e2e", "zmx", "benchmark"]
        let allowedModes: Set<String> = ["concurrent", "serial", "process-global"]
        #expect(Set(suitePaths).count == rows.count, "every suite type path must occur exactly once")
        #expect(rows.allSatisfy { allowedLanes.contains($0.lane) })
        #expect(rows.allSatisfy { allowedModes.contains($0.mode) })

        let sourceFiles = try swiftTestSourceFiles()
        let declaredTypes = Set(try sourceFiles.flatMap(swiftTypeDeclarations(in:)))
        let inventoryTypeNames = Set(rows.map(\.suiteTypeName))
        #expect(inventoryTypeNames.isSubset(of: declaredTypes), "every inventory type must exist in Swift test source")

        let realProcessSuffixes = ["IntegrationTests", "ScriptTests", "SmokeTests"]
        let sourceSuiteTypes = Set(try sourceFiles.flatMap(swiftSuiteTypeDeclarations(in:)))
        let requiredTypes = Set(
            sourceSuiteTypes.filter { suiteType in
                realProcessSuffixes.contains(where: suiteType.hasSuffix)
            })
        #expect(
            requiredTypes.isSubset(of: inventoryTypeNames),
            "every IntegrationTests, ScriptTests, and SmokeTests suite needs an explicit inventory row"
        )
    }

    private static func readLaneFilterPatterns() async throws -> LaneFilterPatterns {
        let filterOutput = try await runBash(
            "source scripts/swift-test-helpers.sh\n"
                + "for lane in fast large webkit e2e zmx benchmark; do\n"
                + "  printf 'FILTER\\t%s\\t%s\\n' \"$lane\" \"$(swift_test_lane_filter_pattern \"$lane\")\"\n"
                + "  printf 'EXCLUDE\\t%s\\t%s\\n' \"$lane\" \"$(swift_test_lane_filter_exclusion_pattern \"$lane\")\"\n"
                + "done\n"
                + "printf 'FAST_SKIP\\t%s\\n' \"$(fast_non_webkit_skip_pattern)\"\n"
                + "printf 'UNLISTED_LANE\\t%s\\n' \"$(swift_test_lane_for_suite_type UnlistedOrdinaryUnitTests)\""
        )
        var laneFilters: [String: String] = [:]
        var laneExclusions: [String: String] = [:]
        var fastSkipPattern = ""
        var unlistedLane = ""

        for line in filterOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let kind = fields.first else { continue }
            switch kind {
            case "FILTER" where fields.count == 3:
                laneFilters[fields[1]] = fields[2]
            case "EXCLUDE" where fields.count == 3:
                laneExclusions[fields[1]] = fields[2]
            case "FAST_SKIP" where fields.count == 2:
                fastSkipPattern = fields[1]
            case "UNLISTED_LANE" where fields.count == 2:
                unlistedLane = fields[1]
            default:
                throw SwiftLaneInventoryAssertionsError.malformedRow(String(line))
            }
        }

        for laneName in Self.laneNames {
            #expect(laneFilters[laneName] != nil, "missing generated filter for lane \(laneName)")
            #expect(laneExclusions[laneName] != nil, "missing generated exclusions for lane \(laneName)")
        }
        return LaneFilterPatterns(
            laneFilters: laneFilters,
            laneExclusions: laneExclusions,
            fastSkipPattern: fastSkipPattern,
            unlistedLane: unlistedLane
        )
    }

    private static func assertGeneratedSelectorsAssignEachListedTypeOnce(
        _ rows: [SuiteLaneInventoryRow],
        filters: LaneFilterPatterns
    ) {
        for row in rows {
            let suiteIdentifier = "AgentStudioTests.\(row.suiteTypePath)/laneInventoryProbe()"
            let selectedLanes = Self.laneNames.filter { laneName in
                matchesSuiteFilter(filters.laneFilters[laneName] ?? "", suiteIdentifier)
                    && !matchesSuiteFilter(filters.laneExclusions[laneName] ?? "", suiteIdentifier)
            }
            #expect(
                selectedLanes == [row.lane],
                "\(row.suiteTypePath) belongs to \(row.lane), generated selectors chose \(selectedLanes)"
            )
            let shouldSkipFastConcurrentPhase = row.lane != "fast" || row.mode != "concurrent"
            #expect(
                matchesSuiteFilter(filters.fastSkipPattern, suiteIdentifier) == shouldSkipFastConcurrentPhase,
                "fast concurrent exclusions drifted for \(row.suiteTypePath)"
            )
        }
    }

    private static func assertUnlistedOrdinarySuitesStayFast(_ filters: LaneFilterPatterns) {
        let suiteIdentifier = "AgentStudioTests.UnlistedOrdinaryUnitTests/unlistedCase()"
        #expect(filters.unlistedLane == "fast", "unlisted ordinary suite types default to fast")
        #expect(!matchesSuiteFilter(filters.fastSkipPattern, suiteIdentifier))
        for laneName in Self.laneNames where laneName != "fast" {
            #expect(!matchesSuiteFilter(filters.laneFilters[laneName] ?? "", suiteIdentifier))
        }
    }

    private static func assertKnownSuiteLaneOwners(_ rows: [SuiteLaneInventoryRow]) throws {
        let lightweightFastTypes: Set<String> = [
            "AgentStudioFileViewStartupDiagnosticTests",
            "AgentStudioStartupDiagnosticActionParsingTests",
            "AgentStudioStartupDiagnosticActionTests",
            "AgentStudioTraceConfigurationTests",
            "BridgePaneSurfaceSelectionContractTests",
            "BridgeProductSessionContractTests",
            "BridgeReviewFileClassifierTests",
            "WebInteractionManagementScriptTests",
        ]
        for suiteTypeName in lightweightFastTypes {
            let row = try #require(rows.first { $0.suiteTypeName == suiteTypeName })
            #expect(row.lane == "fast")
            #expect(row.mode == "concurrent")
        }

        let filesystemRemoteRow = try #require(rows.first { $0.suiteTypeName == "FilesystemGitRemoteReferenceTests" })
        #expect(filesystemRemoteRow.lane == "fast")
        #expect(filesystemRemoteRow.mode == "process-global")
        #expect(try #require(rows.first { $0.suiteTypeName == "BridgeWorktreeRefreshSessionTests" }).lane == "large")
        #expect(try #require(rows.first { $0.suiteTypePath == "WebKitSerializedTests" }).lane == "webkit")
        #expect(try #require(rows.first { $0.suiteTypePath == "E2ESerializedTests" }).lane == "e2e")
        #expect(try #require(rows.first { $0.suiteTypePath == "E2ESerializedTests/ZmxE2ETests" }).lane == "zmx")
        #expect(
            try #require(rows.first { $0.suiteTypeName == "GlobalPreferencesBootstrapBenchmarkTests" }).lane
                == "benchmark")
        #expect(
            try #require(rows.first { $0.suiteTypeName == "RepoExplorerNativeTablePilotBenchmarkTests" }).lane
                == "benchmark")
    }

    private static func assertLargeProcessGlobalRowsMatchTheInventory(
        _ rows: [SuiteLaneInventoryRow]
    ) async throws {
        let output = try await runBash(
            "source scripts/swift-test-helpers.sh\n"
                + "large_process_global_suite_filters"
        )
        let expected = Set(rows.filter { $0.lane == "large" && $0.mode == "process-global" }.map(\.suiteTypePath))
        #expect(Set(output.split(whereSeparator: \.isNewline).map(String.init)) == expected)
    }

    private static let laneNames: [String] = ["fast", "large", "webkit", "e2e", "zmx", "benchmark"]
}

private struct SuiteLaneInventoryRow {
    let lane: String
    let suiteTypePath: String
    let mode: String

    var suiteTypeName: String {
        suiteTypePath.split(separator: "/").last.map(String.init) ?? suiteTypePath
    }
}

private struct LaneFilterPatterns {
    let laneFilters: [String: String]
    let laneExclusions: [String: String]
    let fastSkipPattern: String
    let unlistedLane: String
}

private enum SwiftLaneInventoryAssertionsError: Error {
    case malformedRow(String)
}

private func swiftTestSourceFiles() throws -> [String] {
    let testsRoot = URL(fileURLWithPath: "Tests", isDirectory: true)
    let fileEnumerator = FileManager.default.enumerator(
        at: testsRoot,
        includingPropertiesForKeys: [.isRegularFileKey]
    )
    var sourceFiles: [String] = []

    while let fileURL = fileEnumerator?.nextObject() as? URL {
        guard fileURL.pathExtension == "swift" else { continue }
        sourceFiles.append(try String(contentsOf: fileURL, encoding: .utf8))
    }

    return sourceFiles
}

private func swiftTypeDeclarations(in source: String) throws -> [String] {
    let declarationPattern = try NSRegularExpression(
        pattern:
            #"(?m)^\s*(?:(?:public|package|internal|private|fileprivate|final|open|indirect)\s+)*(?:struct|class)\s+([A-Za-z0-9_]+)\b"#
    )
    let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

    return declarationPattern.matches(in: source, range: fullRange).compactMap { match in
        guard let nameRange = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[nameRange])
    }
}

private func swiftSuiteTypeDeclarations(in source: String) throws -> [String] {
    let declarationPattern = try NSRegularExpression(
        pattern:
            #"^\s*(?:(?:public|package|internal|private|fileprivate|final|open|indirect)\s+)*(?:struct|class)\s+([A-Za-z0-9_]+)\b"#
    )
    let sourceLines = source.components(separatedBy: .newlines)
    var suiteTypeNames: [String] = []

    for lineIndex in sourceLines.indices {
        let line = sourceLines[lineIndex]
        let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let declaration = declarationPattern.firstMatch(in: line, range: lineRange),
            let nameRange = Range(declaration.range(at: 1), in: line)
        else {
            continue
        }

        let attributeStartIndex = max(sourceLines.startIndex, lineIndex - 12)
        let precedingLines = sourceLines[attributeStartIndex..<lineIndex].joined(separator: "\n")
        guard precedingLines.contains("@Suite") else { continue }
        suiteTypeNames.append(String(line[nameRange]))
    }

    return suiteTypeNames
}

private func matchesSuiteFilter(_ pattern: String, _ suiteIdentifier: String) -> Bool {
    guard !pattern.isEmpty,
        let expression = try? NSRegularExpression(pattern: pattern)
    else {
        return false
    }
    let fullRange = NSRange(suiteIdentifier.startIndex..<suiteIdentifier.endIndex, in: suiteIdentifier)
    return expression.firstMatch(in: suiteIdentifier, range: fullRange) != nil
}
