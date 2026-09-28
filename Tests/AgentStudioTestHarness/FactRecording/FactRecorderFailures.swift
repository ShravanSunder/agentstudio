package struct UnexpectedFact: Error, Sendable {
    package let expected: String
    package let actual: String
    package let scope: String
    package let callSite: String
}

package struct SourceEnded: Error, Sendable {
    package let expected: String
    package let scope: String
    package let callSite: String
}

package struct FactsLost: Error, Sendable {
    package let description: String
    package let expected: String
    package let scope: String
    package let callSite: String
}

package struct Cancelled: Error, Sendable {
    package let expected: String
    package let scope: String
    package let callSite: String
}

package struct ConcurrentExpectation: Error, Sendable {
    package let expected: String
    package let scope: String
    package let callSite: String
}

package struct DuplicateClose: Error, Sendable {
    package let actual: String
    package let scope: String
    package let callSite: String
}

package struct FactAfterClose: Error, Sendable {
    package let actual: String
    package let scope: String
    package let callSite: String
}

package struct OpeningPositionMisuse: Error, Sendable {
    package let scope: String
    package let callSite: String
}
