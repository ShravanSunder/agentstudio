import SwiftSyntax

enum FilesystemSlotConstructionPolicy {
    enum Owner: Sendable {
        case registryTransition
        case admissionPlannerCompletion
    }

    enum ProtectedConstructor: String, CaseIterable, Sendable {
        case binding = "FilesystemObservationSlotBinding"
        case bindingIdentity = "FilesystemObservationSlotBindingIdentity"
        case controlBlockIdentity = "FilesystemObservationControlBlockIdentity"
        case nativeGenerationIdentity = "FilesystemObservationNativeGenerationIdentity"
        case startingNativeLifetime = "FilesystemObservationStartingNativeLifetime"

        var approvedOwner: Owner {
            switch self {
            case .bindingIdentity, .controlBlockIdentity, .nativeGenerationIdentity:
                .registryTransition
            case .binding, .startingNativeLifetime:
                .admissionPlannerCompletion
            }
        }
    }

    static func isUUIDv7Generation(_ node: FunctionCallExprSyntax) -> Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
            memberAccess.declName.baseName.text == "generate",
            let base = memberAccess.base
        else {
            return false
        }
        return terminalTypeName(base.trimmedDescription) == "UUIDv7"
    }

    static func protectedConstructor(
        expressionDescription: String
    ) -> ProtectedConstructor? {
        var description = expressionDescription
        if description.hasSuffix(".init") {
            description.removeLast(".init".count)
        }
        let terminalName = terminalTypeName(description)
        return ProtectedConstructor.allCases.first { $0.rawValue == terminalName }
    }

    static func directMemberName(_ expression: ExprSyntax) -> String? {
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        if let declarationReference = expression.as(DeclReferenceExprSyntax.self) {
            return declarationReference.baseName.text
        }
        return nil
    }

    static func hasReservationParameter(_ function: FunctionDeclSyntax) -> Bool {
        function.signature.parameterClause.parameters.contains { parameter in
            let localName = parameter.secondName?.text ?? parameter.firstName.text
            return localName == "reservation"
        }
    }

    static func terminalTypeName(_ description: String) -> String {
        description.split(separator: ".").last.map(String.init) ?? description
    }

    static func isDirectAdmissionPlannerMember(_ function: FunctionDeclSyntax) -> Bool {
        guard function.modifiers.contains(where: { $0.name.text == "static" }) else {
            return false
        }
        var ancestor = function.parent
        while let current = ancestor {
            if let owner = current.as(EnumDeclSyntax.self) {
                return owner.name.text == "FilesystemObservationSlotAdmissionPlanner"
                    && isTopLevel(owner)
            }
            if current.is(FunctionDeclSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(SubscriptDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(ClosureExprSyntax.self)
                || current.is(ExtensionDeclSyntax.self)
                || current.is(ClassDeclSyntax.self)
                || current.is(StructDeclSyntax.self)
                || current.is(ActorDeclSyntax.self)
            {
                return false
            }
            ancestor = current.parent
        }
        return false
    }

    private static func isTopLevel(_ node: some SyntaxProtocol) -> Bool {
        var ancestor = node.parent
        while let current = ancestor {
            if current.is(SourceFileSyntax.self) {
                return true
            }
            if current.is(ClassDeclSyntax.self)
                || current.is(StructDeclSyntax.self)
                || current.is(EnumDeclSyntax.self)
                || current.is(ActorDeclSyntax.self)
                || current.is(ExtensionDeclSyntax.self)
                || current.is(FunctionDeclSyntax.self)
                || current.is(InitializerDeclSyntax.self)
                || current.is(SubscriptDeclSyntax.self)
                || current.is(AccessorDeclSyntax.self)
                || current.is(ClosureExprSyntax.self)
            {
                return false
            }
            ancestor = current.parent
        }
        return false
    }
}
