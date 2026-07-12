func observeLegacyDiagnosticCurrentWithGap(
    _ diagnostics: OrderedFactJournalDiagnostics
) -> Bool {
    diagnostics.isCurrent && diagnostics.productGap != nil
}
