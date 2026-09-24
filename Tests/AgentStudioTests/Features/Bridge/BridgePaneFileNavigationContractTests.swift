import Foundation
import Testing

@testable import AgentStudioBridge

struct BridgePaneFileNavigationContractTests {
    // MARK: - Exact File intent

    @Test("exact File intent binds the collection source and document key")
    func exactFileIntentBindsSourceAndTarget() throws {
        // Arrange
        var authority = BridgePaneSurfaceSelectionAuthority()
        let source = BridgeProductNavigationFileSource(sourceId: "collection-source-3", subscriptionGeneration: 3)
        let target = BridgeProductNavigationFileTarget(path: "backend/src/plan.md", version: .current)

        // Act
        let commandId = authority.retainFileTarget(source: source, target: target)
        let request = try #require(
            try authority.rebindRetainedIntent(
                paneSessionId: "pane-session-1",
                workerInstanceId: "worker-instance-1"
            )
        )

        // Assert
        guard
            case .activateFileTarget(let boundCommandId, let revision, let boundSource, let boundTarget) =
                request.navigationCommand
        else {
            Issue.record("Expected an exact File navigation command")
            return
        }
        #expect(boundCommandId == commandId)
        #expect(revision == 1)
        #expect(boundSource == source)
        #expect(boundTarget == target)
        #expect(authority.diagnosticSnapshot.desiredSurface == .file)
    }

    @Test("a failed exact File intent is dropped rather than replayed")
    func failedExactFileIntentIsDropped() {
        // Arrange
        var authority = BridgePaneSurfaceSelectionAuthority()
        let commandId = authority.retainFileTarget(
            source: BridgeProductNavigationFileSource(sourceId: "collection-source-1", subscriptionGeneration: 1),
            target: BridgeProductNavigationFileTarget(path: "Open Files/plan.md", version: .current)
        )

        // Act
        authority.invalidateFailedExactIntent(commandId: commandId)

        // Assert
        #expect(authority.diagnosticSnapshot.retainedCommandId == nil)
        #expect(authority.diagnosticSnapshot.needsDelivery == false)
    }

    // MARK: - Displayed-selection receipt

    @Test("a displayed-selection receipt decodes with its native command and source generation")
    func displayedSelectionReceiptDecodes() throws {
        // Arrange
        let object = productCall(request: receiptObject())

        // Act
        let decoded = try decode(object)

        // Assert
        guard case .productCall(let call) = decoded, case .fileSelectionReceipt(let receipt) = call.call else {
            Issue.record("Expected a File selection receipt call")
            return
        }
        #expect(receipt.displayPath == "backend/src/plan.md")
        #expect(receipt.nativeNavigationCommandId == "native-file-activation-1")
        #expect(receipt.outcome == .displayed)
        #expect(
            receipt.source
                == BridgeProductFileSelectionReceiptSource(
                    sourceId: "collection-source-3",
                    subscriptionGeneration: 3
                ))
        #expect(call.call.surface == .file)
    }

    @Test("a receipt must state its native command, even when there is none")
    func receiptRequiresExplicitNativeCommand() throws {
        // Arrange
        var humanReceipt = receiptObject()
        humanReceipt["nativeNavigationCommandId"] = NSNull()
        var missingCommand = receiptObject()
        missingCommand.removeValue(forKey: "nativeNavigationCommandId")

        // Act / Assert
        guard
            case .productCall(let call) = try decode(productCall(request: humanReceipt)),
            case .fileSelectionReceipt(let receipt) = call.call
        else {
            Issue.record("Expected a human selection receipt")
            return
        }
        #expect(receipt.nativeNavigationCommandId == nil)
        #expect(throws: (any Error).self) { try decode(productCall(request: missingCommand)) }
    }

    @Test("receipts with unknown outcomes, keys, empty display paths or negative generations are rejected")
    func malformedReceiptsAreRejected() {
        var unknownOutcome = receiptObject()
        unknownOutcome["outcome"] = "highlighted"
        var extraKey = receiptObject()
        extraKey["selectedItemId"] = "file-1"
        var emptyPath = receiptObject()
        emptyPath["displayPath"] = ""
        var negativeGeneration = receiptObject()
        negativeGeneration["source"] = ["sourceId": "collection-source-3", "subscriptionGeneration": -1]

        for invalid in [unknownOutcome, extraKey, emptyPath, negativeGeneration] {
            #expect(throws: (any Error).self) { try decode(productCall(request: invalid)) }
        }
    }

    @Test("a receipt result is a literal null bound to the File method")
    func receiptResultIsLiteralNull() throws {
        // Arrange
        let encoded = try JSONEncoder().encode(BridgeProductCallResult.fileSelectionReceipt)

        // Act
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(BridgeProductCallResult.self, from: encoded)

        // Assert
        #expect(object["method"] as? String == "file.selection.receipt")
        #expect(object["result"] is NSNull)
        #expect(decoded == .fileSelectionReceipt)
    }

    // MARK: - Helpers

    private func receiptObject() -> [String: Any] {
        [
            "displayPath": "backend/src/plan.md",
            "nativeNavigationCommandId": "native-file-activation-1",
            "outcome": "displayed",
            "source": ["sourceId": "collection-source-3", "subscriptionGeneration": 3],
        ]
    }

    private func productCall(request: [String: Any]) -> [String: Any] {
        [
            "call": ["method": "file.selection.receipt", "request": request],
            "kind": "product.call",
            "paneSessionId": "pane-session-1",
            "requestId": "file-selection-receipt-call-1",
            "requestSequence": 2,
            "wireVersion": 2,
            "workerDerivationEpoch": 4,
            "workerInstanceId": "worker-instance-1",
        ]
    }

    private func decode(_ object: [String: Any]) throws -> BridgeProductControlRequest {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try BridgeProductStrictJSON.decode(BridgeProductControlRequest.self, from: data)
    }
}
