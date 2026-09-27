/// Where one lint run spent its time.
///
/// Reported so a slow rule is visible and fixable. Nothing compares these
/// numbers with a threshold: lint speed is a defect to fix, never a failing
/// check.
struct ArchitectureLintTimings {
    let parsedFileCount: Int
    let validatedFileCount: Int
    let parse: Duration
    let prepare: Duration
    /// Wall time of the parallel validation phase.
    let validate: Duration
    /// Per rule: its `prepared(for:)` plus its `validate` summed across files,
    /// so the sum over rules exceeds the validation wall time on many cores.
    let rules: [ArchitectureRuleTiming]

    var renderedLines: String {
        var lines = [
            "architecture-lint timing stage=parse files=\(parsedFileCount) ms=\(parse.wholeMilliseconds)",
            "architecture-lint timing stage=prepare ms=\(prepare.wholeMilliseconds)",
            "architecture-lint timing stage=validate files=\(validatedFileCount) ms=\(validate.wholeMilliseconds)",
        ]
        for rule in rules.sorted(by: { $0.ruleID < $1.ruleID }) {
            lines.append("architecture-lint timing rule=\(rule.ruleID) ms=\(rule.duration.wholeMilliseconds)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

struct ArchitectureRuleTiming: Sendable {
    let ruleID: String
    let duration: Duration
}

extension Duration {
    var wholeMilliseconds: Int64 {
        let (seconds, attoseconds) = components
        let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
        return seconds * 1000 + attoseconds / attosecondsPerMillisecond
    }
}
