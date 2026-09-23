import Foundation
import Testing

@testable import AgentStudioArchitectureLintCore

@Suite
struct DebtLedgerTests {
    private static let ledgerPath = "Tools/AgentStudioArchitectureLint/architecture-debt-ledger.tsv"
    private static let ruleID = "agentstudio_no_polling_wait_in_tests"
    private static let filePath = "Tests/AgentStudioTests/PollingTests.swift"
    private static let displayPath = "/repo/Tests/AgentStudioTests/PollingTests.swift"

    // MARK: - Reconciliation, one row per state

    @Test("a file at exactly its permitted count is known debt and passes")
    func fileAtPermittedCountPasses() throws {
        let outcome = try reconcile(siteCount: 2, permitted: 2)

        #expect(outcome.diagnostics.isEmpty)
        #expect(outcome.observedCounts[key] == 2)
    }

    @Test("a file with no row reports every site")
    func fileWithoutRowReportsEverySite() throws {
        let outcome = try reconcile(siteCount: 2, permitted: nil)

        #expect(outcome.diagnostics.map(\.line) == [10, 20])
        #expect(outcome.diagnostics.allSatisfy { $0.message == "polling" })
    }

    @Test("a clean file with no row passes")
    func cleanFileWithoutRowPasses() throws {
        let outcome = try reconcile(siteCount: 0, permitted: nil)

        #expect(outcome.diagnostics.isEmpty)
    }

    @Test("a file over its permitted count reports every site with both counts")
    func fileOverPermittedCountReportsEverySite() throws {
        let outcome = try reconcile(siteCount: 3, permitted: 2)

        #expect(outcome.diagnostics.map(\.line) == [10, 20, 30])
        #expect(outcome.diagnostics.allSatisfy { $0.message.contains("count 3 exceeds 2 permitted") })
        #expect(outcome.diagnostics.allSatisfy { $0.severity == .error })
    }

    @Test("a file under its permitted count fails and names the count to record")
    func fileUnderPermittedCountNamesLowerCount() throws {
        let outcome = try reconcile(siteCount: 1, permitted: 3)

        #expect(outcome.diagnostics.count == 1)
        let diagnostic = try #require(outcome.diagnostics.first)
        #expect(diagnostic.path == Self.displayPath)
        #expect(diagnostic.line == 1)
        #expect(diagnostic.ruleID == Self.ruleID)
        #expect(diagnostic.message.contains("lower the row to 1"))
        #expect(outcome.observedCounts[key] == 1)
    }

    @Test("a row whose file no longer violates fails and names the row to remove")
    func staleRowFailsAndNamesRowToRemove() throws {
        let outcome = try reconcile(siteCount: 0, permitted: 2)

        #expect(outcome.diagnostics.count == 1)
        let diagnostic = try #require(outcome.diagnostics.first)
        #expect(diagnostic.path == Self.displayPath)
        #expect(diagnostic.message.contains("remove the row"))
        #expect(outcome.observedCounts[key] == 0)
    }

    @Test("a row whose path is not linted fails at the ledger row in a full run only")
    func missingPathRowFailsInFullRunOnly() throws {
        let ledger = try ledger(rows: ["\(Self.ruleID)\tTests/Gone.swift\t1"])

        let fullRun = DebtLedgerReconciliation(ledger: ledger, validatedPaths: [:], isFullRun: true)
            .reconcile(diagnostics: []) { _ in nil }
        let scopedRun = DebtLedgerReconciliation(ledger: ledger, validatedPaths: [:], isFullRun: false)
            .reconcile(diagnostics: []) { _ in nil }

        #expect(fullRun.diagnostics.count == 1)
        let diagnostic = try #require(fullRun.diagnostics.first)
        #expect(diagnostic.path == Self.ledgerPath)
        #expect(diagnostic.line == 2)
        #expect(diagnostic.message.contains("Tests/Gone.swift"))
        #expect(scopedRun.diagnostics.isEmpty)
    }

