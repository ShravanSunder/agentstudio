@testable import AgentStudioBridge

func coordinatorFileUpdateRequest(
    emptyInterestSha256: String,
    targetInterestSha256: String,
    updateId: String
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest(
        [
            "baseInterestRevision": 0,
            "baseInterestSha256": emptyInterestSha256,
            "batchCount": 1,
            "batchIndex": 0,
            "delta": [
                "add": [["lane": "foreground", "path": "Sources/App.swift"]],
                "addPathScope": [],
                "removePathScope": [],
                "removePaths": [],
                "subscriptionKind": "file.metadata",
            ],
            "kind": "subscription.updateBatch",
            "paneSessionId": "pane-session-1",
            "requestId": "request-file-update-3",
            "requestSequence": 3,
            "subscriptionId": "file-subscription-1",
            "subscriptionKind": "file.metadata",
            "targetInterestRevision": 1,
            "targetInterestSha256": targetInterestSha256,
            "totalDeltaItemCount": 1,
            "updateId": updateId,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ]
    )
}

func coordinatorReviewUpdateRequest(
    emptyInterestSha256: String,
    updateId: String
) throws -> BridgeProductControlRequest {
    try bridgeProductLifecycleControlRequest(
        [
            "baseInterestRevision": 0,
            "baseInterestSha256": emptyInterestSha256,
            "batchCount": 1,
            "batchIndex": 0,
            "delta": [
                "add": [
                    ["itemId": "review-item-1", "lane": "foreground"],
                    ["itemId": "review-item-2", "lane": "visible"],
                ],
                "removeItemIds": [],
                "subscriptionKind": "review.metadata",
            ],
            "kind": "subscription.updateBatch",
            "paneSessionId": "pane-session-1",
            "requestId": "request-review-update-3",
            "requestSequence": 3,
            "subscriptionId": "review-subscription-1",
            "subscriptionKind": "review.metadata",
            "targetInterestRevision": 1,
            "targetInterestSha256":
                "2535176c2a822c1f5007dd72a7987b7c0a1b6e9af1bc28324ec4618b43f71ebd",
            "totalDeltaItemCount": 2,
            "updateId": updateId,
            "wireVersion": BridgeProductWireContract.version,
            "workerDerivationEpoch": 1,
            "workerInstanceId": "worker-instance-1",
        ]
    )
}
