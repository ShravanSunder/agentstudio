import AgentStudioInfrastructure
import Foundation
import Testing

@Suite("Swift lane fast shard coverage script")
struct SwiftLaneFastShardCoverageScriptTests {
    @Test("native fast shards use bounded direct helper dispatch and coverage validation")
    func nativeFastShardsUseAcceptedExecutionPath() throws {
        let helperSource = try String(contentsOfFile: "scripts/swift-test-helpers.sh", encoding: .utf8)
        let shardRunner = try #require(shellFunction(named: "run_fast_sharded_native_swift_tests", in: helperSource))
        let shardInvocation = try #require(shellFunction(named: "run_selected_fast_shard", in: helperSource))
        let dispatcher = try #require(shellFunction(named: "dispatch_isolated_suites", in: helperSource))

        #expect(helperSource.contains("FAST_LANE_SHARD_UNIT_CAPACITY=250"))
        #expect(helperSource.contains("FAST_LANE_SHARD_PROCESS_CONCURRENCY=3"))
        #expect(shardRunner.contains("inventory \"$manifest_path\" \"$suite_types_path\""))
        #expect(shardRunner.contains("plan \"$manifest_path\" \"$FAST_LANE_SHARD_UNIT_CAPACITY\""))
        #expect(shardRunner.contains("dispatch_isolated_suites fast-shard"))
        #expect(shardRunner.contains("validate \"$manifest_path\" \"$plan_path\""))
        #expect(dispatcher.contains("FAST_LANE_SHARD_PROCESS_CONCURRENCY"))
        #expect(dispatcher.contains("run_selected_fast_shard"))
        #expect(shardInvocation.contains("\"$swift_testing_helper\" --test-bundle-path \"$swift_test_bundle\""))
        #expect(shardInvocation.contains("LANE_EVENT_STREAM_RETAIN_ALWAYS=1"))
        #expect(shardInvocation.contains("--filter \"$suite_filter\""))
        #expect(!shardInvocation.contains("swift test"))
        #expect(!shardInvocation.contains("--parallel"))
    }

