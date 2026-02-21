import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)

final class PushSnapshotTests {
    @Test
    func test_diffStatusSlice_codable() throws {
        let snapshot = DiffStatusSlice(status: .idle, error: nil, epoch: 1)
        let data = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["epoch"] as? Int == 1)
    }

    @Test
    func test_diffStatusSlice_equatable() {
        let a = DiffStatusSlice(status: .idle, error: nil, epoch: 1)
        let b = DiffStatusSlice(status: .idle, error: nil, epoch: 1)
        let c = DiffStatusSlice(status: .loading, error: nil, epoch: 1)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func test_connectionSlice_codable() throws {
        let snapshot = ConnectionSlice(health: .connected, latencyMs: 3)
        let data = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["latencyMs"] as? Int == 3)
    }
}
