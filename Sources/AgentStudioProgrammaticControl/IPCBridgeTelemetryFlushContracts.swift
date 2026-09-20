import Foundation

package struct IPCBridgeTelemetryFlushParams: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let handle: String
    package let correlationId: UUID

    package init(handle: String, correlationId: UUID) {
        self.handle = handle
        self.correlationId = correlationId
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            IPCRequestSchemaFields.pane(),
            IPCRequestSchemaFields.correlation,
        ])
    }
}
