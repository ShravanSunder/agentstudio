/// The only-decrease rule the lint run cannot see: the engine reads one ledger
/// and has no history, so CI hands this check the ledger from the pull
/// request's merge base.
///
/// A row whose count is higher than at the base, or a row the base does not
/// have, fails. Lowering or removing rows passes.
enum DebtLedgerRatchet {
    static let ruleID = "agentstudio_debt_ledger_ratchet"

    static func violations(current: ArchitectureDebtLedger, base: ArchitectureDebtLedger) -> [ArchitectureDiagnostic] {
        var baseCounts: [DebtLedgerKey: Int] = [:]
        for entry in base.entries {
            baseCounts[entry.key] = entry.count
        }
        return current.entries.compactMap { entry in
            guard let baseCount = baseCounts[entry.key] else {
                return diagnostic(
                    current: current,
                    entry: entry,
                    message:
                        "Debt ledger row \(entry.key.ruleID) \(entry.key.path) is new; the merge base has no "
                        + "such row and debt may only fall. Fix the violations instead"
                )
            }
            guard entry.count > baseCount else {
                return nil
            }
            return diagnostic(
                current: current,
                entry: entry,
                message:
                    "Debt ledger raises \(entry.key.ruleID) \(entry.key.path) from \(baseCount) to "
                    + "\(entry.count); debt may only fall. Fix the new violations instead"
            )
        }
    }

    private static func diagnostic(
        current: ArchitectureDebtLedger,
        entry: DebtLedgerEntry,
        message: String
    ) -> ArchitectureDiagnostic {
        ArchitectureDiagnostic(
            path: current.sourcePath,
            line: entry.line,
            column: 1,
            severity: .error,
            ruleID: ruleID,
            message: message
        )
    }
}
