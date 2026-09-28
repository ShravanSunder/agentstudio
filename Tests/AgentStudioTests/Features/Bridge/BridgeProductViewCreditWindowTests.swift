import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Bridge product view receipt credits")
struct BridgeProductViewCreditWindowTests {
    @Test("receipt credits let a batch exceed its in-flight window")
    func batchLargerThanWindowProgresses() {
        var credits = BridgeProductViewCreditWindow(maximumParts: 2, maximumBytes: 8)
        let viewDomain = BridgeProductViewDomainKey(viewId: "file-view", domain: .singleDomain, incarnation: "first")
        credits.open(viewDomain, handle: "first-handle")

        let firstAdmitted = credits.admitPart(for: viewDomain, handle: "first-handle", sequence: 1, byteCount: 4)
        let secondAdmitted = credits.admitPart(for: viewDomain, handle: "first-handle", sequence: 2, byteCount: 4)
        let thirdBeforeReceipt = credits.admitPart(for: viewDomain, handle: "first-handle", sequence: 3, byteCount: 4)
        #expect(firstAdmitted && secondAdmitted && !thirdBeforeReceipt)

        let firstReceived = credits.acknowledge(for: viewDomain, handle: "first-handle", through: 1)
        let thirdAfterReceipt = credits.admitPart(for: viewDomain, handle: "first-handle", sequence: 3, byteCount: 4)
        #expect(firstReceived && thirdAfterReceipt)
        #expect(credits.outstandingPartCount(for: viewDomain) == 2)
        let remainderReceived = credits.acknowledge(for: viewDomain, handle: "first-handle", through: 3)
        #expect(remainderReceived)
        #expect(credits.outstandingPartCount(for: viewDomain) == 0)
    }

    @Test("stale handles and acknowledgements cannot return credits")
    func staleAcknowledgementsDoNotReturnCredits() {
        var credits = BridgeProductViewCreditWindow(maximumParts: 1, maximumBytes: 8)
        let viewDomain = BridgeProductViewDomainKey(viewId: "review-view", domain: .singleDomain, incarnation: "first")
        credits.open(viewDomain, handle: "first-handle")
        let firstAdmitted = credits.admitPart(for: viewDomain, handle: "first-handle", sequence: 1, byteCount: 8)
        #expect(firstAdmitted)
        credits.open(viewDomain, handle: "second-handle")
        let replacementAdmitted = credits.admitPart(for: viewDomain, handle: "second-handle", sequence: 1, byteCount: 8)
        #expect(replacementAdmitted)

        let staleReceipt = credits.acknowledge(for: viewDomain, handle: "first-handle", through: 1)
        let speculativeReceipt = credits.acknowledge(for: viewDomain, handle: "second-handle", through: 2)
        let partBeforeReceipt = credits.admitPart(for: viewDomain, handle: "second-handle", sequence: 2, byteCount: 1)
        let validReceipt = credits.acknowledge(for: viewDomain, handle: "second-handle", through: 1)
        let duplicateReceipt = credits.acknowledge(for: viewDomain, handle: "second-handle", through: 1)
        let partAfterReceipt = credits.admitPart(for: viewDomain, handle: "second-handle", sequence: 2, byteCount: 1)
        #expect(!staleReceipt && !speculativeReceipt && !partBeforeReceipt)
        #expect(validReceipt && !duplicateReceipt && partAfterReceipt)
    }

    @Test("domains share transport credits and old receipts cannot release successor capacity")
    func domainsShareCreditsWithSeparateReceiptAttribution() {
        var credits = BridgeProductViewCreditWindow(maximumParts: 1, maximumBytes: 4)
        let retired = BridgeProductViewDomainKey(viewId: "file-view", domain: .singleDomain, incarnation: "first")
        let successor = BridgeProductViewDomainKey(viewId: "file-view", domain: .singleDomain, incarnation: "second")
        credits.open(retired, handle: "shared-handle")
        credits.open(successor, handle: "shared-handle")
        let oldAdmitted = credits.admitPart(for: retired, handle: "shared-handle", sequence: 1, byteCount: 4)
        let newBeforeRelease = credits.admitPart(for: successor, handle: "shared-handle", sequence: 1, byteCount: 4)
        credits.close(retired)
        let newAfterRelease = credits.admitPart(for: successor, handle: "shared-handle", sequence: 1, byteCount: 4)
        let staleReceipt = credits.acknowledge(for: retired, handle: "shared-handle", through: 1)

        #expect(oldAdmitted && !newBeforeRelease && newAfterRelease && !staleReceipt)
        #expect(credits.outstandingPartCount(for: retired) == 0)
        #expect(credits.outstandingPartCount(for: successor) == 1)
    }

    @Test("late acknowledgement after resnapshot is satisfied without returning successor credit")
    func abandonedReceiptIsSatisfiedWithoutDoubleCredit() {
        var credits = BridgeProductViewCreditWindow(maximumParts: 1, maximumBytes: 8)
        let view = BridgeProductViewDomainKey(viewId: "file-view", domain: .singleDomain, incarnation: "first")
        credits.open(view, handle: "handle-1")
        let firstAdmitted = credits.admitPart(for: view, handle: "handle-1", sequence: 1, byteCount: 8)
        #expect(firstAdmitted)
        credits.abandonOutstanding(for: view)
        #expect(credits.outstandingPartCount(for: view) == 0)

        let abandonedReceiptReturnedCredit = credits.acknowledge(for: view, handle: "handle-1", through: 1)
        #expect(!abandonedReceiptReturnedCredit)
        #expect(credits.wasAlreadySatisfied(for: view, handle: "handle-1", through: 1))
        #expect(!credits.wasAlreadySatisfied(for: view, handle: "wrong-handle", through: 1))
        #expect(!credits.wasAlreadySatisfied(for: view, handle: "handle-1", through: 2))
        let successorPartAdmitted = credits.admitPart(for: view, handle: "handle-1", sequence: 2, byteCount: 8)
        #expect(successorPartAdmitted)
        #expect(credits.wasAlreadySatisfied(for: view, handle: "handle-1", through: 1))
        #expect(credits.outstandingPartCount(for: view) == 1)
    }

    @Test("reserved but unissued parts advance the credit floor without crediting late receipts")
    func reservedUnissuedSequencesDoNotBlockReplacement() {
        var credits = BridgeProductViewCreditWindow(maximumParts: 1, maximumBytes: 8)
        let view = BridgeProductViewDomainKey(viewId: "file-view", domain: .singleDomain, incarnation: "first")
        credits.open(view, handle: "handle-1")
        credits.abandonOutstanding(for: view, throughReservedSequence: 3)

        #expect(credits.wasAlreadySatisfied(for: view, handle: "handle-1", through: 3))
        let replacementAdmitted = credits.admitPart(for: view, handle: "handle-1", sequence: 4, byteCount: 8)
        let lateReceiptReturnedCredit = credits.acknowledge(for: view, handle: "handle-1", through: 3)
        #expect(replacementAdmitted)
        #expect(!lateReceiptReturnedCredit)
        #expect(credits.outstandingPartCount(for: view) == 1)
        let replacementReceiptReturnedCredit = credits.acknowledge(for: view, handle: "handle-1", through: 4)
        #expect(replacementReceiptReturnedCredit)
        #expect(credits.outstandingPartCount(for: view) == 0)
    }
}
