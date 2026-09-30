/// A scope's history boundary, captured under the recorder's append lock.
package struct OpeningPosition<Scope: Hashable & Sendable>: Sendable {
    package let recorderIdentity: ObjectIdentifier
    package let scope: Scope
    package let historyIndex: Int
}
