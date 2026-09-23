import Foundation
import SwiftParser

/// The one lint pipeline shared by the command line and the tool's own tests,
/// so the two cannot drift.
///
/// 1. Parse every file in parallel.
/// 2. Prepare every rule once against all parsed files. This is the only
///    barrier: cross-file rules build their indexes here.
/// 3. Validate the in-scope files in parallel; each worker runs every prepared
///    rule on its own file and writes only its own result slot.
///
/// A scoped run still parses the whole corpus, because a scoped file must get
/// the diagnostics a full run would give it, and those can depend on indexes
/// built from files outside the scope.
struct ArchitectureLintEngine {
    let rules: [any ArchitectureRule]
    let workspaceRootPath: String

    /// - Parameters:
    ///   - files: Every file to parse. Order decides which duplicate source
    ///     identity is kept.
    ///   - validatedFiles: Paths, as given in `files`, whose diagnostics are
    ///     reported. `nil` validates every parsed file.
    func lint(files: [String], validatedFiles: Set<String>? = nil) throws -> ArchitectureLintRun {
        let clock = ContinuousClock()
        let workspaceRootPath = workspaceRootPath

        let parseStart = clock.now
        let parsedContexts = try ConcurrentFileWork.map(files) { file in
            try Self.parseContext(file: file, workspaceRootPath: workspaceRootPath)
        }
        var seenSourceIdentities: Set<String> = []
        let contexts = parsedContexts.filter { context in
            seenSourceIdentities.insert(context.syntaxScopeSourceIdentity).inserted
        }
        let parseDuration = parseStart.duration(to: clock.now)

        let prepareStart = clock.now
        let preparations = rules.map { rule in
            let ruleStart = clock.now
            let preparedRule = rule.prepared(for: contexts)
            return (rule: preparedRule, duration: ruleStart.duration(to: clock.now))
        }
        let preparedRules = preparations.map(\.rule)
        let prepareDuration = prepareStart.duration(to: clock.now)

        let validatedContexts =
            validatedFiles.map { scope in
                contexts.filter { scope.contains($0.path) }
            } ?? contexts
        let validateStart = clock.now
        let fileValidations = try ConcurrentFileWork.map(validatedContexts) { context in
            Self.validate(context: context, preparedRules: preparedRules, clock: clock)
        }
        let validateDuration = validateStart.duration(to: clock.now)

        var ruleDurations = preparations.map(\.duration)
        var diagnostics: [ArchitectureDiagnostic] = []
        for fileValidation in fileValidations {
            diagnostics.append(contentsOf: fileValidation.diagnostics)
            for (ruleIndex, duration) in fileValidation.ruleDurations.enumerated() {
                ruleDurations[ruleIndex] += duration
            }
        }

        return ArchitectureLintRun(
            contexts: contexts,
            validatedContexts: validatedContexts,
            diagnostics: diagnostics.sorted(),
            timings: ArchitectureLintTimings(
                parsedFileCount: contexts.count,
                validatedFileCount: validatedContexts.count,
                parse: parseDuration,
                prepare: prepareDuration,
                validate: validateDuration,
                rules: zip(preparedRules, ruleDurations).map { rule, duration in
                    ArchitectureRuleTiming(ruleID: rule.id, duration: duration)
                }
            )
        )
    }

    private static func parseContext(file: String, workspaceRootPath: String) throws -> ArchitectureLintContext {
        let source: String
        do {
            source = try String(contentsOfFile: file, encoding: .utf8)
        } catch {
            throw ArchitectureLintEngineError.unreadableFile(path: file, underlying: error)
        }
        return ArchitectureLintContext(
            path: file,
            source: source,
            sourceFile: Parser.parse(source: source),
            workspaceRootPath: workspaceRootPath
        )
    }

    private static func validate(
        context: ArchitectureLintContext,
        preparedRules: [any ArchitectureRule],
        clock: ContinuousClock
    ) -> FileValidation {
        var diagnostics: [ArchitectureDiagnostic] = []
        var ruleDurations: [Duration] = []
        ruleDurations.reserveCapacity(preparedRules.count)
        for rule in preparedRules {
            let ruleStart = clock.now
            diagnostics.append(contentsOf: rule.validate(context: context))
            ruleDurations.append(ruleStart.duration(to: clock.now))
        }
        return FileValidation(diagnostics: diagnostics, ruleDurations: ruleDurations)
    }
}

struct ArchitectureLintRun {
    /// Every parsed file after duplicate source identities are dropped.
    let contexts: [ArchitectureLintContext]
    /// The files whose diagnostics this run reports.
    let validatedContexts: [ArchitectureLintContext]
    /// Sorted, so output is deterministic whatever order the workers finished.
    let diagnostics: [ArchitectureDiagnostic]
    let timings: ArchitectureLintTimings
}

private struct FileValidation: Sendable {
    let diagnostics: [ArchitectureDiagnostic]
    /// Indexed like the prepared rules.
    let ruleDurations: [Duration]
}

enum ArchitectureLintEngineError: Error, CustomStringConvertible {
    case unreadableFile(path: String, underlying: any Error)

    var description: String {
        switch self {
        case .unreadableFile(let path, let underlying):
            "cannot read \(path): \(underlying)"
        }
    }
}
