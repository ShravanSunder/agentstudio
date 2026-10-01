import AgentStudioInfrastructure
import Foundation

/// Pure byte-domain rules. No decoding/re-encoding alters captured bytes.
enum ScrollbackPersistedForm {
    static let resetPrefix = Data("\u{1B}c".utf8)
    static let truncationMarker = Data("[older output omitted]\r\n".utf8)

    static func make(_ capture: Data, byteCap: Int) -> Data {
        let header = resetPrefix + truncationMarker
        precondition(byteCap >= header.count && byteCap <= AppPolicies.Restore.snapshotByteCap)
        if capture.count <= byteCap - resetPrefix.count {
            return resetPrefix + capture
        }
        let earliestOffset = capture.count - (byteCap - header.count)
        let cutOffset = capture.withUnsafeBytes { rawBytes in
            safeSuffixOffset(in: rawBytes.bindMemory(to: UInt8.self), atOrAfter: earliestOffset)
        }
        var persisted = header
        persisted.append(capture.suffix(capture.count - cutOffset))
        return persisted
    }

    /// Parse from the beginning: a local look-behind cannot distinguish
    /// ordinary text from the middle of a long OSC/DCS payload.
    private static func safeSuffixOffset(in bytes: UnsafeBufferPointer<UInt8>, atOrAfter minimum: Int) -> Int {
        var escapeState = EscapeBoundaryState.ground
        for offset in bytes.indices {
            let byte = bytes[offset]
            if offset >= minimum, escapeState == .ground, byte & 0xC0 != 0x80 {
                return offset
            }
            escapeState.consume(byte)
        }
        // An unterminated sequence crossing the cut has no safe suffix;
        // the bounded reset and omission marker are still replayable.
        return bytes.count
    }
}

private enum EscapeBoundaryState: Equatable {
    case ground
    case escape
    case escapeIntermediate
    case csi
    case controlString(osc: Bool)
    case controlStringEscape(osc: Bool)

    mutating func consume(_ byte: UInt8) {
        if byte == 0x18 || byte == 0x1A {
            self = .ground
            return
        }
        switch self {
        case .ground:
            if byte == 0x1B { self = .escape }
        case .escape:
            switch byte {
            case 0x1B: break
            case 0x5B: self = .csi
            case 0x5D: self = .controlString(osc: true)
            case 0x50, 0x58, 0x5E, 0x5F: self = .controlString(osc: false)
            case 0x20...0x2F: self = .escapeIntermediate
            case 0x30...0x7E: self = .ground
            default: break
            }
        case .escapeIntermediate:
            if byte == 0x1B { self = .escape } else if (0x30...0x7E).contains(byte) { self = .ground }
        case .csi:
            if byte == 0x1B { self = .escape } else if (0x40...0x7E).contains(byte) { self = .ground }
        case .controlString(let osc):
            if byte == 0x1B { self = .controlStringEscape(osc: osc) } else if osc && byte == 0x07 { self = .ground }
        case .controlStringEscape(let osc):
            if byte == 0x5C || (osc && byte == 0x07) {
                self = .ground
            } else if byte != 0x1B {
                self = .controlString(osc: osc)
            }
        }
    }
}
