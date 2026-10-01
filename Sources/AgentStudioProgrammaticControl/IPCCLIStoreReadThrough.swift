import Foundation

/// The identity and handled prefixes reported by the app's local cursors.
package struct IPCCLIStoreReadThrough: Codable, Equatable, Sendable, IPCSchemaProviding {
    package let storeId: UUID
    package let outbox: Int64
    package let lifecycleReport: Int64?

    package init(storeId: UUID, outbox: Int64, lifecycleReport: Int64? = nil) {
        self.storeId = storeId
        self.outbox = outbox
        self.lifecycleReport = lifecycleReport
    }

    package static func ipcSchema() throws -> IPCJSONSchema {
        // S3 red stand-in: no wire fields admitted until red is verified.
        .object(fields: [])
    }
}
