import Dispatch
import Foundation
import Testing

@testable import AgentStudio

@Suite("FSEvent registration control block")
struct FSEventRegistrationControlBlockTests {
    @Test("closing rejects new callbacks while an old-generation lease remains valid")
    func closingRejectsNewCallbacksWithoutRelabelingLease() throws {
        let token = makeToken(registrationGeneration: 9)
        let controlBlock = try makeControlBlock(token: token)
        let lease: FSEventCallbackLease
        switch controlBlock.acquireCallbackLease(for: token) {
        case .acquired(let acquiredLease):
            lease = acquiredLease
        case .staleRegistration, .leaseIdentityExhausted, .closing, .closed:
            Issue.record("open registration must acquire a callback lease")
            return
        }

        #expect(controlBlock.beginClosing() == .applied)
        #expect(controlBlock.acquireCallbackLease(for: token) == .closing)
        #expect(lease.registration == token)
        #expect(lease.release() == .released)
        #expect(lease.release() == .alreadyReleased)
    }

    @Test("lease drain advances only after callback queue barrier")
    func leaseDrainRequiresQueueBarrier() async throws {
        let token = makeToken(registrationGeneration: 12)
        let controlBlock = try makeControlBlock(token: token)
        let lease: FSEventCallbackLease
        switch controlBlock.acquireCallbackLease(for: token) {
        case .acquired(let acquiredLease): lease = acquiredLease
        case .staleRegistration, .leaseIdentityExhausted, .closing, .closed:
            Issue.record("open registration must acquire a callback lease")
            return
        }

        #expect(controlBlock.beginClosing() == .applied)
        #expect(controlBlock.markStreamInvalidated() == .applied)
        #expect(controlBlock.markCallbackQueueDrained() == .waitingForLeases(activeLeaseCount: 1))

        async let drained: Void = controlBlock.waitUntilLeasesDrained()
        #expect(lease.release() == .released)
        await drained
        #expect(controlBlock.lifecycleSnapshot == .closing(.leasesDrained, activeLeaseCount: 0))
    }

    @Test("wrong generation and completed lifecycle are explicit states")
    func staleAndClosedLeaseAdmissionsAreExplicit() throws {
        let token = makeToken(registrationGeneration: 20)
        let controlBlock = try makeControlBlock(token: token)

        #expect(controlBlock.acquireCallbackLease(for: makeToken(registrationGeneration: 21)) == .staleRegistration)
        #expect(controlBlock.beginClosing() == .applied)
        #expect(controlBlock.markStreamInvalidated() == .applied)
        #expect(controlBlock.markCallbackQueueDrained() == .leasesDrained)
        #expect(controlBlock.markRecoveryTransferred() == .applied)
        #expect(controlBlock.markMailboxGenerationInvalidated() == .applied)
        #expect(controlBlock.finishClosing() == .applied)
        #expect(controlBlock.lifecycleSnapshot == .closed)
        #expect(controlBlock.acquireCallbackLease(for: token) == .closed)
    }

    @Test("out-of-order close phases preserve the current lifecycle")
    func outOfOrderClosePhasesAreRejected() throws {
        let controlBlock = try makeControlBlock(token: makeToken(registrationGeneration: 30))

        #expect(
            controlBlock.markStreamInvalidated()
                == .invalidTransition(.open(activeLeaseCount: 0))
        )
        #expect(controlBlock.beginClosing() == .applied)
        #expect(
            controlBlock.markCallbackQueueDrained()
                == .invalidTransition(.closing(.admissionClosed, activeLeaseCount: 0))
        )
        #expect(controlBlock.lifecycleSnapshot == .closing(.admissionClosed, activeLeaseCount: 0))
    }

    @Test("last of multiple leases completes the drain")
    func lastLeaseCompletesDrain() async throws {
        let token = makeToken(registrationGeneration: 31)
        let controlBlock = try makeControlBlock(token: token)
        let firstLease = try #require(acquiredLease(from: controlBlock, token: token))
        let secondLease = try #require(acquiredLease(from: controlBlock, token: token))

        #expect(controlBlock.beginClosing() == .applied)
        #expect(controlBlock.markStreamInvalidated() == .applied)
        #expect(controlBlock.markCallbackQueueDrained() == .waitingForLeases(activeLeaseCount: 2))
        #expect(firstLease.release() == .released)
        #expect(controlBlock.lifecycleSnapshot == .closing(.callbackQueueDrained, activeLeaseCount: 1))
        #expect(secondLease.release() == .released)
        await controlBlock.waitUntilLeasesDrained()
        #expect(controlBlock.lifecycleSnapshot == .closing(.leasesDrained, activeLeaseCount: 0))
    }

    @Test("control block rejects a watch root owned by another source")
    func watchRootSourceMustMatchRegistration() throws {
        let token = makeToken(registrationGeneration: 32)
        let otherSource = FilesystemSourceID(kind: .registeredWorktreeContent, rootID: UUID())

        #expect(throws: FSEventRegistrationControlBlockError.watchRootSourceMismatch) {
            try FSEventRegistrationControlBlock(
                registration: token,
                watchRoot: WatchRoot(
                    sourceID: otherSource,
                    declaredPath: "/workspace/repo",
                    resolvedPath: "/private/workspace/repo"
                ),
                captureLimits: try makeCaptureLimits(),
                callbackQueue: DispatchQueue(label: "test.fsevent.mismatched")
            )
        }
    }

    private func makeControlBlock(token: FSEventRegistrationToken) throws
        -> FSEventRegistrationControlBlock
    {
        let callbackQueue = DispatchQueue(label: "test.fsevent.\(token.registrationGeneration)")
        let controlBlock = try FSEventRegistrationControlBlock(
            registration: token,
            watchRoot: WatchRoot(
                sourceID: token.sourceID,
                declaredPath: "/workspace/repo",
                resolvedPath: "/private/workspace/repo"
            ),
            captureLimits: makeCaptureLimits(),
            callbackQueue: callbackQueue
        )
        #expect(controlBlock.callbackQueue === callbackQueue)
        return controlBlock
    }

    private func makeCaptureLimits() throws -> FSEventCaptureLimits {
        try FSEventCaptureLimits(
            maximumInspectedNativeRecords: 32,
            maximumCopiedRecords: 16,
            maximumCopiedUTF8Bytes: 4096,
            maximumSinglePathUTF8Bytes: 1024
        )
    }

    private func acquiredLease(
        from controlBlock: FSEventRegistrationControlBlock,
        token: FSEventRegistrationToken
    ) -> FSEventCallbackLease? {
        switch controlBlock.acquireCallbackLease(for: token) {
        case .acquired(let lease): lease
        case .staleRegistration, .leaseIdentityExhausted, .closing, .closed: nil
        }
    }

    private func makeToken(registrationGeneration: UInt64) -> FSEventRegistrationToken {
        FSEventRegistrationToken(
            sourceID: FilesystemSourceID(
                kind: .registeredWorktreeContent,
                rootID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ),
            registrationGeneration: registrationGeneration,
            rootGeneration: 4
        )
    }
}