    @Test("planner counts parameter cases and keeps suites whole under K")
    func plannerCountsCasesAndKeepsSuitesWhole() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.standardManifest)
        defer { fixture.remove() }

        let result = try await fixture.run("plan \(fixture.manifest.path) 4")

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("SHARD\t1\t4"))
        #expect(result.output.contains("SUITE\t1\tTarget.Alpha"))
        #expect(result.output.contains("SHARD\t2\t3"))
        #expect(result.output.contains("SUITE\t2\tTarget.Beta"))
        #expect(result.output.contains("SHARD\t3\t3"))
        #expect(result.output.contains("SUITE\t3\tTarget.Delta"))
        #expect(result.output.contains("SUITE\t3\tTarget.Gamma"))
    }

    @Test("live classified native suites must have F2 manifest entries")
    func inventoryRejectsUnmanifestedSuite() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.standardManifest)
        defer { fixture.remove() }
        try fixture.writeSuiteTypes(["Alpha", "Beta", "Gamma", "Delta", "Epsilon"])

        let result = try await fixture.run("inventory \(fixture.manifest.path) \(fixture.suiteTypes.path)")

        #expect(result.exitCode != 0)
        #expect(result.output.contains("inventory_error=unmanifested_suite suite=Epsilon"))
    }

    @Test("coverage rejects a plan that drops a suite by its identity")
    func coverageRejectsDroppedSuite() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.standardManifest)
        defer { fixture.remove() }
        try fixture.writePlan("SHARD\t1\t4\nSUITE\t1\tTarget.Alpha\n")

        let result = try await fixture.run(
            "validate \(fixture.manifest.path) \(fixture.plan.path) \(fixture.captureDirectory.path) \(fixture.receipt.path)"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("coverage_error=missing_suite suite=Target.Beta"))
    }

    @Test("coverage rejects a suite assigned to two shards")
    func coverageRejectsDuplicateSuite() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.standardManifest)
        defer { fixture.remove() }
        try fixture.writePlan(
            "SHARD\t1\t4\nSUITE\t1\tTarget.Alpha\n"
                + "SHARD\t2\t4\nSUITE\t2\tTarget.Alpha\n"
        )

        let result = try await fixture.run(
            "validate \(fixture.manifest.path) \(fixture.plan.path) \(fixture.captureDirectory.path) \(fixture.receipt.path)"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("coverage_error=duplicate_suite suite=Target.Alpha"))
    }

    @Test("coverage names a test function missing from its shard")
    func coverageNamesMissingFunction() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.singleParameterizedSuiteManifest)
        defer { fixture.remove() }
        try fixture.writePlan("SHARD\t1\t3\nSUITE\t1\tTarget.Alpha\n")
        try fixture.writeEvents(shard: 1, [try fixture.event("runStarted"), try fixture.event("runEnded")])
        try fixture.writeTiming(
            shard: 1,
            startToFirstOutputSeconds: 0.25,
            announcedTests: 0,
            endedTests: 0,
            startedCases: 0,
            endedCases: 0
        )

        let result = try await fixture.run(
            "validate \(fixture.manifest.path) \(fixture.plan.path) \(fixture.captureDirectory.path) \(fixture.receipt.path)"
        )

        #expect(result.exitCode != 0)
        #expect(
            result.output.contains("coverage_error=missing_function function=Target.Alpha/alphaParameterized(value:)"))
    }

    @Test("coverage names a missing parameter case and records first output")
    func coverageNamesMissingParameterCase() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.singleParameterizedSuiteManifest)
        defer { fixture.remove() }
        try fixture.writePlan("SHARD\t1\t3\nSUITE\t1\tTarget.Alpha\n")
        try fixture.writeEvents(
            shard: 1,
            [
                try fixture.suiteDefinition("Target.Alpha"),
                try fixture.functionDefinition("Target.Alpha/alphaParameterized(value:)", parameterized: true),
                try fixture.event("runStarted"),
                try fixture.event("testStarted", testID: "Target.Alpha/alphaParameterized(value:)/Alpha.swift:1:1"),
                try fixture.event(
                    "testCaseStarted",
                    testID: "Target.Alpha/alphaParameterized(value:)/Alpha.swift:1:1",
                    caseID: "case-one",
                    displayName: "first value"
                ),
                try fixture.event(
                    "testCaseEnded",
                    testID: "Target.Alpha/alphaParameterized(value:)/Alpha.swift:1:1",
                    caseID: "case-one",
                    displayName: "first value"
                ),
                try fixture.event("testEnded", testID: "Target.Alpha/alphaParameterized(value:)/Alpha.swift:1:1"),
                try fixture.event("runEnded"),
            ]
        )
        try fixture.writeTiming(shard: 1, startToFirstOutputSeconds: 0.25)

        let result = try await fixture.run(
            "validate \(fixture.manifest.path) \(fixture.plan.path) \(fixture.captureDirectory.path) \(fixture.receipt.path)"
        )
        let receipt = try String(contentsOf: fixture.receipt, encoding: .utf8)

        #expect(result.exitCode != 0)
        #expect(result.output.contains("coverage_error=missing_case_display_name"))
        #expect(result.output.contains("function=Target.Alpha/alphaParameterized(value:)"))
        #expect(receipt.contains("start_to_first_output_seconds"))
        #expect(receipt.contains("case-one"))
    }

    @Test("manifest generation rejects an F2 ledger with an unended function")
    func manifestGenerationRejectsIncompleteF2Ledger() async throws {
        let fixture = try FastShardCoverageFixture(manifest: FastShardCoverageFixture.singleParameterizedSuiteManifest)
        defer { fixture.remove() }
        try fixture.writeEvents(
            shard: 1,
            [
                try fixture.suiteDefinition("Target.Alpha"),
                try fixture.functionDefinition("Target.Alpha/alphaParameterized(value:)", parameterized: true),
                try fixture.event("runStarted"),
                try fixture.event("testStarted", testID: "Target.Alpha/alphaParameterized(value:)/Alpha.swift:1:1"),
                try fixture.event("runEnded"),
            ]
        )
        try fixture.writeTiming(
            shard: 1,
            startToFirstOutputSeconds: 0.25,
            announcedTests: 1,
            endedTests: 0,
            startedCases: 0,
            endedCases: 0
        )

        let result = try await fixture.run(
            "manifest \(fixture.events(for: 1).path) \(fixture.timing(for: 1).path) fixture-run fixture-head"
        )

        #expect(result.exitCode != 0)
        #expect(result.output.contains("manifest_error=unended_function"))
        #expect(result.output.contains("Target.Alpha/alphaParameterized(value:)"))
    }

    private struct FastShardCoverageFixture {
        static let standardManifest = #"""
            {
              "schema_version": 1,
              "source_run_id": "fixture-run",
              "source_head_sha": "fixture-head",
              "suites": [
                {"id": "Target.Alpha", "type_path": "Alpha"},
                {"id": "Target.Beta", "type_path": "Beta"},
                {"id": "Target.Gamma", "type_path": "Gamma"},
                {"id": "Target.Delta", "type_path": "Delta"}
              ],
              "functions": [
                {"id": "Target.Alpha/alphaPlain()", "suite_id": "Target.Alpha", "name": "alphaPlain()", "parameterized": false, "case_display_names": []},
                {"id": "Target.Alpha/alphaParameterized(value:)", "suite_id": "Target.Alpha", "name": "alphaParameterized(value:)", "parameterized": true, "case_display_names": ["alpha case one", "alpha case two"]},
                {"id": "Target.Beta/betaPlain()", "suite_id": "Target.Beta", "name": "betaPlain()", "parameterized": false, "case_display_names": []},
                {"id": "Target.Beta/betaParameterized(value:)", "suite_id": "Target.Beta", "name": "betaParameterized(value:)", "parameterized": true, "case_display_names": ["beta case"]},
                {"id": "Target.Gamma/gammaOne()", "suite_id": "Target.Gamma", "name": "gammaOne()", "parameterized": false, "case_display_names": []},
                {"id": "Target.Gamma/gammaTwo()", "suite_id": "Target.Gamma", "name": "gammaTwo()", "parameterized": false, "case_display_names": []},
                {"id": "Target.Delta/deltaOne()", "suite_id": "Target.Delta", "name": "deltaOne()", "parameterized": false, "case_display_names": []}
              ]
            }
            """#

        static let singleParameterizedSuiteManifest = #"""
            {
              "schema_version": 1,
              "source_run_id": "fixture-run",
              "source_head_sha": "fixture-head",
              "suites": [{"id": "Target.Alpha", "type_path": "Alpha"}],
              "functions": [
                {"id": "Target.Alpha/alphaParameterized(value:)", "suite_id": "Target.Alpha", "name": "alphaParameterized(value:)", "parameterized": true, "case_display_names": ["first value", "second value"]}
              ]
            }
            """#

        let root: URL
        let manifest: URL
        let plan: URL
        let captureDirectory: URL
        let receipt: URL
        let suiteTypes: URL

        init(manifest manifestContents: String) throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "swift-fast-shard-\(UUIDv7.generate().uuidString)")
            manifest = root.appending(path: "manifest.json")
            plan = root.appending(path: "plan.tsv")
            captureDirectory = root.appending(path: "events", directoryHint: .isDirectory)
            receipt = root.appending(path: "coverage.json")
            suiteTypes = root.appending(path: "suite-types.txt")
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            try manifestContents.write(to: manifest, atomically: true, encoding: .utf8)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        func run(_ arguments: String) async throws -> LaneScriptBashResult {
            try await runLaneScriptBash("perl scripts/swift-test-fast-shard-inventory.pl \(arguments)")
        }

        func writePlan(_ contents: String) throws {
            try contents.write(to: plan, atomically: true, encoding: .utf8)
        }

        func writeSuiteTypes(_ suiteTypes: [String]) throws {
            try (suiteTypes.joined(separator: "\n") + "\n")
                .write(to: self.suiteTypes, atomically: true, encoding: .utf8)
        }

        func events(for shard: Int) -> URL {
            captureDirectory.appending(path: String(format: "shard-%03d.events.jsonl", shard))
        }

        func timing(for shard: Int) -> URL {
            captureDirectory.appending(path: String(format: "shard-%03d.timing.json", shard))
        }

        func writeEvents(shard: Int, _ records: [String]) throws {
            try (records.joined(separator: "\n") + "\n")
                .write(to: events(for: shard), atomically: true, encoding: .utf8)
        }

        func writeTiming(
            shard: Int,
            startToFirstOutputSeconds: Double,
            announcedTests: Int = 1,
            endedTests: Int = 1,
            startedCases: Int = 1,
            endedCases: Int = 1
        ) throws {
            let timingPayload: [String: Any] = [
                "command_status": 0,
                "announced_tests": announcedTests,
                "ended_tests": endedTests,
                "started_parameterized_cases": startedCases,
                "ended_parameterized_cases": endedCases,
                "start_to_first_output_seconds": startToFirstOutputSeconds,
            ]
            let data = try JSONSerialization.data(withJSONObject: timingPayload, options: [.sortedKeys])
            try data.write(to: timing(for: shard))
        }

        func suiteDefinition(_ suiteID: String) throws -> String {
            try record([
                "kind": "test",
                "payload": ["kind": "suite", "id": suiteID, "name": suiteID],
            ])
        }

        func functionDefinition(_ functionID: String, parameterized: Bool) throws -> String {
            let name = functionID.split(separator: "/").last.map(String.init) ?? functionID
            let id = "\(functionID)/Alpha.swift:1:1"
            return try record([
                "kind": "test",
                "payload": [
                    "kind": "function", "id": id, "name": name, "isParameterized": parameterized,
                ],
            ])
        }

        func event(
            _ kind: String,
            testID: String? = nil,
            caseID: String? = nil,
            displayName: String? = nil
        ) throws -> String {
            var payload: [String: Any] = ["kind": kind]
            if let testID { payload["testID"] = testID }
            if let caseID, let displayName {
                payload["_testCase"] = ["id": caseID, "displayName": displayName]
            }
            return try record(["kind": "event", "payload": payload])
        }

        private func record(_ value: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            return try #require(String(data: data, encoding: .utf8))
        }
    }

    private func shellFunction(named name: String, in source: String) -> String? {
        guard let declaration = source.range(of: "\(name)() {") else { return nil }
        let functionContentsStart = declaration.upperBound
        guard let closingBrace = source[functionContentsStart...].range(of: "\n}") else { return nil }
        return String(source[declaration.lowerBound..<closingBrace.upperBound])
    }

}
