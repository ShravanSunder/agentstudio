import Foundation

/// One committed report's location in the CLI-owned store.
package struct IPCLifecycleReportPosition: Codable, Equatable, Sendable {
    package let storeId: UUID
    package let sequence: Int64
    package init(storeId: UUID, sequence: Int64) {
        self.storeId = storeId
        self.sequence = sequence
    }
}
