import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite("FilesystemGitPipeline repository fact update")
struct FilesystemGitPipelineRepositoryFactUpdateTests {
    @Test("repository refresh admits remote fetch only")
    func repositoryRefreshAdmitsRemoteFetchOnly() throws {
        let source = try String(
            contentsOfFile: "Sources/AgentStudio/App/Coordination/FilesystemGitPipeline.swift",
            encoding: .utf8
        )
        let functionStart = try #require(
            source.range(of: "func startRepositoryFactUpdate(")
        )
        let nextFunction = try #require(
            source.range(
                of: "static func admitRepositoryFactUpdateSources(",
                range: functionStart.upperBound..<source.endIndex
            )
        )
        let functionSource = source[functionStart.lowerBound..<nextFunction.lowerBound]

        #expect(functionSource.contains("source: .remoteReferences"))
        #expect(!functionSource.contains("source: .localGit"))
        #expect(!functionSource.contains("source: .forge"))
    }

    @Test("all source owners receive admission concurrently before settlement")
    func allSourcesAdmitConcurrentlyBeforeSettlement() async throws {
        let admissionGate = RepositoryFactUpdateTestGate(requiredArrivalCount: 3)
        let settlementGate = RepositoryFactUpdateTestGate(requiredArrivalCount: 3)
        let attemptID = UUIDv7.generate()
        let handlers = RepositoryFactSource.allCases.map { source in
            RepositoryFactUpdateSourceAdmissionHandler(source: source) { _, receivedAttemptID in
                #expect(receivedAttemptID == attemptID)
                await admissionGate.arriveAndWait()
                return .accepted(
                    RepositoryFactSourceUpdateLease(
                        source: source,
                        attemptId: receivedAttemptID,
                        settlementTask: Task {
                            await settlementGate.arriveAndWait()
                            return source == .localGit ? .completed : .failed
                        }
                    )
                )
            }
        }
        let admissionTask = Task {
            await FilesystemGitPipeline.admitRepositoryFactUpdateSources(
                repoId: UUIDv7.generate(),
                attemptId: attemptID,
                handlers: handlers
            )
        }

        await admissionGate.waitForAllArrivals()
        await admissionGate.release()
        let admission = await admissionTask.value

        #expect(admission.acceptedSources == Set(RepositoryFactSource.allCases))
        #expect(admission.terminalResultsBySource.isEmpty)
        await settlementGate.waitForAllArrivals()
        await settlementGate.release()
        let results = await admission.settlement()
        #expect(results[.localGit] == .completed)
        #expect(results[.remoteReferences] == .failed)
        #expect(results[.forge] == .failed)
    }

    @Test("all terminal admissions settle without a false accepted source")
    func allTerminalAdmissionsSettleWithoutAcceptedSource() async {
        let handlers = RepositoryFactSource.allCases.map { source in
            RepositoryFactUpdateSourceAdmissionHandler(source: source) { _, _ in
                source == .forge ? .obsolete : .notApplicable
            }
        }

        let admission = await FilesystemGitPipeline.admitRepositoryFactUpdateSources(
            repoId: UUIDv7.generate(),
            attemptId: UUIDv7.generate(),
            handlers: handlers
        )

        #expect(admission.acceptedSources.isEmpty)
        #expect(admission.terminalResultsBySource[.localGit] == .notApplicable)
        #expect(admission.terminalResultsBySource[.remoteReferences] == .notApplicable)
        #expect(admission.terminalResultsBySource[.forge] == .obsolete)
        #expect(await admission.settlement().isEmpty)
    }
}

private actor RepositoryFactUpdateTestGate {
    private let requiredArrivalCount: Int
    private var arrivalCount = 0
    private var isReleased = false
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(requiredArrivalCount: Int) {
        self.requiredArrivalCount = requiredArrivalCount
    }

    func arriveAndWait() async {
        arrivalCount += 1
        if arrivalCount >= requiredArrivalCount {
            let waiters = arrivalWaiters
            arrivalWaiters.removeAll(keepingCapacity: false)
            for waiter in waiters { waiter.resume() }
        }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitForAllArrivals() async {
        guard arrivalCount < requiredArrivalCount else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }
}
