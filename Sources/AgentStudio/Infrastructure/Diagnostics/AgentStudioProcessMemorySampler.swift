import Darwin
import Foundation

struct AgentStudioProcessMemorySnapshot: Equatable, Sendable {
    let blocksInUse: UInt64
    let sizeInUseBytes: UInt64
    let maximumSizeInUseBytes: UInt64
    let sizeAllocatedBytes: UInt64

    var traceAttributes: [String: AgentStudioTraceValue] {
        [
            "agentstudio.performance.process.malloc.blocks_in_use": .int(Self.traceInteger(blocksInUse)),
            "agentstudio.performance.process.malloc.size_in_use_bytes": .int(Self.traceInteger(sizeInUseBytes)),
            "agentstudio.performance.process.malloc.maximum_size_in_use_bytes": .int(
                Self.traceInteger(maximumSizeInUseBytes)
            ),
            "agentstudio.performance.process.malloc.size_allocated_bytes": .int(
                Self.traceInteger(sizeAllocatedBytes)
            ),
        ]
    }

    static func captureAllMallocZones() -> Self {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Self(
            blocksInUse: UInt64(statistics.blocks_in_use),
            sizeInUseBytes: UInt64(statistics.size_in_use),
            maximumSizeInUseBytes: UInt64(statistics.max_size_in_use),
            sizeAllocatedBytes: UInt64(statistics.size_allocated)
        )
    }

    private static func traceInteger(_ value: UInt64) -> Int {
        value > UInt64(Int.max) ? Int.max : Int(value)
    }
}

final class AgentStudioProcessMemorySampler: @unchecked Sendable {
    typealias SnapshotProvider = @Sendable () -> AgentStudioProcessMemorySnapshot
    typealias WaitForNextSample = @Sendable () async -> Bool
    typealias SnapshotRecorder = @Sendable (AgentStudioProcessMemorySnapshot) -> Void

    private enum Lifecycle: Equatable {
        case idle
        case running
        case stopped
    }

    private let lock = NSLock()
    private let snapshotProvider: SnapshotProvider
    private let waitForNextSample: WaitForNextSample
    private let recordSnapshot: SnapshotRecorder

    private var lifecycle: Lifecycle = .idle
    private var samplingTask: Task<Void, Never>?

    init(
        snapshotProvider: @escaping SnapshotProvider = AgentStudioProcessMemorySnapshot.captureAllMallocZones,
        waitForNextSample: @escaping WaitForNextSample = AgentStudioProcessMemorySampler.waitOneSecond,
        recordSnapshot: @escaping SnapshotRecorder
    ) {
        self.snapshotProvider = snapshotProvider
        self.waitForNextSample = waitForNextSample
        self.recordSnapshot = recordSnapshot
    }

    deinit {
        samplingTask?.cancel()
    }

    func start() {
        lock.lock()
        guard lifecycle == .idle else {
            lock.unlock()
            return
        }
        lifecycle = .running
        // Sampling must not inherit MainActor from the app-owned performance recorder.
        // swiftlint:disable:next no_task_detached
        let task = Task.detached { [weak self] in
            guard let self else { return }
            self.sampleNow()
            while !Task.isCancelled, await self.waitForNextSample() {
                guard !Task.isCancelled else { return }
                self.sampleNow()
            }
        }
        samplingTask = task
        lock.unlock()
    }

    func sampleNow() {
        lock.withLock {
            guard lifecycle != .stopped else { return }
            recordSnapshot(snapshotProvider())
        }
    }

    func stop() async {
        let task = takeSamplingTaskForStop()
        task?.cancel()
        await task?.value
    }

    func cancel() {
        takeSamplingTaskForStop()?.cancel()
    }

    private func takeSamplingTaskForStop() -> Task<Void, Never>? {
        lock.withLock {
            guard lifecycle != .stopped else { return nil }
            lifecycle = .stopped
            let task = samplingTask
            samplingTask = nil
            return task
        }
    }

    private static func waitOneSecond() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}
