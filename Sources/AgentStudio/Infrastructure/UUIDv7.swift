import Foundation
import Security

/// UUID v7 generator (RFC 9562).
///
/// UUID v7 encodes a 48-bit millisecond Unix timestamp in the high bits,
/// making UUIDs lexicographically sortable by creation time at millisecond
/// granularity when compared as standard UUID strings.
/// UUIDs generated within the same millisecond are not strictly monotonic
/// because their lower bits are random.
///
/// Byte layout (128 bits, big-endian):
///   Bytes 0-5   (48 bits): Unix timestamp in milliseconds
///   Byte  6     (8 bits):  version (0111) | rand_a high nibble
///   Byte  7     (8 bits):  rand_a low byte
///   Byte  8     (8 bits):  variant (10) | rand_b high 6 bits
///   Bytes 9-15  (56 bits): rand_b remaining
///
/// This lives in Infrastructure/ because it's a domain-agnostic utility
/// that imports nothing internal.
enum UUIDv7 {

    /// Generate a new UUID v7 with the current timestamp.
    static func generate() -> UUID {
        generate(timestamp: Date())
    }

    /// Generate a UUID v7 with an explicit timestamp (for testing).
    static func generate(timestamp: Date) -> UUID {
        let milliseconds = UInt64(timestamp.timeIntervalSince1970 * 1000)
        return generate(milliseconds: milliseconds)
    }

    /// Generate a UUID v7 from raw milliseconds since Unix epoch.
    static func generate(milliseconds: UInt64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)

        // Bytes 0-5: 48-bit timestamp (big-endian, most significant first)
        bytes[0] = UInt8((milliseconds >> 40) & 0xFF)
        bytes[1] = UInt8((milliseconds >> 32) & 0xFF)
        bytes[2] = UInt8((milliseconds >> 24) & 0xFF)
        bytes[3] = UInt8((milliseconds >> 16) & 0xFF)
        bytes[4] = UInt8((milliseconds >> 8) & 0xFF)
        bytes[5] = UInt8(milliseconds & 0xFF)

        // Bytes 6-15: fill with cryptographic random
        let status = SecRandomCopyBytes(kSecRandomDefault, 10, &bytes[6])
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status)")

        // Byte 6: set version to 7 (0111 in high nibble, preserve low nibble)
        bytes[6] = (bytes[6] & 0x0F) | 0x70

        // Byte 8: set variant to RFC 9562/4122 layout (10 in high 2 bits, preserve low 6 bits)
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    /// Extract the 48-bit millisecond timestamp from a UUID v7.
    /// Returns nil if the UUID is not version 7.
    static func timestamp(from uuid: UUID) -> Date? {
        let bytes = uuidBytes(uuid)
        // Check version: byte 6 high nibble must be 0x7
        guard (bytes[6] >> 4) == 0x07 else { return nil }

        let ms: UInt64 =
            (UInt64(bytes[0]) << 40)
            | (UInt64(bytes[1]) << 32)
            | (UInt64(bytes[2]) << 24)
            | (UInt64(bytes[3]) << 16)
            | (UInt64(bytes[4]) << 8)
            | UInt64(bytes[5])

        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    /// Check whether a UUID is version 7.
    static func isV7(_ uuid: UUID) -> Bool {
        let bytes = uuidBytes(uuid)
        return (bytes[6] >> 4) == 0x07
    }

    // MARK: - Internal

    private static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        let t = uuid.uuid
        return [
            t.0, t.1, t.2, t.3, t.4, t.5, t.6, t.7,
            t.8, t.9, t.10, t.11, t.12, t.13, t.14, t.15,
        ]
    }
}
