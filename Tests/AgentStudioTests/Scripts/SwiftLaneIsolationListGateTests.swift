import AgentStudioTestSupport
import Foundation
import Testing

/// The set of suites that need a process of their own is half discovered and
/// half hand-kept: `aggregate_serial_non_webkit_suite_filters` unions a regex
/// scan for `@MainActor` + `@Suite(.serialized)` types with an explicit list of
/// `path:Suite` pairs. Test correctness depends on that list, and nothing stopped
/// a member from silently falling out of it — a suite absent from the list beside
/// its listed sibling is one of the diagnosed CI failure families.
///
/// This suite is that gate (spec R13). It checks the hand-kept half still points
/// at real declarations, and that every suite marked process-global lands in some
/// isolated lane rather than in the concurrent fast inventory.
@Suite("Swift lane isolation list gate")
struct SwiftLaneIsolationListGateTests {
    @Test("every hand-kept isolation entry points at a real suite declaration")
    func everyHandKeptIsolationEntryPointsAtRealSuiteDeclaration() throws {
        let helperScript = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let aggregateFunction = try shellFunctionBody(
            named: "aggregate_serial_non_webkit_suite_filters",
            in: helperScript
        )
        let largeFunction = try shellFunctionBody(
            named: "large_process_global_suite_filters",
            in: helperScript
        )
        let handKeptEntries =
            explicitSuitePathPairs(in: aggregateFunction) + explicitSuitePathPairs(in: largeFunction)

        #expect(handKeptEntries.count >= 20)
        for entry in handKeptEntries {
            #expect(
                FileManager.default.fileExists(atPath: entry.sourcePath),
                "Stale isolation entry: \(entry.sourcePath):\(entry.suiteName) names a file that no longer exists"
            )
            guard let source = try? String(contentsOfFile: entry.sourcePath, encoding: .utf8) else {
                continue
            }
            #expect(
                declaresType(named: entry.suiteName, in: source),
                "Stale isolation entry: \(entry.sourcePath) no longer declares \(entry.suiteName)"
            )
        }
    }

    @Test("every serialized MainActor suite runs in an isolated lane")
    func everySerializedMainActorSuiteRunsInAnIsolatedLane() async throws {
        let isolatedSuiteNames = try await isolatedLaneSuiteNames()

        for suite in try discoveredSerializedMainActorSuites() {
            guard !isolatedSuiteNames.contains(suite.name) else { continue }
            #expect(
                suite.isRoutedOnDedicatedLane,
                """
                \(suite.name) (\(suite.sourcePath)) is marked @MainActor + @Suite(.serialized) but appears in no \
                isolated lane inventory. Add it to the lane it belongs to in scripts/swift-test-helpers.sh, or it \
                runs inside the concurrent fast inventory beside the process-global state it shares.
                """
            )
        }
    }

    @Test("E2E and zmx name substrings do not skip isolation without a dedicated-lane parent")
    func e2eAndZmxNameSubstringsDoNotSkipIsolationWithoutDedicatedLaneParent() {
        let nested = serializedMainActorSuites(
            in: [
                "extension E2ESerializedTests {",
                "@MainActor",
                "@Suite(.serialized)",
                "struct FilesystemSourceE2ETests {}",
                "}",
            ].joined(separator: "\n")
        )
        #expect(nested.map(\.name) == ["FilesystemSourceE2ETests"])
        #expect(nested.first?.enclosingTypeNames == ["E2ESerializedTests"])
        #expect(nested.first?.isRoutedOnDedicatedLane == true)

        let zmxChild = serializedMainActorSuites(
            in: [
                "extension E2ESerializedTests {",
                "@Suite(.serialized)",
                "@MainActor",
                "struct ZmxBackendIntegrationTests {}",
                "}",
            ].joined(separator: "\n")
        )
        #expect(zmxChild.first?.isRoutedOnDedicatedLane == true)

        let standalone = serializedMainActorSuites(
            in: [
                "@MainActor",
                "@Suite(.serialized)",
                "struct NewE2ETests {}",
            ].joined(separator: "\n")
        )
        #expect(standalone.map(\.name) == ["NewE2ETests"])
        #expect(standalone.first?.enclosingTypeNames.isEmpty == true)
        #expect(standalone.first?.isRoutedOnDedicatedLane == false)

        let zmxSubstring = serializedMainActorSuites(
            in: [
                "@MainActor",
                "@Suite(\"Workspace SQLite zmx session ID storage\", .serialized)",
                "struct WorkspaceSQLiteZmxSessionIDStorageTests {}",
            ].joined(separator: "\n")
        )
        #expect(zmxSubstring.first?.isRoutedOnDedicatedLane == false)
    }

    // MARK: - Lane inventories

    /// Every suite name some isolated lane claims: the aggregate process-global
    /// phase, the large process-global phase, the serial large process phase, and
    /// the WebKit lane. Read from the helper script's own functions so the gate
    /// cannot drift from the runner.
    private func isolatedLaneSuiteNames() async throws -> Set<String> {
        var names: Set<String> = []
        for helperFunction in [
            "aggregate_serial_non_webkit_suite_filters",
            "large_process_global_suite_filters",
            "webkit_leaf_suite_filters",
        ] {
            names.formUnion(try await shellHelperLines(helperFunction))
        }
        names.formUnion(
            try await shellHelperLines("large_serial_non_webkit_filter_pattern")
                .flatMap { $0.components(separatedBy: "|") }
        )
        return names
    }

    // MARK: - Independent discovery

    private struct DiscoveredSuite {
        let name: String
        let sourcePath: String
        let enclosingTypeNames: [String]

        /// The runner skips `E2ESerializedTests` and `ZmxE2ETests` by those exact
        /// type names; nested children inherit that skip. A substring such as
        /// `NewE2ETests` is not a dedicated lane.
        var isRoutedOnDedicatedLane: Bool {
            Self.isRoutedOnDedicatedLane(name: name, enclosingTypeNames: enclosingTypeNames)
        }

        static func isRoutedOnDedicatedLane(name: String, enclosingTypeNames: [String]) -> Bool {
            let dedicatedLaneSuites: Set<String> = ["E2ESerializedTests", "ZmxE2ETests"]
            if dedicatedLaneSuites.contains(name) {
                return true
            }
            if enclosingTypeNames.contains(where: dedicatedLaneSuites.contains) {
                return true
            }
            return [
                "GlobalPreferencesBootstrapBenchmarkTests",
                "RepoExplorerNativeTablePilotBenchmarkTests",
            ].contains(name)
        }
    }

    /// Scans `Tests/` for types carrying both `@MainActor` and a `@Suite(...)`
    /// with the `.serialized` trait, in either attribute order and across
    /// formatted multi-line arguments.
    ///
    /// Deliberately independent of the helper script's perl patterns: a gate that
    /// reused them could not catch a suite those patterns fail to see.
    private func discoveredSerializedMainActorSuites() throws -> [DiscoveredSuite] {
        var discovered: [DiscoveredSuite] = []
        let testsRoot = URL(fileURLWithPath: "Tests", isDirectory: true)
        guard
            let enumerator = FileManager.default.enumerator(
                at: testsRoot,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relativePath =
                fileURL.path.hasPrefix(FileManager.default.currentDirectoryPath + "/")
                ? String(fileURL.path.dropFirst(FileManager.default.currentDirectoryPath.count + 1))
                : fileURL.path
            for suite in serializedMainActorSuites(in: source) {
                discovered.append(
                    DiscoveredSuite(
                        name: suite.name,
                        sourcePath: relativePath,
                        enclosingTypeNames: suite.enclosingTypeNames
                    )
                )
            }
        }
        return discovered
    }

    private struct SerializedMainActorSuite {
        let name: String
        let enclosingTypeNames: [String]

        var isRoutedOnDedicatedLane: Bool {
            DiscoveredSuite.isRoutedOnDedicatedLane(name: name, enclosingTypeNames: enclosingTypeNames)
        }
    }

    /// Attribute lines accumulate until a declaration consumes them; anything
    /// else clears them, so a nested type inside a serialized suite is not
    /// mistaken for the suite. Brace depth tracks `extension` / type parents so
    /// dedicated-lane membership is the enclosing type, not a name substring.
    private func serializedMainActorSuites(in source: String) -> [SerializedMainActorSuite] {
        var suiteNames: [SerializedMainActorSuite] = []
        var pendingAttributes = ""
        var openParenthesisDepth = 0
        var enclosingTypes: [(name: String, braceDepth: Int)] = []
        var braceDepth = 0

        for line in source.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if openParenthesisDepth > 0 {
                pendingAttributes += "\n" + trimmedLine
                openParenthesisDepth += parenthesisDelta(in: trimmedLine)
                braceDepth += braceDelta(in: trimmedLine)
                popClosedEnclosingTypes(
                    enclosingTypes: &enclosingTypes,
                    braceDepth: braceDepth
                )
                continue
            }
            if trimmedLine.hasPrefix("@") {
                pendingAttributes += "\n" + trimmedLine
                openParenthesisDepth = max(0, parenthesisDelta(in: trimmedLine))
                continue
            }
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") {
                braceDepth += braceDelta(in: trimmedLine)
                popClosedEnclosingTypes(
                    enclosingTypes: &enclosingTypes,
                    braceDepth: braceDepth
                )
                continue
            }
            let attributes = pendingAttributes
            pendingAttributes = ""
            if let declaredTypeName = declaredTypeName(in: trimmedLine) {
                if attributes.contains("@MainActor"), declaresSerializedSuite(in: attributes) {
                    suiteNames.append(
                        SerializedMainActorSuite(
                            name: declaredTypeName,
                            enclosingTypeNames: enclosingTypes.map(\.name)
                        )
                    )
                }
                enclosingTypes.append((declaredTypeName, braceDepth))
            } else if let extensionName = declaredExtensionName(in: trimmedLine) {
                enclosingTypes.append((extensionName, braceDepth))
            }
            braceDepth += braceDelta(in: trimmedLine)
            popClosedEnclosingTypes(
                enclosingTypes: &enclosingTypes,
                braceDepth: braceDepth
            )
        }
        return suiteNames
    }

    private func popClosedEnclosingTypes(
        enclosingTypes: inout [(name: String, braceDepth: Int)],
        braceDepth: Int
    ) {
        while let last = enclosingTypes.last, braceDepth <= last.braceDepth {
            enclosingTypes.removeLast()
        }
    }

    private func braceDelta(in line: String) -> Int {
        line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
    }

    private func declaredExtensionName(in line: String) -> String? {
        guard let keywordRange = line.range(of: "extension ") else {
            return nil
        }
        let identifier = line[keywordRange.upperBound...]
            .prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return identifier.isEmpty ? nil : String(identifier)
    }

    private func parenthesisDelta(in line: String) -> Int {
        line.filter { $0 == "(" }.count - line.filter { $0 == ")" }.count
    }

    /// `.serialized` as a whole trait, never the `.serializedIfSupported` prefix.
    private func declaresSerializedSuite(in attributes: String) -> Bool {
        guard attributes.contains("@Suite") else { return false }
        var searchRange = attributes.startIndex..<attributes.endIndex
        while let traitRange = attributes.range(of: ".serialized", range: searchRange) {
            searchRange = traitRange.upperBound..<attributes.endIndex
            guard traitRange.upperBound < attributes.endIndex else { return true }
            let nextCharacter = attributes[traitRange.upperBound]
            if !nextCharacter.isLetter, !nextCharacter.isNumber, nextCharacter != "_" {
                return true
            }
        }
        return false
    }

    private func declaredTypeName(in line: String) -> String? {
        for keyword in ["struct ", "final class ", "class ", "actor ", "enum "] {
            guard let keywordRange = line.range(of: keyword) else { continue }
            let prefix = line[line.startIndex..<keywordRange.lowerBound]
            guard prefix.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "(" || $0 == ")" }) else {
                continue
            }
            let identifier = line[keywordRange.upperBound...]
                .prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            return identifier.isEmpty ? nil : String(identifier)
        }
        return nil
    }

    private func declaresType(named typeName: String, in source: String) -> Bool {
        for keyword in ["struct", "class", "actor", "enum"] {
            var searchRange = source.startIndex..<source.endIndex
            while let range = source.range(of: "\(keyword) \(typeName)", range: searchRange) {
                searchRange = range.upperBound..<source.endIndex
                guard range.upperBound < source.endIndex else { return true }
                let nextCharacter = source[range.upperBound]
                if !nextCharacter.isLetter, !nextCharacter.isNumber, nextCharacter != "_" {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Shell helpers

    private struct HandKeptIsolationEntry {
        let sourcePath: String
        let suiteName: String
    }

    /// The `printf '%s:%s\n' 'path' 'Suite'` pairs a helper function hand-maintains.
    private func explicitSuitePathPairs(in functionBody: String) -> [HandKeptIsolationEntry] {
        var entries: [HandKeptIsolationEntry] = []
        let lines = functionBody.components(separatedBy: "\n")
        var lineIndex = 0
        while lineIndex < lines.count {
            guard lines[lineIndex].contains("printf '%s:%s") else {
                lineIndex += 1
                continue
            }
            let quotedArguments = (lineIndex + 1..<min(lineIndex + 3, lines.count))
                .compactMap { singleQuotedValue(in: lines[$0]) }
            if quotedArguments.count == 2 {
                entries.append(
                    HandKeptIsolationEntry(sourcePath: quotedArguments[0], suiteName: quotedArguments[1])
                )
            }
            lineIndex += 3
        }
        return entries
    }

    private func singleQuotedValue(in line: String) -> String? {
        guard let openingQuote = line.firstIndex(of: "'"),
            let closingQuote = line.lastIndex(of: "'"),
            openingQuote < closingQuote
        else {
            return nil
        }
        return String(line[line.index(after: openingQuote)..<closingQuote])
    }

    private func shellFunctionBody(named functionName: String, in script: String) throws -> String {
        let marker = "\(functionName)() {"
        guard let startRange = script.range(of: marker) else {
            throw SwiftLaneIsolationListGateError.missingShellFunction(functionName)
        }
        let tail = script[startRange.lowerBound...]
        guard let endRange = tail.range(of: "\n}\n") else {
            return String(tail)
        }
        return String(tail[..<endRange.lowerBound])
    }

    /// Runs one helper function and returns its printed lines.
    ///
    /// The subprocess wait goes through `withoutBlockingCooperativePool`: waiting
    /// on process exit from a test body parks a cooperative thread, which is the
    /// blocking rule this standard exists to enforce (spec R8).
    private func shellHelperLines(_ helperFunction: String) async throws -> Set<String> {
        let rendered = try await withoutBlockingCooperativePool {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                "-c",
                "source scripts/swift-test-helpers.sh; \(helperFunction)",
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            process.standardOutput = output
            process.standardError = output

            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let rendered = String(bytes: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw SwiftLaneIsolationListGateError.shellHelperFailed(helperFunction, rendered)
            }
            return rendered
        }
        return Set(rendered.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }
}

private enum SwiftLaneIsolationListGateError: Error {
    case missingShellFunction(String)
    case shellHelperFailed(String, String)
}
