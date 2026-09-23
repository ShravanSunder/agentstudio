import Foundation

package enum IPCTargetSelectorError: Error, Equatable, Sendable {
    case invalidSelector
    case wrongTargetKind
}

/// Wire parsing preserves declared kind and unresolved self/ordinal intent.
/// App admission resolves membership and authority; parsing does neither.
package enum IPCTargetSelector: Equatable, Sendable {
    case selfPane
    case paneOrdinal(Int)
    case canonical(kind: IPCHandleKind, id: UUID)

    package static func parse(_ rawValue: String, expectedKind: IPCHandleKind) throws -> Self {
        if rawValue == "self" {
            guard expectedKind == .pane else { throw IPCTargetSelectorError.wrongTargetKind }
            return .selfPane
        }
        if let identifier = UUID(uuidString: rawValue) {
            return .canonical(kind: expectedKind, id: identifier)
        }
        let components = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2,
            let suppliedKind = IPCHandleKind(rawValue: String(components[0]))
        else { throw IPCTargetSelectorError.invalidSelector }
        guard suppliedKind == expectedKind else { throw IPCTargetSelectorError.wrongTargetKind }
        guard suppliedKind == .pane,
            let ordinal = Int(components[1]), ordinal > 0,
            String(ordinal) == components[1]
        else { throw IPCTargetSelectorError.invalidSelector }
        return .paneOrdinal(ordinal)
    }
}
