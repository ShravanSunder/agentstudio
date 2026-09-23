import SwiftSyntax

extension ExprSyntax {
    /// The expression names the concurrency `Task` type itself, however it is
    /// spelled: bare `Task`, module-qualified `Swift.Task` / `_Concurrency.Task`,
    /// or specialized `Task<Never, Never>`.
    ///
    /// Shared by the rules that care what `Task` is being asked to do:
    /// `TestTaskSleepRule` (`Task.sleep`) and `TestPollingWaitRule`
    /// (`Task.yield` inside a loop).
    var isTaskTypeReference: Bool {
        if let reference = self.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text == "Task"
        }

        if let memberAccess = self.as(MemberAccessExprSyntax.self) {
            guard memberAccess.declName.baseName.text == "Task",
                let baseReference = memberAccess.base?.as(DeclReferenceExprSyntax.self)
            else {
                return false
            }
            return baseReference.baseName.text == "Swift"
                || baseReference.baseName.text == "_Concurrency"
        }

        if let specialization = self.as(GenericSpecializationExprSyntax.self) {
            return specialization.expression.isTaskTypeReference
        }

        return false
    }
}
