import Foundation

actor AgentStudioJSONLTraceWriter {
    private let fileURL: URL
    private let rotatedFileURL: URL
    private let retainedLineLimit: Int
    private let maximumFileSizeBytes: UInt64?
    private let encoder: AgentStudioJSONLTraceEncoder
    private let fileManager: FileManager

    private var bufferedLines: [String] = []
    private(set) var droppedLineCount = 0

    init(
        fileURL: URL,
        retainedLineLimit: Int = 2048,
        maximumFileSizeBytes: UInt64? = 20 * 1024 * 1024,
        encoder: AgentStudioJSONLTraceEncoder = AgentStudioJSONLTraceEncoder(),
        fileManager: FileManager = .default
    ) {
        precondition(retainedLineLimit > 0, "retainedLineLimit must be positive")
        self.fileURL = fileURL
        self.rotatedFileURL = fileURL.appendingPathExtension("1")
        self.retainedLineLimit = retainedLineLimit
        self.maximumFileSizeBytes = maximumFileSizeBytes
        self.encoder = encoder
        self.fileManager = fileManager
    }

    func append(_ record: AgentStudioTraceRecord) throws {
        let line = try encoder.encodeLine(record)
        bufferedLines.append(line)
        trimBufferIfNeeded()
    }

    func flush() throws {
        guard !bufferedLines.isEmpty else { return }

        let data = Data(bufferedLines.joined().utf8)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try rotateFileIfNeeded(appendingByteCount: UInt64(data.count))
        try append(data, to: fileURL)
        bufferedLines.removeAll(keepingCapacity: true)
    }

    private func trimBufferIfNeeded() {
        guard bufferedLines.count > retainedLineLimit else { return }
        let overflowCount = bufferedLines.count - retainedLineLimit
        bufferedLines.removeFirst(overflowCount)
        droppedLineCount += overflowCount
    }

    private func append(_ data: Data, to fileURL: URL) throws {
        if fileManager.fileExists(atPath: fileURL.path) {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer {
                try? fileHandle.close()
            }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    private func rotateFileIfNeeded(appendingByteCount: UInt64) throws {
        guard
            let maximumFileSizeBytes,
            fileManager.fileExists(atPath: fileURL.path),
            try existingFileSize() + appendingByteCount > maximumFileSizeBytes
        else { return }

        if fileManager.fileExists(atPath: rotatedFileURL.path) {
            try fileManager.removeItem(at: rotatedFileURL)
        }
        try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
    }

    private func existingFileSize() throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
