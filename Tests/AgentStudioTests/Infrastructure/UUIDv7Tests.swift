import Foundation
import Testing

@testable import AgentStudio

@Suite
struct UUIDv7Tests {

    // MARK: - Version & Variant Bits

    @Test
    func generatedUUIDHasVersion7() {
        // Act
        let uuid = UUIDv7.generate()

        // Assert — byte 6 high nibble must be 0x7
        let byte6 = uuid.uuid.6
        #expect((byte6 >> 4) == 0x07, "Version nibble should be 7, got \(byte6 >> 4)")
    }

    @Test
    func generatedUUIDHasRFC4122Variant() {
        // Act
        let uuid = UUIDv7.generate()

        // Assert — byte 8 high 2 bits must be 10 (0x80..0xBF)
        let byte8 = uuid.uuid.8
        #expect((byte8 & 0xC0) == 0x80, "Variant bits should be 10, got \(String(byte8, radix: 2))")
    }

    @Test
    func versionAndVariantConsistentAcrossManyGenerations() {
        // Act & Assert — generate 100 UUIDs, all must be valid v7
        for _ in 0..<100 {
            let uuid = UUIDv7.generate()
            #expect((uuid.uuid.6 >> 4) == 0x07)
            #expect((uuid.uuid.8 & 0xC0) == 0x80)
        }
    }

    // MARK: - Timestamp Encoding

    @Test
    func timestampEncodesCurrentTimeWithinTolerance() {
        // Arrange
        let before = Date()

        // Act
        let uuid = UUIDv7.generate()

        // Assert — extracted timestamp within 100ms of generation time
        let after = Date()
        guard let extracted = UUIDv7.timestamp(from: uuid) else {
            Issue.record("Expected v7 UUID to have extractable timestamp")
            return
        }
        #expect(extracted >= before.addingTimeInterval(-0.1))
        #expect(extracted <= after.addingTimeInterval(0.1))
    }

    @Test
    func timestampFromExplicitDateRoundTrips() {
        // Arrange — use a known timestamp (truncated to ms precision)
        let knownDate = Date(timeIntervalSince1970: 1_708_000_000.123)

        // Act
        let uuid = UUIDv7.generate(timestamp: knownDate)
        let extracted = UUIDv7.timestamp(from: uuid)

        // Assert — within 1ms (floating point truncation)
        guard let extracted else {
            Issue.record("Expected extractable timestamp")
            return
        }
        let diffMs = abs(extracted.timeIntervalSince1970 - knownDate.timeIntervalSince1970) * 1000
        #expect(diffMs < 1.0, "Timestamp should round-trip within 1ms, got \(diffMs)ms drift")
    }

    @Test
    func timestampFromExplicitMillisecondsRoundTrips() {
        // Arrange
        let ms: UInt64 = 1_708_000_000_123

        // Act
        let uuid = UUIDv7.generate(milliseconds: ms)
        let extracted = UUIDv7.timestamp(from: uuid)

        // Assert
        guard let extracted else {
            Issue.record("Expected extractable timestamp")
            return
        }
        let extractedMs = UInt64(extracted.timeIntervalSince1970 * 1000)
        #expect(extractedMs == ms)
    }

    // MARK: - Monotonic Ordering

    @Test
    func sequentialUUIDsAreLexicographicallySorted() {
        // Arrange & Act — generate UUIDs with increasing timestamps
        var uuids: [UUID] = []
        for i in 0..<10 {
            let uuid = UUIDv7.generate(milliseconds: 1_700_000_000_000 + UInt64(i) * 1000)
            uuids.append(uuid)
        }

        // Assert — lexicographic order matches generation order
        let sorted = uuids.sorted { $0.uuidString < $1.uuidString }
        #expect(uuids == sorted, "UUIDs generated with increasing timestamps should be lexicographically sorted")
    }

    @Test
    func sameMillisecondProducesDifferentUUIDs() {
        // Arrange — same timestamp, different random bits
        let ms: UInt64 = 1_700_000_000_000

        // Act
        let uuid1 = UUIDv7.generate(milliseconds: ms)
        let uuid2 = UUIDv7.generate(milliseconds: ms)

        // Assert — same timestamp prefix but different random tails
        #expect(uuid1 != uuid2, "Two UUIDs at the same millisecond should differ in random bits")

        // Both share the same timestamp bytes (0-5)
        let hex1 = uuid1.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        let hex2 = uuid2.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        #expect(hex1 == hex2, "Timestamp portion (first 12 hex chars / 48 bits) should match")
    }

    // MARK: - Uniqueness

    @Test
    func generatedUUIDsAreUnique() {
        // Act
        var seen = Set<UUID>()
        for _ in 0..<1000 {
            let uuid = UUIDv7.generate()
            #expect(!seen.contains(uuid), "Duplicate UUID generated")
            seen.insert(uuid)
        }

        // Assert
        #expect(seen.count == 1000)
    }

    // MARK: - isV7

    @Test
    func isV7ReturnsTrueForGeneratedUUID() {
        let uuid = UUIDv7.generate()
        #expect(UUIDv7.isV7(uuid))
    }

    @Test
    func isV7ReturnsFalseForV4UUID() {
        let v4 = UUID()  // Foundation generates v4
        #expect(!UUIDv7.isV7(v4))
    }

    // MARK: - Timestamp Extraction Edge Cases

    @Test
    func timestampReturnsNilForV4UUID() {
        let v4 = UUID()
        #expect(UUIDv7.timestamp(from: v4) == nil)
    }

    @Test
    func timestampAtUnixEpoch() {
        // Arrange — timestamp 0 = 1970-01-01
        let uuid = UUIDv7.generate(milliseconds: 0)

        // Act
        let extracted = UUIDv7.timestamp(from: uuid)

        // Assert
        #expect(extracted?.timeIntervalSince1970 == 0)
    }

    // MARK: - UUID String Format

    @Test
    func generatedUUIDHasStandardStringFormat() {
        // Act
        let uuid = UUIDv7.generate()
        let str = uuid.uuidString

        // Assert — standard UUID format: 8-4-4-4-12 hex chars
        let parts = str.split(separator: "-")
        #expect(parts.count == 5)
        #expect(parts[0].count == 8)
        #expect(parts[1].count == 4)
        #expect(parts[2].count == 4)
        #expect(parts[3].count == 4)
        #expect(parts[4].count == 12)

        // Version character is at position 0 of the 3rd group
        #expect(parts[2].hasPrefix("7"), "Third group should start with version '7'")
    }
}
