import Foundation

extension IPCBridgeDOMRect: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "x", description: "Horizontal viewport coordinate in CSS pixels", schema: .number()),
            .init(name: "y", description: "Vertical viewport coordinate in CSS pixels", schema: .number()),
            .init(name: "width", description: "Rectangle width in CSS pixels", schema: .number(minimum: 0)),
            .init(name: "height", description: "Rectangle height in CSS pixels", schema: .number(minimum: 0)),
        ])
    }
}

extension IPCBridgeVisibleHydrationStateProbe: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgeOptionalCount("reportedVisibleItemCount", "Items reported visible by the page"),
            bridgeOptionalCount("trackedVisibleItemCount", "Visible items tracked by hydration"),
            bridgeOptionalCount("truncatedVisibleItemCount", "Visible items omitted by the probe limit"),
            bridgeOptionalCount("untrackedItemCount", "Visible items without hydration state"),
            bridgeOptionalCount("loadingItemCount", "Visible items currently loading"),
            bridgeOptionalCount("readyItemCount", "Visible items ready to render"),
            bridgeOptionalCount("failedItemCount", "Visible items whose hydration failed"),
            bridgeOptionalCount("deferredItemCount", "Visible items with deferred hydration"),
            bridgeOptionalCount("abortedItemCount", "Visible items whose hydration was aborted"),
            .optional("pausedNow", description: "Whether visible hydration is paused", schema: .boolean),
        ])
    }
}

extension IPCBridgeVisibleHydrationDiscardRecord: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .optional(
                "hadState", description: "Whether the discarded item had tracked hydration state", schema: .boolean),
            .optional("pausedNow", description: "Whether hydration was paused at discard time", schema: .boolean),
        ])
    }
}

extension IPCBridgeVisibleHydrationDiscardProbe: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgeOptionalCount("readyResultDiscardCount", "Ready hydration results discarded as stale"),
            .init(
                name: "records", description: "Bounded discard observations",
                schema: .array(items: try IPCBridgeVisibleHydrationDiscardRecord.ipcSchema())),
        ])
    }
}

extension IPCBridgeFrameJankLongTaskSummary: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgeOptionalCount("count", "Observed browser long tasks"),
            .optional("totalMs", description: "Total long-task duration in milliseconds", schema: .number(minimum: 0)),
            .optional("maxMs", description: "Longest task duration in milliseconds", schema: .number(minimum: 0)),
        ])
    }
}

extension IPCBridgeFrameJankDroppedFrameSummary: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgeOptionalCount("count", "Observed dropped frames"),
            .optional("worstGapMs", description: "Largest frame gap in milliseconds", schema: .number(minimum: 0)),
        ])
    }
}

extension IPCBridgeFrameJankProbe: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(
                name: "longTask", description: "Long-task measurements",
                schema: try IPCBridgeFrameJankLongTaskSummary.ipcSchema()),
            .init(
                name: "droppedFrame", description: "Dropped-frame measurements",
                schema: try IPCBridgeFrameJankDroppedFrameSummary.ipcSchema()),
            .optional(
                "lastLongTaskAtMs", description: "Page performance timestamp of the last long task in milliseconds",
                schema: .number(minimum: 0)),
        ])
    }
}

extension IPCBridgeProductSessionDiagnostic: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            bridgeCount("activeProducerCount", "Active content producers"),
            bridgeCount("activeProducerTaskCount", "Running producer tasks"),
            bridgeCount("activeContentLeaseCount", "Active content leases"),
            bridgeCount("queuedFrameCount", "Queued product frames"),
            bridgeCount("queuedByteCount", "Bytes held by queued product frames"),
            bridgeCount("pendingFrameWaiterCount", "Consumers waiting for frames"),
            bridgeCount("inFlightFrameReceiptCount", "Frame receipts awaiting settlement"),
            bridgeCount("pendingLifecycleAcknowledgementCount", "Lifecycle acknowledgements awaiting settlement"),
            .init(
                name: "nextMetadataStreamSequence", description: "Next product metadata stream sequence",
                schema: .integer(minimum: 0)),
        ])
    }
}

extension IPCBridgeProductMetadataStreamDiagnostic.Kind: IPCSchemaProviding {}

extension IPCBridgeProductMetadataStreamDiagnostic.SubscriptionTermination: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .optional("subscriptionId", description: "Terminated subscription identifier", schema: .string()),
            .optional("outcome", description: "Subscription termination outcome", schema: .string()),
            .optional("reason", description: "Subscription termination reason", schema: .string()),
        ])
    }
}

