import SwiftSyntax

/// A performance probe or telemetry recorder that reports through MainActor
/// goes blind exactly when it matters: during a MainActor stall its periodic
/// report waits behind the stall it should be measuring.
///
/// Scope: source files under a `Diagnostics/` or `Telemetry/` folder, or
/// whose name contains `Recorder`, `Telemetry`, `Probe` or `Sampler`. Flags
/// `MainActor.run`, `@MainActor` closures (`Task { @MainActor in … }`), and a
/// `*Reporter` type or typealias marked `@MainActor`. Other `@MainActor`
/// types in those files (proof harnesses, pilot views) are not reporters.
struct ProbeReportsOffMainRule: ArchitectureRule {
    let id = "agentstudio_probe_reports_off_main"
    let severity = ArchitectureSeverity.error
    let message =
        "Probe and recorder paths must report off MainActor; a MainActor stall would delay the report that "
        + "measures it"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        guard Self.isProbeOrRecorderPath(context.normalizedPath) else {
            return []
        }
        let hopVisitor = MainActorHopVisitor()
        hopVisitor.walk(context.sourceFile)
        let reporterVisitor = MainActorReporterDeclarationVisitor()
        reporterVisitor.walk(context.sourceFile)
        return (hopVisitor.positions + reporterVisitor.positions)
            .sorted { $0.utf8Offset < $1.utf8Offset }
            .map { diagnostic(context: context, position: $0) }
    }

    static func isProbeOrRecorderPath(_ path: String) -> Bool {
        guard ("/" + path).contains("/Sources/"), path.hasSuffix(".swift") else {
            return false
        }
        if path.contains("/Diagnostics/") || path.contains("/Telemetry/") {
            return true
        }
        let fileName = path.split(separator: "/").last.map(String.init) ?? path
        return ["Recorder", "Telemetry", "Probe", "Sampler"].contains { fileName.contains($0) }
    }
}

private final class MainActorReporterDeclarationVisitor: SyntaxVisitor {
    private(set) var positions: [AbsolutePosition] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visitPost(_ node: TypeAliasDeclSyntax) {
        guard node.name.text.hasSuffix("Reporter"),
            node.initializer.value.tokens(viewMode: .sourceAccurate).contains(where: {
                $0.text == "MainActor"
            })
        else {
            return
        }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        recordIfMainActorReporter(name: node.name.text, attributes: node.attributes, node: Syntax(node))
    }

    override func visitPost(_ node: StructDeclSyntax) {
        recordIfMainActorReporter(name: node.name.text, attributes: node.attributes, node: Syntax(node))
    }

    private func recordIfMainActorReporter(name: String, attributes: AttributeListSyntax, node: Syntax) {
        guard name.hasSuffix("Reporter"), attributes.containsAttribute("@MainActor") else {
            return
        }
        positions.append(node.positionAfterSkippingLeadingTrivia)
    }
}
