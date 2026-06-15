import Foundation

protocol BridgeTelemetryBatchIngesting: Sendable {
    func ingest(_ data: Data) async -> BridgeTelemetryIngestResult
}

extension BridgeTelemetryIngestor: BridgeTelemetryBatchIngesting {}