extension IPCBridgeProductMetadataStreamDiagnostic: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "kind", description: "Product diagnostic kind", schema: try Kind.ipcSchema()),
            .optional(
                "lastSubscriptionTermination", description: "Most recent subscription termination",
                schema: try SubscriptionTermination.ipcSchema()),
            bridgeOptionalString("routeFailureSubscriptionId", "Subscription whose frame route failed"),
            bridgeOptionalCount("acknowledgedFrameCount", "Frames acknowledged by the consumer"),
            bridgeOptionalCount("activeSubscriptionCount", "Active metadata stream subscriptions"),
            bridgeOptionalCount("committedFrameCount", "Frames committed by the consumer"),
            bridgeOptionalString("decoderState", "Current metadata stream decoder state"),
            bridgeOptionalCount("expectedNextStreamSequence", "Next stream sequence expected by the decoder"),
            bridgeOptionalString("failureCode", "Current stream failure code"),
            bridgeOptionalString("failureStage", "Current stream failure stage"),
            bridgeOptionalString("identityMismatchField", "Identity field that failed validation"),
            bridgeOptionalCount("lastChunkByteCount", "Bytes in the most recent stream chunk"),
            bridgeOptionalCount("lastAcknowledgedStreamSequence", "Most recent acknowledged stream sequence"),
            bridgeOptionalString("lastCommittedFrameKind", "Kind of the most recently committed frame"),
            bridgeOptionalString("lastRoutedFrameKind", "Kind of the most recently routed frame"),
            bridgeOptionalString("lifecycleState", "Metadata stream lifecycle state"),
            bridgeOptionalCount("peakRetainedByteCount", "Peak retained stream bytes"),
            bridgeOptionalCount("pushCount", "Stream push operations"),
            bridgeOptionalCount("readFulfilledCount", "Read requests fulfilled"),
            .optional("readPending", description: "Whether a stream read is pending", schema: .boolean),
            bridgeOptionalCount("readRequestCount", "Stream read requests"),
            bridgeOptionalCount("receivedByteCount", "Bytes received from the stream"),
            bridgeOptionalCount("retainedByteCount", "Bytes currently retained by the decoder"),
            bridgeOptionalString("routeFailureCode", "Most recent frame routing failure code"),
            bridgeOptionalCount("routedFrameCount", "Frames routed to the consumer"),
            bridgeOptionalCount("streamOpenCount", "Metadata stream openings"),
        ])
    }
}

extension IPCBridgeRenderDiagnostics: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "evaluateSucceeded", description: "Whether page-state evaluation completed", schema: .boolean),
            bridgeCount("pageErrorCount", "Page errors observed"),
            .init(name: "pageErrorKinds", description: "Page error classifications", schema: .array(items: .string())),
            .init(
                name: "pageErrorMessages", description: "Page error diagnostic messages",
                schema: .array(items: .string())),
            .init(
                name: "nativeActivity", description: "Native Bridge pane activity state",
                schema: try IPCBridgeNativeActivity.ipcSchema()),
            .init(
                name: "foregroundWorkEpoch", description: "Foreground work generation",
                schema: IPCSchemaScalars.unsignedInteger),
            .init(name: "dirtyFactPresent", description: "Whether unresolved dirty work is present", schema: .boolean),
            .init(name: "activeRefreshPassPresent", description: "Whether a refresh pass is active", schema: .boolean),
            bridgeCount("refreshPassCount", "Refresh passes observed"),
            .optional(
                "productMetadataStream", description: "Product metadata stream diagnostics when available",
                schema: try IPCBridgeProductMetadataStreamDiagnostic.ipcSchema()),
            .init(
                name: "productSession", description: "Native product-session resource diagnostics",
                schema: try IPCBridgeProductSessionDiagnostic.ipcSchema()),
        ])
    }
}

