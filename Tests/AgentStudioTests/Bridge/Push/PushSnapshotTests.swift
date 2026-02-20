import XCTest

@testable import AgentStudio

final class PushSnapshotTests: XCTestCase {
    func test_diffStatusSlice_codable() throws {
        let snapshot = DiffStatusSlice(status: .idle, error: nil, epoch: 1)
        let data = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["epoch"] as? Int, 1)
    }

    func test_diffStatusSlice_equatable() {
        let a = DiffStatusSlice(status: .idle, error: nil, epoch: 1)
        let b = DiffStatusSlice(status: .idle, error: nil, epoch: 1)
        let c = DiffStatusSlice(status: .loading, error: nil, epoch: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func test_connectionSlice_codable() throws {
        let snapshot = ConnectionSlice(health: .connected, latencyMs: 3)
        let data = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["latencyMs"] as? Int, 3)
    }
}
