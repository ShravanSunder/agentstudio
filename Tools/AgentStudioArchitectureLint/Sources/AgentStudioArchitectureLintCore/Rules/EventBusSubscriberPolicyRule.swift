import SwiftSyntax

struct EventBusSubscriberPolicyRule: ArchitectureRule {
    let id = "agentstudio_eventbus_subscriber_policy_required"
    let severity = ArchitectureSeverity.error
    let message =
        "Production EventBus subscribers must call subscribe(policy:subscriberName:) or waitForFirst(policy:subscriberName:) with an explicit BusSubscriberPolicy"

    func validate(context: ArchitectureLintContext) -> [ArchitectureDiagnostic] {
        let path = context.normalizedPath
        let pathForMatching = path.hasPrefix("/") ? path : "/\(path)"
        let classifier = AgentStudioPathClassifier(path: pathForMatching)
        guard classifier.isAgentStudioSource else {
            return []
        }

        let symbolVisitor = EventBusSymbolVisitor()
        symbolVisitor.walk(context.sourceFile)

        let visitor = EventBusSubscriberPolicyVisitor(eventBusNames: symbolVisitor.eventBusNames)
        visitor.walk(context.sourceFile)
        return visitor.violations.map {
            diagnostic(context: context, position: $0.position, message: $0.message)
        }
    }
}

private final class EventBusSymbolVisitor: SyntaxVisitor {
    private(set) var eventBusNames: Set<String> = []

    override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                continue
            }
            if Self.isEventBusType(binding.typeAnnotation?.type.trimmedDescription) {
                eventBusNames.insert(identifier.identifier.text)
                continue
            }
            if Self.isEventBusBackedExpression(
                binding.initializer?.value.trimmedDescription,
                knownEventBusNames: eventBusNames
            ) {
                eventBusNames.insert(identifier.identifier.text)
            }
        }
    }

    override func visitPost(_ node: FunctionParameterSyntax) {
        guard Self.isEventBusType(node.type.trimmedDescription) else {
            return
        }
        eventBusNames.insert(node.secondName?.text ?? node.firstName.text)
    }

    private static func isEventBusType(_ typeDescription: String?) -> Bool {
        guard let typeDescription else {
            return false
        }
        return typeDescription.contains("EventBus<") || typeDescription.contains("EventBus <")
    }

    private static func isEventBusBackedExpression(
        _ expressionDescription: String?,
        knownEventBusNames: Set<String>
    ) -> Bool {
        guard let expressionDescription else {
            return false
        }
        if expressionDescription == "PaneRuntimeEventBus.shared" || expressionDescription == "AppEventBus.shared" {
            return true
        }
        if let lastSegment = expressionDescription.split(separator: ".").last,
            knownEventBusNames.contains(String(lastSegment))
        {
            return true
        }
        return false
    }
}

private final class EventBusSubscriberPolicyVisitor: SyntaxVisitor {
    private(set) var violations: [ArchitectureViolation] = []
    private let eventBusNames: Set<String>

    init(eventBusNames: Set<String>, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.eventBusNames = eventBusNames
        super.init(viewMode: viewMode)
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return
        }
        let memberName = memberAccess.declName.baseName.text
        if memberName == "subscribe" {
            validateSubscribeCall(node, memberAccess: memberAccess)
        } else if memberName == "waitForFirst" {
            validateWaitForFirstCall(node, memberAccess: memberAccess)
        }
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        let functionName = node.name.text
        let bodyDescription = node.body?.trimmedDescription ?? ""
        let callsEventBusSubscriber =
            bodyDescription.contains(".subscribe(") || bodyDescription.contains(".waitForFirst")
        for parameter in node.signature.parameterClause.parameters {
            let parameterName = parameter.secondName?.text ?? parameter.firstName.text
            guard parameter.defaultValue != nil,
                parameterName == "policy" || parameterName == "bufferingPolicy"
                    || parameter.type.trimmedDescription == "BusSubscriberPolicy"
            else {
                continue
            }
            guard functionName == "subscribe" || functionName == "waitForFirst" || callsEventBusSubscriber else {
                continue
            }
            violations.append(
                ArchitectureViolation(
                    position: parameter.positionAfterSkippingLeadingTrivia,
                    message: "Production EventBus subscriber helpers must not provide default policy arguments"
                )
            )
        }
        if node.signature.parameterClause.parameters.isEmpty,
            returnsEventBusSubscription(node),
            callsEventBusSubscriber
        {
            violations.append(
                ArchitectureViolation(
                    position: node.name.positionAfterSkippingLeadingTrivia,
                    message:
                        "Production EventBus subscriber helpers must not hide policy behind zero-argument overloads"
                )
            )
        }
    }

    private func returnsEventBusSubscription(_ node: FunctionDeclSyntax) -> Bool {
        guard let returnDescription = node.signature.returnClause?.type.trimmedDescription else {
            return false
        }
        return returnDescription.contains("EventBusSubscription")
    }

    private func validateSubscribeCall(_ node: FunctionCallExprSyntax, memberAccess: MemberAccessExprSyntax) {
        guard isEventBusBackedReceiver(memberAccess.base) else {
            return
        }
        let argumentLabels = argumentLabels(node)
        if argumentLabels.contains("bufferingPolicy") {
            violations.append(
                ArchitectureViolation(
                    position: memberAccess.positionAfterSkippingLeadingTrivia,
                    message:
                        "Production EventBus subscriber call sites must use BusSubscriberPolicy, not raw AsyncStream bufferingPolicy"
                )
            )
            return
        }
        guard argumentLabels.contains("policy") else {
            violations.append(
                ArchitectureViolation(
                    position: memberAccess.positionAfterSkippingLeadingTrivia,
                    message: "Production EventBus subscriber call sites must pass an explicit BusSubscriberPolicy"
                )
            )
            return
        }
    }

    private func validateWaitForFirstCall(_ node: FunctionCallExprSyntax, memberAccess: MemberAccessExprSyntax) {
        guard isEventBusBackedReceiver(memberAccess.base) else {
            return
        }
        guard argumentLabels(node).contains("policy") else {
            violations.append(
                ArchitectureViolation(
                    position: memberAccess.positionAfterSkippingLeadingTrivia,
                    message: "Production EventBus wait helpers must pass an explicit BusSubscriberPolicy"
                )
            )
            return
        }
    }

    private func argumentLabels(_ node: FunctionCallExprSyntax) -> Set<String> {
        Set(
            node.arguments.compactMap { argument in
                argument.label?.text
            })
    }

    private func isEventBusBackedReceiver(_ expression: ExprSyntax?) -> Bool {
        guard let expression else {
            return false
        }
        let description = expression.trimmedDescription
        if description == "PaneRuntimeEventBus.shared" || description == "AppEventBus.shared" {
            return true
        }
        if let lastSegment = description.split(separator: ".").last,
            eventBusNames.contains(String(lastSegment))
        {
            return true
        }
        return false
    }
}
