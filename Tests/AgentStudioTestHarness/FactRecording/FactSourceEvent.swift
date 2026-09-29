package enum FactSourceEvent<Scope: Hashable & Sendable, Fact: Sendable>: Sendable {
    case fact(scope: Scope, fact: Fact, sequence: UInt64)
    case ended
    case lost(description: String)
    case cancelled
}
