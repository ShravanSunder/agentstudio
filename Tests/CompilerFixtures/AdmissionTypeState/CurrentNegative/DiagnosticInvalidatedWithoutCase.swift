func attachGapToCurrentDiagnosticInvalidated()
    -> OrderedFactJournalDiagnosticCurrentness
{
    .invalidated(fatalError("Invalidated diagnostics cannot carry a product gap"))
}
