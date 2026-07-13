import SwiftSyntax

protocol ArchitectureRule: Sendable {
    var id: String { get }
    var severity: ArchitectureSeverity { get }
    var message: String { get }

    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule
    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic]
}

extension ArchitectureRule {
    func prepared(for contexts: [ArchitectureLintContext]) -> any ArchitectureRule {
        self
    }

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
        FeatureAppIPCImportBoundaryRule(),
        IPCPublicSurfaceSanitizationRule(),
        IPCNoDirectAtomAccessRule(),
        ForbiddenArchitectureMarkerRule(),
        GenericClockSleepRule(),
        TestTaskSleepRule(),
        TooltipSourceRule(),
        EventBusSubscriberPolicyRule(),
        RuntimeSignalPlaneRule(),
        FilesystemObservationSlotRegistryOwnershipRule(),
    ]
}
