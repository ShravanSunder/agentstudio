/// The source-side work that `finish()` must stop and join.
package protocol FactSourceHandle: Sendable {
    func stop() async
}
