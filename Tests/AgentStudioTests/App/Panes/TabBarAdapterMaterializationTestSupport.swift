import Foundation
import Synchronization

@testable import AgentStudio

func tabBarTelemetryElapsedMilliseconds(
    for eventName: String,
    in jsonLines: String
) throws -> Double {
    for jsonLine in jsonLines.split(separator: "\n") {
        let jsonData = Data(jsonLine.utf8)
        guard
            let record = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            record["body"] as? String == eventName,
            let attributes = record["attributes"] as? [String: Any],
            let elapsedMilliseconds = attributes["agentstudio.performance.elapsed_ms"] as? Double
        else {
            continue
        }
        return elapsedMilliseconds
    }
    throw TabBarTelemetryTestSupportError.missingElapsedDuration(eventName)
}

private enum TabBarTelemetryTestSupportError: Error {
    case missingElapsedDuration(String)
}

final class TabBarAdapterTestSignal: Sendable {
    private struct State {
        var didSignal = false
        var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    }

    private let state = Mutex(State())

    func signal() {
        let waiters = state.withLock { state in
            guard !state.didSignal else { return [CheckedContinuation<Bool, Never>]() }
            state.didSignal = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: true)
        }
    }

    func wait() async -> Bool {
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            let shouldResumeImmediately = state.withLock { state in
                guard !state.didSignal else { return true }
                state.waiters[waiterID] = continuation
                return false
            }
            if shouldResumeImmediately {
                continuation.resume(returning: true)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5)) { [weak self] in
                let timedOutContinuation = self?.state.withLock { state in
                    state.waiters.removeValue(forKey: waiterID)
                }
                timedOutContinuation?.resume(returning: false)
            }
        }
    }
}

final class TabBarAdapterProjectionGate: Sendable {
    private let started = TabBarAdapterTestSignal()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let didRelease = Mutex(false)

    func hold() throws(CancellationError) {
        started.signal()
        guard releaseSemaphore.wait(timeout: .now() + .seconds(5)) == .success else {
            throw CancellationError()
        }
    }

    func waitUntilStarted() async -> Bool {
        await started.wait()
    }

    func release() {
        let shouldRelease = didRelease.withLock { didRelease in
            guard !didRelease else { return false }
            didRelease = true
            return true
        }
        if shouldRelease {
            releaseSemaphore.signal()
        }
    }
}

final class TabBarAdapterProjectionController: Sendable {
    private struct State {
        var projectedGenerations: [UInt64] = []
        var projectedTabIDs: [UUID] = []
        var firstProjectionByTabID: [UUID: TabBarProjection] = [:]
        var activeProjectionCount = 0
        var maximumConcurrentProjectionCount = 0
    }

    private let gatesByGeneration: [UInt64: TabBarAdapterProjectionGate]
    private let returnsFirstProjection: Bool
    private let returnsFirstProjectionForGenerations: Set<UInt64>
    private let state = Mutex(State())

    init(
        gatesByGeneration: [UInt64: TabBarAdapterProjectionGate] = [:],
        returnsFirstProjection: Bool = false,
        returnsFirstProjectionForGenerations: Set<UInt64> = []
    ) {
        self.gatesByGeneration = gatesByGeneration
        self.returnsFirstProjection = returnsFirstProjection
        self.returnsFirstProjectionForGenerations = returnsFirstProjectionForGenerations
    }

    var projectionCount: Int {
        state.withLock { $0.projectedGenerations.count }
    }

    var projectedGenerations: [UInt64] {
        state.withLock { $0.projectedGenerations }
    }

    var projectedTabIDs: [UUID] {
        state.withLock { $0.projectedTabIDs }
    }

    var maximumConcurrentProjectionCount: Int {
        state.withLock { $0.maximumConcurrentProjectionCount }
    }

    func project(
        _ request: TabBarProjectionRequest
    ) throws(CancellationError) -> TabBarProjection {
        let generation = request.generation.value
        state.withLock { state in
            state.projectedGenerations.append(generation)
            state.activeProjectionCount += 1
            state.maximumConcurrentProjectionCount = max(
                state.maximumConcurrentProjectionCount,
                state.activeProjectionCount
            )
        }
        defer {
            state.withLock { state in
                precondition(state.activeProjectionCount > 0)
                state.activeProjectionCount -= 1
            }
        }
        try gatesByGeneration[generation]?.hold()
        let candidate = try TabBarProjector.project(request)
        return state.withLock { state in
            state.projectedTabIDs.append(contentsOf: candidate.items.map(\.id))
            guard let tabID = candidate.items.first?.id else { return candidate }
            if let firstProjection = state.firstProjectionByTabID[tabID],
                returnsFirstProjection || returnsFirstProjectionForGenerations.contains(generation)
            {
                return firstProjection
            }
            state.firstProjectionByTabID[tabID] = candidate
            return candidate
        }
    }
}

final class TabBarAdapterTestCounter: Sendable {
    private let countState = Mutex(0)

    var didIncrement: Bool {
        countState.withLock { $0 > 0 }
    }

    func increment() {
        countState.withLock { $0 += 1 }
    }
}

@MainActor
final class TabBarAdapterProjectionCompletionRecorder {
    private var completions: [TabBarMaterializedProjection.ProjectionCompletion] = []
    private var waiters:
        [(
            completion: TabBarMaterializedProjection.ProjectionCompletion,
            signal: TabBarAdapterTestSignal
        )] = []

    func record(_ completion: TabBarMaterializedProjection.ProjectionCompletion) {
        completions.append(completion)
        for waiter in waiters where waiter.completion == completion {
            waiter.signal.signal()
        }
    }

    func wait(
        for completion: TabBarMaterializedProjection.ProjectionCompletion
    ) async -> Bool {
        if completions.contains(completion) {
            return true
        }
        if let existingWaiter = waiters.first(where: { $0.completion == completion }) {
            return await existingWaiter.signal.wait()
        }
        let signal = TabBarAdapterTestSignal()
        waiters.append((completion: completion, signal: signal))
        return await signal.wait()
    }
}