    @Test("lowering records smaller counts, drops zero and missing rows, and never raises")
    func loweringNeverRaises() throws {
        let ledger = try ledger(rows: [
            "a_rule\tTests/Gone.swift\t1",
            "a_rule\tTests/Lower.swift\t3",
            "a_rule\tTests/Over.swift\t1",
            "a_rule\tTests/Paid.swift\t2",
        ])
        let reconciliation = DebtLedgerReconciliation(
            ledger: ledger,
            validatedPaths: [
                "Tests/Lower.swift": "/repo/Tests/Lower.swift",
                "Tests/Over.swift": "/repo/Tests/Over.swift",
                "Tests/Paid.swift": "/repo/Tests/Paid.swift",
            ],
            isFullRun: true
        )

        let lowered = reconciliation.lowered(observedCounts: [
            DebtLedgerKey(ruleID: "a_rule", path: "Tests/Lower.swift"): 1,
            DebtLedgerKey(ruleID: "a_rule", path: "Tests/Over.swift"): 5,
            DebtLedgerKey(ruleID: "a_rule", path: "Tests/Paid.swift"): 0,
        ])

        #expect(
            lowered.rendered
                == """
                rule_id\tpath\tcount
                a_rule\tTests/Lower.swift\t1
                a_rule\tTests/Over.swift\t1

                """)
    }

    // MARK: - Ratchet against the merge base

    @Test("ratchet fails a raised count and a new row, and passes lowered, removed and equal rows")
    func ratchetFailsRaisesAndAdditionsOnly() throws {
        let base = try ledger(rows: [
            "a_rule\tTests/Equal.swift\t2",
            "a_rule\tTests/Lowered.swift\t3",
            "a_rule\tTests/Raised.swift\t1",
            "a_rule\tTests/Removed.swift\t1",
        ])
        let current = try ledger(rows: [
            "a_rule\tTests/Added.swift\t1",
            "a_rule\tTests/Equal.swift\t2",
            "a_rule\tTests/Lowered.swift\t1",
            "a_rule\tTests/Raised.swift\t2",
        ])

        let violations = DebtLedgerRatchet.violations(current: current, base: base)

        #expect(violations.map(\.line) == [2, 5])
        #expect(violations[0].message.contains("Tests/Added.swift is new"))
        #expect(violations[1].message.contains("Tests/Raised.swift from 1 to 2"))
        #expect(violations.allSatisfy { $0.ruleID == DebtLedgerRatchet.ruleID && $0.path == Self.ledgerPath })
        #expect(DebtLedgerRatchet.violations(current: base, base: base).isEmpty)
    }

    // MARK: - File format fails closed

    @Test(
        "malformed ledgers fail closed naming the line",
        arguments: [
            ("a_rule\tTests/A.swift\t1\n", 1),
            ("rule_id\tpath\tcount\na_rule\tTests/A.swift\n", 2),
            ("rule_id\tpath\tcount\na_rule\tTests/A.swift\t0\n", 2),
            ("rule_id\tpath\tcount\na_rule\t/abs/A.swift\t1\n", 2),
            ("rule_id\tpath\tcount\nb_rule\tTests/A.swift\t1\na_rule\tTests/A.swift\t1\n", 3),
            ("rule_id\tpath\tcount\na_rule\tTests/A.swift\t1\na_rule\tTests/A.swift\t2\n", 3),
        ]
    )
    func malformedLedgersFailClosed(contents: String, line: Int) {
        #expect {
            try ArchitectureDebtLedger.parse(contents: contents, sourcePath: Self.ledgerPath)
        } throws: { error in
            guard case .malformed(let path, let errorLine, _) = error as? DebtLedgerError else {
                return false
            }
            return path == Self.ledgerPath && errorLine == line
        }
    }

    @Test("a ledger renders back to the same text it was parsed from")
    func ledgerRoundTrips() throws {
        let contents = "rule_id\tpath\tcount\na_rule\tTests/A.swift\t2\nb_rule\tSources/B.swift\t1\n"

        let ledger = try ArchitectureDebtLedger.parse(contents: contents, sourcePath: Self.ledgerPath)

        #expect(ledger.rendered == contents)
    }

    // MARK: - Helpers

    private var key: DebtLedgerKey {
        DebtLedgerKey(ruleID: Self.ruleID, path: Self.filePath)
    }

    private func reconcile(siteCount: Int, permitted: Int?) throws -> DebtLedgerReconciliation.Outcome {
        let rows = permitted.map { ["\(Self.ruleID)\t\(Self.filePath)\t\($0)"] } ?? []
        let sites = (0..<siteCount).map { index in
            ArchitectureDiagnostic(
                path: Self.displayPath,
                line: (index + 1) * 10,
                column: 1,
                severity: .error,
                ruleID: Self.ruleID,
                message: "polling"
            )
        }
        return try DebtLedgerReconciliation(
            ledger: ledger(rows: rows),
            validatedPaths: [Self.filePath: Self.displayPath],
            isFullRun: true
        )
        .reconcile(diagnostics: sites) { $0.path == Self.displayPath ? Self.filePath : nil }
    }

    private func ledger(rows: [String]) throws -> ArchitectureDebtLedger {
        try ArchitectureDebtLedger.parse(
            contents: ([ArchitectureDebtLedger.header] + rows).joined(separator: "\n") + "\n",
            sourcePath: Self.ledgerPath
        )
    }
}
