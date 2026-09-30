import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioTestSupport

@MainActor
extension WebKitSerializedTests.BridgeProductRealGitFileAndReviewWebKitTests {
    /// Link 1: the page reader's finite-progress deadline aborts its fetch signal
    /// (bridge-product-transport-content-progress.unit.test.ts). Link 2: this
    /// packaged WebKit fetch uses that signal path and proves an ACK0-parked
    /// native content producer retires when the fetch is aborted.
    @Test("aborted packaged content fetch retires its ACK0-parked native producer")
    func abortedContentFetchRetiresACK0ParkedProducer() async throws {
        let repoURL = try await FilesystemTestGitRepo.create(named: "bridge-product-content-abort-webkit")
        defer { FilesystemTestGitRepo.destroy(repoURL) }
        try "tracked\n".write(
            to: repoURL.appending(path: "tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try await FilesystemTestGitRepo.runGit(at: repoURL, args: ["add", "tracked.txt"])
        try await FilesystemTestGitRepo.runGit(at: repoURL, args: ["commit", "-m", "Initial commit"])
        let controller = makeController(
            repoURL: repoURL,
            traceRecorder: BridgeProductWebKitCarrierTraceRecorder()
        )

        let run = try await BridgeProductWebKitCarrierTestSupport.withHostedController(
            controller
        ) { hostedController in
            hostedController.loadApp()
            await WebPageEventWaits.waitForNavigationToFinish(hostedController.page)
            try await WebPageEventWaits.waitForDocumentSelector(
                hostedController.page,
                "[data-testid=\"bridge-app-root\"]"
            )
            let installation = try #require(
                await hostedController.productSessionOwner.activeInstallation
            )
            #expect(await installation.session.waitUntilActive())
            let baseline = await hostedController.productSessionOwner.snapshot()
            let request = try await makeContentAbortRequest(installation: installation)
            return try await observePackagedContentAbort(
                controller: hostedController,
                baseline: baseline,
                capability: request.capability,
                requestBody: request.requestBody,
                acknowledgementBody: request.acknowledgementBody
            )
        }

        #expect(run.value.2 == "404:unknownRead")
        #expect(run.value.1.activeSchemeTaskCount == run.value.0.activeSchemeTaskCount)
        #expect(run.value.1.activeTransportLeaseCount == run.value.0.activeTransportLeaseCount)
        #expect(run.value.1.activeProducerCount == run.value.0.activeProducerCount)
        #expect(run.value.1.activeProducerTaskCount == run.value.0.activeProducerTaskCount)
        #expect(run.value.1.activeContentLeaseCount == run.value.0.activeContentLeaseCount)
        #expect(run.value.1.queuedFrameCount == run.value.0.queuedFrameCount)
        #expect(run.value.1.inFlightFrameReceiptCount == run.value.0.inFlightFrameReceiptCount)
        #expect(run.teardownSnapshot.hasZeroResidue)
    }
    private func makeContentAbortRequest(
        installation: BridgeProductSessionInstallation
    ) async throws -> (capability: String, requestBody: String, acknowledgementBody: String) {
        let fileEpoch = await installation.session.snapshot.workerDerivationEpochBySurface[.file] ?? 0
        let capability = try BridgeProductCapabilityHeaderEncoding.encode(
            installation.capabilityBytes
        )
        let contentRequestID = "webKit-ack0-abort-content"
        let leaseID = "webKit-ack0-abort-lease"
        let requestBody = try JSONSerialization.data(
            withJSONObject: [
                "kind": "content.open",
                "contentKind": "file.content",
                "contentRequestId": contentRequestID,
                "leaseId": leaseID,
                "operationCorrelationId": NSNull(),
                "paneSessionId": installation.bootstrap.paneSessionId,
                "wireVersion": BridgeProductWireContract.version,
                "workerDerivationEpoch": fileEpoch,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
                "descriptor": [
                    "contentKind": "file.content",
                    "declaredByteLength": 3,
                    "descriptorId": "webKit-ack0-abort-descriptor",
                    "encoding": "utf-8",
                    "expectedSha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                    "fileId": "webKit-ack0-abort-file",
                    "maximumBytes": 3,
                    "source": [
                        "repoId": "00000000-0000-4000-8000-000000000001",
                        "rootRevisionToken": NSNull(),
                        "sourceCursor": "webKit-ack0-abort-cursor",
                        "sourceId": "webKit-ack0-abort-source",
                        "subscriptionGeneration": 1,
                        "worktreeId": "00000000-0000-4000-8000-000000000002",
                    ] as [String: Any],
                    "window": [
                        "kind": "prefix",
                        "maximumBytes": 3,
                        "maximumLines": 10_000,
                        "startByte": 0,
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
            options: [.sortedKeys]
        )
        let requestText = try #require(String(data: requestBody, encoding: .utf8))
        let acknowledgementBody = try JSONSerialization.data(
            withJSONObject: [
                "kind": "content.acknowledge",
                "contentRequestId": contentRequestID,
                "leaseId": leaseID,
                "paneSessionId": installation.bootstrap.paneSessionId,
                "wireVersion": BridgeProductWireContract.version,
                "workerInstanceId": installation.bootstrap.workerInstanceId,
                "receivedThroughContentSequence": 0,
            ],
            options: [.sortedKeys]
        )
        let acknowledgementText = try #require(
            String(data: acknowledgementBody, encoding: .utf8)
        )
        return (capability, requestText, acknowledgementText)
    }

    private func observePackagedContentAbort(
        controller hostedController: BridgePaneController,
        baseline: BridgePaneProductSessionOwnerSnapshot,
        capability: String,
        requestBody requestText: String,
        acknowledgementBody acknowledgementText: String
    ) async throws -> (
        BridgePaneProductSessionOwnerSnapshot,
        BridgePaneProductSessionOwnerSnapshot,
        String?
    ) {
        let contentFetch = Task { @MainActor in
            try await hostedController.page.callJavaScript(
                """
                const controller = new AbortController();
                const response = await fetch(contentURL, {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'X-AgentStudio-Bridge-Product-Capability': capability
                  },
                  body: requestBody,
                  signal: controller.signal
                });
                if (!response.ok || response.body === null) return 'opening-failed:' + response.status;
                const reader = response.body.getReader();
                const opening = await reader.read();
                if (opening.done || !opening.value?.length) return 'opening-missing';
                const abortRequested = new Promise(resolve => {
                  window.addEventListener('bridge-test-abort-content', resolve, { once: true });
                });
                document.documentElement.setAttribute('data-bridge-test-ack0-opening', 'received');
                await abortRequested;
                controller.abort();
                await reader.cancel().catch(() => {});
                const lateAck = await fetch(commandURL, {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'X-AgentStudio-Bridge-Product-Capability': capability
                  },
                  body: acknowledgementBody
                });
                const refusal = await lateAck.json();
                return `${lateAck.status}:${refusal.reason}`;
                """,
                arguments: [
                    "contentURL": BridgeProductWireContract.contentRoute,
                    "commandURL": BridgeProductWireContract.commandRoute,
                    "capability": capability,
                    "requestBody": requestText,
                    "acknowledgementBody": acknowledgementText,
                ]
            ) as? String
        }
        try await WebPageEventWaits.waitForDocumentSelector(
            hostedController.page,
            "html[data-bridge-test-ack0-opening=\"received\"]"
        )
        let parked = await hostedController.productSessionOwner.snapshot()
        #expect(parked.activeProducerCount == baseline.activeProducerCount + 1)
        #expect(parked.activeProducerTaskCount == baseline.activeProducerTaskCount + 1)
        #expect(parked.activeContentLeaseCount == baseline.activeContentLeaseCount + 1)
        _ = try await hostedController.page.callJavaScript(
            "window.dispatchEvent(new Event('bridge-test-abort-content'));"
        )
        let lateAcknowledgement = try await contentFetch.value
        let settled = await hostedController.productSessionOwner.snapshot()
        return (baseline, settled, lateAcknowledgement)
    }

}
