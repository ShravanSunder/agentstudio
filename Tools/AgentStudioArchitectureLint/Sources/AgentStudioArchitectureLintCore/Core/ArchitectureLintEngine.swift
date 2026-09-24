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
/// 4. Reconcile the sites against the debt ledger (`ArchitectureLintRun`).
///
/// A scoped run still parses the whole corpus, because a scoped file must get
/// the diagnostics a full run would give it, and those can depend on indexes
/// built from files outside the scope.
struct ArchitectureLintEngine {
    let rules: [any ArchitectureRule]
    /// Rules over agent instruction documents (`AGENTS.md`) in `files`.
    let documentRules: [any ArchitectureDocumentRule]
    let workspaceRootPath: String

    /// - Parameters:
    ///   - files: Every file to parse. Order decides which duplicate source
    ///     identity is kept.
    ///   - validatedFiles: Paths, as given in `files`, whose diagnostics are
    ///     reported. `nil` validates every parsed file.
    func lint(files: [String], validatedFiles: Set<String>? = nil) throws -> ArchitectureLintRun {
        let clock = ContinuousClock()
        let workspaceRootPath = workspaceRootPath

        let documentFiles = files.filter(AgentDocumentContext.isAgentDocument)
        let swiftFiles = files.filter { !AgentDocumentContext.isAgentDocument($0) }

        let parseStart = clock.now
        let documents = try ConcurrentFileWork.map(documentFiles) { file in
            try Self.readDocument(file: file, workspaceRootPath: workspaceRootPath)
        }
        let parsedContexts = try ConcurrentFileWork.map(swiftFiles) { file in
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
        let documentRules = documentRules
        let validatedDocuments =
            validatedFiles.map { scope in
                documents.filter { scope.contains($0.path) }
            } ?? documents
        let documentValidations = try ConcurrentFileWork.map(validatedDocuments) { document in
            Self.validate(document: document, documentRules: documentRules, clock: clock)
        }
        let validateDuration = validateStart.duration(to: clock.now)

        var ruleDurations = preparations.map(\.duration) + documentRules.map { _ in Duration.zero }
        var diagnostics: [ArchitectureDiagnostic] =
            validatedFiles == nil ? preparedRules.flatMap { $0.configurationDiagnostics() } : []
        for documentValidation in documentValidations {
            diagnostics.append(contentsOf: documentValidation.diagnostics)
            for (ruleIndex, duration) in documentValidation.ruleDurations.enumerated() {
                ruleDurations[preparedRules.count + ruleIndex] += duration
            }
        }
        for fileValidation in fileValidations {
            diagnostics.append(contentsOf: fileValidation.diagnostics)
            for (ruleIndex, duration) in fileValidation.ruleDurations.enumerated() {
                ruleDurations[ruleIndex] += duration
            }
        }

        return ArchitectureLintRun(
            contexts: contexts,
            validatedContexts: validatedContexts,
            validatedDocuments: validatedDocuments,
            isFullRun: validatedFiles == nil,
            siteDiagnostics: diagnostics.sorted(),
            timings: ArchitectureLintTimings(
                parsedFileCount: contexts.count + documents.count,
                validatedFileCount: validatedContexts.count + validatedDocuments.count,
                parse: parseDuration,
                prepare: prepareDuration,
                validate: validateDuration,
                rules: zip(preparedRules.map(\.id) + documentRules.map(\.id), ruleDurations).map { ruleID, duration in
                    ArchitectureRuleTiming(ruleID: ruleID, duration: duration)
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

    private static func readDocument(file: String, workspaceRootPath: String) throws -> AgentDocumentContext {
        do {
            return AgentDocumentContext(
                path: file,
                contents: try String(contentsOfFile: file, encoding: .utf8),
                workspaceRootPath: workspaceRootPath
            )
        } catch {
            throw ArchitectureLintEngineError.unreadableFile(path: file, underlying: error)
        }
    }

    private static func validate(
        document: AgentDocumentContext,
        documentRules: [any ArchitectureDocumentRule],
        clock: ContinuousClock
    ) -> FileValidation {
        var diagnostics: [ArchitectureDiagnostic] = []
        var ruleDurations: [Duration] = []
        for rule in documentRules {
            let ruleStart = clock.now
            diagnostics.append(contentsOf: rule.validate(document: document))
            ruleDurations.append(ruleStart.duration(to: clock.now))
        }
        return FileValidation(diagnostics: diagnostics, ruleDurations: ruleDurations)
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
    let validatedDocuments: [AgentDocumentContext]
    let isFullRun: Bool
    /// Every violation site the rules found, before the debt ledger is
    /// applied. Sorted, so output is deterministic whatever order the workers
    /// finished in.
    let siteDiagnostics: [ArchitectureDiagnostic]
    let timings: ArchitectureLintTimings

    func reconciliation(with ledger: ArchitectureDebtLedger) -> DebtLedgerReconciliation {
        var validatedPaths: [String: String] = [:]
        for context in validatedContexts {
            if let relativePath = context.workspaceRelativePath {
                validatedPaths[relativePath] = context.path
            }
        }
        for document in validatedDocuments {
            if let relativePath = document.workspaceRelativePath {
                validatedPaths[relativePath] = document.path
            }
        }
        return DebtLedgerReconciliation(ledger: ledger, validatedPaths: validatedPaths, isFullRun: isFullRun)
    }

    /// The run's diagnostics with known debt removed and ledger drift added.
    func reconciled(with ledger: ArchitectureDebtLedger) -> DebtLedgerReconciliation.Outcome {
        var relativePathByDisplayPath: [String: String] = [:]
        for (relativePath, displayPath) in reconciliation(with: ledger).validatedPaths {
            relativePathByDisplayPath[displayPath] = relativePath
        }
        return reconciliation(with: ledger).reconcile(diagnostics: siteDiagnostics) { diagnostic in
            relativePathByDisplayPath[diagnostic.path]
        }
    }
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
