import Foundation

/// One pane-valued wire selector with the shared self/UUID/pane:N vocabulary.
/// App admission resolves this intent to a canonical pane UUID.
package struct IPCPaneSelector: IPCSchemaProviding, Equatable, Sendable {
    package let rawValue: String
    package let parsed: IPCTargetSelector

    package init(rawValue: String) throws {
        self.rawValue = rawValue
        parsed = try IPCTargetSelector.parse(rawValue, expectedKind: .pane)
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        IPCRequestSchemaFields.paneSelector
    }
}
