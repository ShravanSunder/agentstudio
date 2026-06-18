import SwiftSyntax

protocol ArchitectureRule: Sendable {
    var id: String { get }
    var severity: ArchitectureSeverity { get }
    var message: String { get }

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic]
}

extension ArchitectureRule {
    func diagnostic(
        context: ArchitectureLintContext,
        position: AbsolutePosition,
        message: String? = nil
    ) -> ArchitectureDiagnostic {
        let location = context.location(for: position)
        return ArchitectureDiagnostic(
            path: context.path,
            line: location.line,
            column: location.column,
            severity: severity,
            ruleID: id,
            message: message ?? self.message
        )
    }
}

enum ArchitectureRuleRegistry {
    static let rules: [any ArchitectureRule] = [
        ImportDirectionRule(),
        SharedComponentsStatelessRule(),
        AtomLibGenericRule(),
        DerivedValueDeclaredInputsRule(),
        RepoCacheKeyedReadsRule(),
        WorktreeEnrichmentComparatorRule(),
        StateActorPathRule(),
        IPCProgrammaticControlBoundaryRule(),
        AppIPCPortBoundaryRule(),
        IPCCompositionLocationRule(),
        IPCPublicSurfaceSanitizationRule(),
        IPCNoDirectAtomAccessRule(),
        ForbiddenArchitectureMarkerRule(),
        GenericClockSleepRule(),
        TestTaskSleepRule(),
    ]
}
