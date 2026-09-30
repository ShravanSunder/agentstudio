/// Test-side descriptions of an owner's scope and closed fact vocabulary.
package struct FactVocabulary<Scope: Hashable & Sendable, Fact: Sendable>: Sendable {
    package let describeScope: @Sendable (Scope) -> String
    package let describeFact: @Sendable (Fact) -> String
    package let isClosing: @Sendable (Scope, Fact) -> Bool

    package init(
        describeScope: @escaping @Sendable (Scope) -> String,
        describeFact: @escaping @Sendable (Fact) -> String,
        isClosing: @escaping @Sendable (Scope, Fact) -> Bool
    ) {
        self.describeScope = describeScope
        self.describeFact = describeFact
        self.isClosing = isClosing
    }
}