extension IPCBridgeRenderSummary: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        var fields: [IPCObjectField] = [
            bridgeOptionalString("pageTitle", "Rendered page title"),
            .init(name: "hasAppRoot", description: "Whether the Bridge app root is mounted", schema: .boolean),
            .init(name: "hasEmptyShell", description: "Whether the empty Bridge shell is visible", schema: .boolean),
            .init(name: "hasReviewShell", description: "Whether the review shell is visible", schema: .boolean),
            bridgeOptionalString("sidebarPosition", "Rendered sidebar placement"),
        ]
        fields += [
            bridgeOptionalBoolean("hasFileShell", "Whether the file-view shell is present"),
            bridgeOptionalBoolean("hasFileTree", "Whether the file tree is present"),
            bridgeOptionalBoolean("hasFileCodeView", "Whether the code viewer is present"),
            bridgeOptionalString("bridgeProtocol", "Bridge protocol version reported by the page"),
            bridgeOptionalString("worktreeSourceState", "Worktree source loading state"),
            bridgeOptionalString("worktreeOpenFileState", "Open-file request state"),
            bridgeOptionalString("worktreeOpenFilePath", "Requested worktree-relative file path"),
            bridgeOptionalString("worktreeRenderedFilePath", "Currently rendered worktree-relative file path"),
            bridgeOptionalString("worktreeSelectedDisplayPath", "Selected file display path"),
            bridgeOptionalCount("worktreeDescriptorCount", "Loaded worktree file descriptors"),
            bridgeOptionalCount("worktreeTotalDescriptorCount", "Total worktree file descriptors"),
            bridgeOptionalCount("worktreeIntakeFrameCount", "Worktree intake frames processed"),
            bridgeOptionalCount("worktreeCommandCount", "Worktree commands observed"),
            bridgeOptionalCount("worktreeOpenSourceCommandCount", "Open-source commands observed"),
            bridgeOptionalCount("worktreeCodeTextLength", "Rendered worktree code length in UTF-16 code units"),
            bridgeOptionalString("activeViewerMode", "Active file viewer mode"),
            bridgeOptionalString("documentVisibilityState", "Browser document visibility state"),
            bridgeOptionalString("frameLivenessRafAlive", "Animation-frame liveness state"),
            bridgeOptionalCount("reviewMetadataGeneration", "Loaded review metadata generation"),
            bridgeOptionalCount("reviewMetadataItemCount", "Review metadata item count"),
            bridgeOptionalCount("reviewMetadataTreeRowCount", "Rendered review tree row count"),
            bridgeOptionalString("reviewSelectedItemId", "Selected review item identifier"),
            bridgeOptionalCount("reviewCodeTextLength", "Rendered review code length in UTF-16 code units"),
            bridgeOptionalString("comparisonTriggerLabel", "Comparison control label"),
            bridgeOptionalString("comparisonTriggerDescription", "Comparison control description"),
            bridgeOptionalString("comparisonTriggerState", "Comparison control state"),
            bridgeOptionalString("comparisonTargetRevision", "Resolved comparison target revision"),
            bridgeOptionalString("comparisonSharedStartRevision", "Resolved shared-start revision"),
            .optional(
                "contentTopbarFrame", description: "Content top bar frame", schema: try IPCBridgeDOMRect.ipcSchema()),
            .optional(
                "contentTopbarControlsFrame", description: "Content top bar controls frame",
                schema: try IPCBridgeDOMRect.ipcSchema()),
            .optional(
                "comparisonTriggerFrame", description: "Comparison trigger frame",
                schema: try IPCBridgeDOMRect.ipcSchema()),
            .optional(
                "visibleHydrationStateProbe", description: "Visible hydration state measurements",
                schema: try IPCBridgeVisibleHydrationStateProbe.ipcSchema()),
            .optional(
                "visibleHydrationDiscardProbe", description: "Discarded hydration-result measurements",
                schema: try IPCBridgeVisibleHydrationDiscardProbe.ipcSchema()),
            .optional(
                "frameJankProbe", description: "Browser frame-jank measurements",
                schema: try IPCBridgeFrameJankProbe.ipcSchema()),
        ]
        return .object(fields: fields)
    }
}

extension IPCBridgeRenderStateResult: IPCSchemaProviding {
    package static func ipcSchema() throws -> IPCJSONSchema {
        .object(fields: [
            .init(name: "paneId", description: "Bridge pane UUID", schema: IPCSchemaScalars.uuid),
            .init(
                name: "summary", description: "Page-rendered state summary",
                schema: try IPCBridgeRenderSummary.ipcSchema()),
            .init(
                name: "diagnostics", description: "Native and page diagnostic state",
                schema: try IPCBridgeRenderDiagnostics.ipcSchema()),
            .optional(
                "visibleHydrationStateProbe", description: "Requested visible hydration state probe",
                schema: try IPCBridgeVisibleHydrationStateProbe.ipcSchema()),
            .optional(
                "visibleHydrationDiscardProbe", description: "Requested hydration discard probe",
                schema: try IPCBridgeVisibleHydrationDiscardProbe.ipcSchema()),
            .optional(
                "frameJankProbe", description: "Requested frame-jank probe",
                schema: try IPCBridgeFrameJankProbe.ipcSchema()),
        ])
    }
}

private func bridgeCount(_ name: String, _ description: String) -> IPCObjectField {
    .init(name: name, description: description, schema: .integer(minimum: 0))
}

private func bridgeOptionalCount(_ name: String, _ description: String) -> IPCObjectField {
    .optional(name, description: description, schema: .integer(minimum: 0))
}

private func bridgeOptionalString(_ name: String, _ description: String) -> IPCObjectField {
    .optional(name, description: description, schema: .string())
}

private func bridgeOptionalBoolean(_ name: String, _ description: String) -> IPCObjectField {
    .optional(name, description: description, schema: .boolean)
}
