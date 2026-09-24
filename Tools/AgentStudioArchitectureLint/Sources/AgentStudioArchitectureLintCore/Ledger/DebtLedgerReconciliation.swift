/// Compares one run's violation sites with the ledger, per rule and file.
///
/// | Sites found (n) vs permitted (k) | Result |
/// | --- | --- |
/// | n = k | pass: the sites are known debt |
/// | n > k | every site is reported, with the permitted count |
/// | 0 < n < k | one error: lower the row to n |
/// | n = 0 < k | one error: remove the row |
/// | row path not linted (full run) | one error at the row: the path is gone |
///
/// Lower counts fail too, so the ledger always states the real debt and a
/// paid-down file cannot quietly absorb a new violation later.
struct DebtLedgerReconciliation {
    let ledger: ArchitectureDebtLedger
    /// The files this run validated: repository-relative path to the path
    /// its diagnostics are printed with.
    let validatedPaths: [String: String]
    /// A full run also owns rows whose path it did not validate: such a path
    /// no longer exists or is no longer linted. A scoped run cannot tell.
    let isFullRun: Bool

    struct Outcome {
        let diagnostics: [ArchitectureDiagnostic]
        /// Sites found for every ledger row this run can see, for lowering.
        let observedCounts: [DebtLedgerKey: Int]
    }

    /// - Parameter relativePath: The repository-relative path of a validated
    ///   file's diagnostic, or `nil` for a path outside the validated files.
    func reconcile(
        diagnostics: [ArchitectureDiagnostic],
        relativePath: (ArchitectureDiagnostic) -> String?
    ) -> Outcome {
        var sitesByKey: [DebtLedgerKey: [ArchitectureDiagnostic]] = [:]
        var reconciled: [ArchitectureDiagnostic] = []
        for diagnostic in diagnostics {
            guard let path = relativePath(diagnostic) else {
                reconciled.append(diagnostic)
                continue
            }
            sitesByKey[DebtLedgerKey(ruleID: diagnostic.ruleID, path: path), default: []].append(diagnostic)
        }

        var entriesByKey: [DebtLedgerKey: DebtLedgerEntry] = [:]
        for entry in ledger.entries {
            entriesByKey[entry.key] = entry
        }

        var observedCounts: [DebtLedgerKey: Int] = [:]
        for (key, sites) in sitesByKey {
            guard let entry = entriesByKey[key] else {
                reconciled.append(contentsOf: sites)
                continue
            }
            observedCounts[key] = sites.count
            if sites.count > entry.count {
                reconciled.append(contentsOf: sites.map { overCount($0, found: sites.count, permitted: entry.count) })
            } else if sites.count < entry.count {
                reconciled.append(
                    fileDiagnostic(
                        sites[0],
                        message:
                            "Debt ledger permits \(entry.count) here but \(sites.count) remain; lower the "
                            + "row to \(sites.count) in \(ledger.sourcePath) (--lower-ledger-counts)"
                    )
                )
            }
        }

        for entry in ledger.entries where sitesByKey[entry.key] == nil {
            if let displayPath = validatedPaths[entry.key.path] {
                observedCounts[entry.key] = 0
                reconciled.append(
                    ArchitectureDiagnostic(
                        path: displayPath,
                        line: 1,
                        column: 1,
                        severity: .error,
                        ruleID: entry.key.ruleID,
                        message:
                            "Debt ledger permits \(entry.count) here but none remain; remove the row from "
                            + "\(ledger.sourcePath) (--lower-ledger-counts)"
                    )
                )
            } else if isFullRun {
                reconciled.append(
                    ArchitectureDiagnostic(
                        path: ledger.sourcePath,
                        line: entry.line,
                        column: 1,
                        severity: .error,
                        ruleID: entry.key.ruleID,
                        message:
                            "Debt ledger row names \(entry.key.path), which no longer exists or is not linted; "
                            + "remove the row (--lower-ledger-counts)"
                    )
                )
            }
        }

        return Outcome(diagnostics: reconciled.sorted(), observedCounts: observedCounts)
    }

    /// The ledger with every visible count lowered to what this run found.
    /// Rows at zero, and in a full run rows whose path is gone, are removed.
    /// A count is never raised and no row is added.
    func lowered(observedCounts: [DebtLedgerKey: Int]) -> ArchitectureDebtLedger {
        let entries = ledger.entries.compactMap { entry -> DebtLedgerEntry? in
            guard let observed = observedCounts[entry.key] else {
                return isFullRun ? nil : entry
            }
            let count = min(entry.count, observed)
            guard count > 0 else {
                return nil
            }
            return DebtLedgerEntry(key: entry.key, count: count, line: entry.line)
        }
        return ArchitectureDebtLedger(sourcePath: ledger.sourcePath, entries: entries)
    }

    private func overCount(_ site: ArchitectureDiagnostic, found: Int, permitted: Int) -> ArchitectureDiagnostic {
        ArchitectureDiagnostic(
            path: site.path,
            line: site.line,
            column: site.column,
            severity: site.severity,
            ruleID: site.ruleID,
            message: "\(site.message) [count \(found) exceeds \(permitted) permitted by \(ledger.sourcePath)]"
        )
    }

    private func fileDiagnostic(_ site: ArchitectureDiagnostic, message: String) -> ArchitectureDiagnostic {
        ArchitectureDiagnostic(
            path: site.path,
            line: 1,
            column: 1,
            severity: .error,
            ruleID: site.ruleID,
            message: message
        )
    }
}
