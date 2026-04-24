import Foundation

enum ChaosStoreSeeder {
    struct Payloads {
        let validJSON: String
        let sliceMissingJSON: String
        let sliceTypeErrorJSON: String
        let sliceUnknownEnumJSON: String
        let unknownSchemaVersionJSON: String
    }

    enum Flavor: CaseIterable {
        case missing
        case empty
        case truncatedJSON
        case wrongShape
        case sliceMissing
        case sliceTypeError
        case sliceUnknownEnum
        case unknownSchemaVersion
        case garbage

        var corruptsWholeFile: Bool {
            switch self {
            case .empty, .truncatedJSON, .wrongShape, .garbage:
                return true
            case .missing, .sliceMissing, .sliceTypeError, .sliceUnknownEnum:
                return false
            case .unknownSchemaVersion:
                return true
            }
        }
    }

    static func seed(
        _ flavor: Flavor,
        at url: URL,
        payloads: Payloads
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        switch flavor {
        case .missing:
            try? FileManager.default.removeItem(at: url)
        case .empty:
            try Data().write(to: url, options: .atomic)
        case .truncatedJSON:
            try Data("{".utf8).write(to: url, options: .atomic)
        case .wrongShape:
            try Data("[1,2,3]".utf8).write(to: url, options: .atomic)
        case .sliceMissing:
            try Data(payloads.sliceMissingJSON.utf8).write(to: url, options: .atomic)
        case .sliceTypeError:
            try Data(payloads.sliceTypeErrorJSON.utf8).write(to: url, options: .atomic)
        case .sliceUnknownEnum:
            try Data(payloads.sliceUnknownEnumJSON.utf8).write(to: url, options: .atomic)
        case .unknownSchemaVersion:
            try Data(payloads.unknownSchemaVersionJSON.utf8).write(to: url, options: .atomic)
        case .garbage:
            try Data([0xff, 0x00, 0xde, 0xad, 0xbe, 0xef]).write(to: url, options: .atomic)
        }
    }
}
