func observeLegacyDiagnosticNonCurrentWithoutGap(
    _ diagnostics: OrderedFactJournalDiagnostics
) -> Bool {
    diagnostics.isCurrent == false && diagnostics.productGap == nil
}
