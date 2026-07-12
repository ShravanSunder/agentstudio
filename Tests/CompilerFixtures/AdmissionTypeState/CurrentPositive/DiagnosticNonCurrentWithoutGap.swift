import Foundation

func constructCurrentDiagnosticNonCurrentWithGap()
    -> OrderedFactJournalDiagnosticCurrentness
{
    let generation = AdmissionGeneration(owner: .runtimeFacts, value: 1)
    return .nonCurrent(
        FactGap(
            generation: generation,
            missingSequences: 1...1,
            token: FactGapToken(
                generation: generation,
                journalIdentity: UUID(),
                revision: 1
            )
        )
    )
}
