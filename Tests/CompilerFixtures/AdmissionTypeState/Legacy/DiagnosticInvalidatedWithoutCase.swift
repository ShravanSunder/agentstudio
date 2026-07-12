func observeLegacyDiagnosticInvalidatedWithoutCase(
    _ diagnostics: OrderedFactJournalDiagnostics
) -> Bool {
    diagnostics.isCurrent == false && diagnostics.productGap == nil
}
