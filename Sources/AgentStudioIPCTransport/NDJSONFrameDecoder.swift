import Foundation

public struct NDJSONFrameError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case frameTooLarge
        case embeddedNewline
        case invalidUTF8
    }

    public let reason: Reason
    /// Measured size of the offending frame, so an overflow is reported as a
    /// finite condition rather than an opaque failure. Zero when the reason
    /// carries no size, such as an embedded newline.
    public let frameByteCount: Int
    /// Bound the frame was measured against.
    public let maximumFrameBytes: Int

    public init(reason: Reason, frameByteCount: Int = 0, maximumFrameBytes: Int = 0) {
        self.reason = reason
        self.frameByteCount = frameByteCount
        self.maximumFrameBytes = maximumFrameBytes
    }
}

public enum NDJSONFrameEncoder {
    public static func encode(_ frame: String, maxFrameBytes: Int) throws -> Data {
        precondition(maxFrameBytes > 0, "maxFrameBytes must be positive")

        guard !frame.contains("\n"), !frame.contains("\r") else {
            throw NDJSONFrameError(reason: .embeddedNewline)
        }

        let frameByteCount = frame.utf8.count
        guard frameByteCount <= maxFrameBytes else {
            throw NDJSONFrameError(
                reason: .frameTooLarge,
                frameByteCount: frameByteCount,
                maximumFrameBytes: maxFrameBytes
            )
        }

        return Data((frame + "\n").utf8)
    }
}

public struct NDJSONFrameDecoder: Sendable {
    public private(set) var pendingByteCount = 0

    private let maxFrameBytes: Int
    private var pending = Data()

    public init(maxFrameBytes: Int) {
        precondition(maxFrameBytes > 0, "maxFrameBytes must be positive")
        self.maxFrameBytes = maxFrameBytes
    }

    public mutating func append(_ data: Data) throws -> [String] {
        pending.append(data)
        pendingByteCount = pending.count

        var frames: [String] = []
        while let newlineIndex = pending.firstIndex(of: 0x0a) {
            let frameData = pending[..<newlineIndex]
            guard frameData.count <= maxFrameBytes else {
                let frameByteCount = frameData.count
                clearPending()
                throw NDJSONFrameError(
                    reason: .frameTooLarge,
                    frameByteCount: frameByteCount,
                    maximumFrameBytes: maxFrameBytes
                )
            }

            let nextFrameStart = pending.index(after: newlineIndex)
            pending.removeSubrange(..<nextFrameStart)
            pendingByteCount = pending.count

            guard !frameData.isEmpty else {
                continue
            }

            let normalizedFrameData = frameData.last == 0x0d ? frameData.dropLast() : frameData
            guard let frame = String(data: normalizedFrameData, encoding: .utf8) else {
                clearPending()
                throw NDJSONFrameError(reason: .invalidUTF8)
            }

            frames.append(frame)
        }

        guard pending.count <= maxFrameBytes else {
            let pendingFrameByteCount = pending.count
            clearPending()
            throw NDJSONFrameError(
                reason: .frameTooLarge,
                frameByteCount: pendingFrameByteCount,
                maximumFrameBytes: maxFrameBytes
            )
        }

        return frames
    }

    private mutating func clearPending() {
        pending.removeAll(keepingCapacity: true)
        pendingByteCount = 0
    }
}
