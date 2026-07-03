import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryBatchValidatorTests {
    @Test
    func scopeGateExposesOnlyBrowserOwnedScopesToBridgeWeb() {
        let scopeGate = BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit])

        #expect(scopeGate.browserExposedScopes == [.web])
    }

    @Test
    func validatorAcceptsSafeEnabledSamples() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.intake_frame",
                    durationMilliseconds: 2.5,
                    traceContext: try BridgeTraceContext(
                        traceId: "11111111111111111111111111111111",
                        spanId: "2222222222222222",
                        parentSpanId: nil,
                        sampled: true
                    ),
                    stringAttributes: [
                        "agentstudio.bridge.intake.frame_kind": "review.metadataSnapshot",
                        "agentstudio.bridge.plane": "data",
                        "agentstudio.bridge.phase": "intake",
                        "agentstudio.bridge.priority": "cold",
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.result_reason": "none",
                        "agentstudio.bridge.slice": "review_metadata",
                        "agentstudio.bridge.transport": "intake",
                    ],
                    numericAttributes: [
                        "agentstudio.bridge.intake.generation": 1,
                        "agentstudio.bridge.intake.sequence": 1,
                    ],
                    booleanAttributes: [:]
                )
            ]
        )

        let result = validator.validate(batch)

        #expect(result == .accepted(batch))
    }

    @Test
    func validatorRejectsReviewPackageDataOverPushTransport() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packagePushBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "push"
            )
        )
        let deltaPushBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "warm",
                slice: "diff_package_delta",
                transport: "push"
            )
        )

        #expect(validator.validate(packagePushBatch) == .dropped(.unsafeAttribute))
        #expect(validator.validate(deltaPushBatch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorAcceptsReviewFirstRenderAfterIntakeTransport() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.first_render",
                phase: "render",
                plane: "data",
                priority: "hot",
                slice: "review_metadata",
                transport: "intake"
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorRejectsLegacyReviewPackageSlicesOverIntakeTransport() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packageApplyBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "intake"
            )
        )
        let firstRenderBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.first_render",
                phase: "render",
                plane: "data",
                priority: "hot",
                slice: "diff_package_metadata",
                transport: "intake"
            )
        )
        let intakeFrameBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.intake_frame",
                phase: "intake",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.intake.frame_kind": "review.metadataSnapshot",
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "none",
                ],
                extraNumbers: [
                    "agentstudio.bridge.intake.generation": 1,
                    "agentstudio.bridge.intake.sequence": 1,
                ]
            )
        )

        #expect(validator.validate(packageApplyBatch) == .dropped(.unsafeAttribute))
        #expect(validator.validate(firstRenderBatch) == .dropped(.unsafeAttribute))
        #expect(validator.validate(intakeFrameBatch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorAcceptsReviewProtocolSlicesOverIntakeTransport() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let snapshotIntakeApplyBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.intake_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "review_metadata",
                transport: "intake"
            )
        )
        let snapshotPackageApplyBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "review_metadata",
                transport: "intake"
            )
        )
        let deltaPackageApplyBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "warm",
                slice: "review_delta",
                transport: "intake"
            )
        )
        let windowIntakeFrameBatch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.intake_frame",
                phase: "intake",
                plane: "data",
                priority: "cold",
                slice: "review_metadata",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.intake.frame_kind": "review.metadataWindow",
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "none",
                ],
                extraNumbers: [
                    "agentstudio.bridge.intake.generation": 1,
                    "agentstudio.bridge.intake.sequence": 2,
                ]
            )
        )

        #expect(validator.validate(snapshotIntakeApplyBatch) == .accepted(snapshotIntakeApplyBatch))
        #expect(validator.validate(snapshotPackageApplyBatch) == .accepted(snapshotPackageApplyBatch))
        #expect(validator.validate(deltaPackageApplyBatch) == .accepted(deltaPackageApplyBatch))
        #expect(validator.validate(windowIntakeFrameBatch) == .accepted(windowIntakeFrameBatch))
    }

    @Test
    func validatorAcceptsUnknownReviewIntakeDropTelemetry() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.intake_frame",
                phase: "intake",
                plane: "data",
                priority: "warm",
                slice: "review_projection",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.intake.frame_kind": "unknown",
                    "agentstudio.bridge.result": "failed",
                    "agentstudio.bridge.result_reason": "frame_decode_failed",
                ],
                extraNumbers: [
                    "agentstudio.bridge.intake.generation": 0,
                    "agentstudio.bridge.intake.sequence": 0,
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsContentFetchTelemetryWithContentOnlyAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.content_fetch",
                phase: "fetch",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "content",
                extraStrings: [
                    "agentstudio.bridge.content.correlation_mode": "summary",
                    "agentstudio.bridge.content.role": "head",
                ],
                extraBooleans: [
                    "agentstudio.bridge.header_missing": true,
                    "agentstudio.bridge.header_supported": false,
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsDemandContentFetchTelemetryWithResultAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.content_fetch",
                phase: "fetch",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "content",
                extraStrings: [
                    "agentstudio.bridge.content.correlation_mode": "summary",
                    "agentstudio.bridge.content.interest": "selected",
                    "agentstudio.bridge.content.role": "head",
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "none",
                ],
                extraBooleans: [
                    "agentstudio.bridge.header_missing": true,
                    "agentstudio.bridge.header_supported": false,
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsWorktreeFileContentFetchTelemetryWithTimingAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.content_fetch",
                phase: "fetch",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "content",
                extraStrings: [
                    "agentstudio.bridge.content.correlation_mode": "summary",
                    "agentstudio.bridge.content.role": "file",
                    "agentstudio.bridge.demand.lane": "foreground",
                    "agentstudio.bridge.file_size_bucket": "small",
                    "agentstudio.bridge.generation_relation": "current",
                    "agentstudio.bridge.protocol": "worktree-file",
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "none",
                    "agentstudio.bridge.viewer": "file",
                ],
                extraNumbers: [
                    "agentstudio.bridge.content.byte_length": 2048,
                    "agentstudio.bridge.content.estimated_bytes": 4096,
                    "agentstudio.bridge.content.first_chunk_wait_ms": 4.5,
                    "agentstudio.bridge.content.response_wait_ms": 3.25,
                    "agentstudio.bridge.content.stream_read_ms": 9.75,
                ],
                extraBooleans: [
                    "agentstudio.bridge.header_missing": true,
                    "agentstudio.bridge.header_supported": false,
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsDemandContentQueueTelemetryWithInterestAttribute() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.viewer.content_queue",
                phase: "content_queue",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "content",
                extraStrings: [
                    "agentstudio.bridge.content.interest": "selected",
                    "agentstudio.bridge.content.priority": "selected",
                    "agentstudio.bridge.content.role": "head",
                    "agentstudio.bridge.queue.depth_bucket": "small",
                    "agentstudio.bridge.result": "success",
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsConnectionPushApplyTelemetryAsControlPlane() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "control",
                priority: "hot",
                slice: "connection_health",
                transport: "push"
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }
}

@Suite
struct BridgeTelemetryBatchValidatorContractTests {
    @Test
    func validatorAcceptsViewerTelemetryContracts() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: bridgeViewerTelemetryContractSamples
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsCurrentReviewProjectionModeTelemetry() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let projectionKinds = [
            "normal_review",
            "guided_review",
            "plans_and_specs",
        ]

        for projectionKind in projectionKinds {
            let batch = batchWithWebSample(
                WebSampleProps(
                    name: "performance.bridge.trees.projection_build",
                    phase: "projection_build",
                    plane: "data",
                    priority: "warm",
                    slice: "review_projection",
                    transport: "worker",
                    extraStrings: [
                        "agentstudio.bridge.fixture_class": "large",
                        "agentstudio.bridge.item_count_bucket": "large",
                        "agentstudio.bridge.projection.kind": projectionKind,
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.tree_path_count_bucket": "large",
                        "agentstudio.bridge.worker.lane": "projection",
                    ]
                )
            )

            #expect(validator.validate(batch) == .accepted(batch))
        }
    }

}

@Suite
struct BridgeTelemetryBatchValidatorSafetyTests {
    @Test
    func validatorRejectsEventInappropriateAuxiliaryAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packageApplyWithRPCClass = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "push",
                extraStrings: ["agentstudio.bridge.rpc.method_class": "telemetry"]
            )
        )
        let rpcSendWithoutMethodClass = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "control",
                priority: "warm",
                slice: "review_rpc",
                transport: "rpc"
            )
        )
        let telemetryDropWithoutDroppedCount = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "best_effort",
                slice: "telemetry_drop",
                transport: "rpc",
                extraStrings: ["agentstudio.bridge.telemetry.drop_reason": "queue_saturated"]
            )
        )

        #expect(validator.validate(packageApplyWithRPCClass) == .dropped(.unsafeAttribute))
        #expect(validator.validate(rpcSendWithoutMethodClass) == .dropped(.unsafeAttribute))
        #expect(validator.validate(telemetryDropWithoutDroppedCount) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsHistoricalLaneAttribute() {
        let historicalBridgeLane = ["agentstudio", "bridge", "lane"].joined(separator: ".")
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.push_apply",
                    durationMilliseconds: 2.5,
                    traceContext: nil,
                    stringAttributes: [
                        historicalBridgeLane: "warm",
                        "agentstudio.bridge.phase": "package_apply",
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsSamplesMissingRequiredTaxonomyFields() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.telemetry_drop",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.plane": "observability",
                        "agentstudio.bridge.priority": "best_effort",
                        "agentstudio.bridge.slice": "telemetry_drop",
                        "agentstudio.bridge.telemetry.drop_reason": "queue_saturated",
                    ],
                    numericAttributes: [
                        "agentstudio.bridge.telemetry.dropped_count": 1
                    ],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsSpoofedBrowserTelemetryCombinations() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )

        let telemetryDropAsHot = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "hot",
                slice: "telemetry_drop",
                transport: "rpc",
                extraStrings: ["agentstudio.bridge.telemetry.drop_reason": "queue_saturated"]
            )
        )
        let rpcSendAsObservability = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "observability",
                priority: "best_effort",
                slice: "review_rpc",
                transport: "rpc"
            )
        )
        let contentFetchAsSwift = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.content_fetch",
                phase: "fetch",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "swift"
            )
        )

        #expect(validator.validate(telemetryDropAsHot) == .dropped(.unsafeAttribute))
        #expect(validator.validate(rpcSendAsObservability) == .dropped(.unsafeAttribute))
        #expect(validator.validate(contentFetchAsSwift) == .dropped(.unsafeAttribute))
    }

    @Test
    func dropReasonWireValuesUseSnakeCase() throws {
        #expect(BridgeTelemetryDropReason.queueSaturated.rawValue == "queue_saturated")
        #expect(BridgeTelemetryDropReason.decodingFailed.rawValue == "decoding_failed")
        #expect(BridgeTelemetryDropReason.hostPortMessageInvalid.rawValue == "host_port_message_invalid")

        let decoded = try JSONDecoder().decode(
            BridgeTelemetryDropReason.self,
            from: Data(#""too_many_samples""#.utf8)
        )

        #expect(decoded == .tooManySamples)
    }

    @Test
    func validatorAcceptsHostPortMessageInvalidTelemetryDropReason() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.telemetry_drop",
                phase: "dropped",
                plane: "observability",
                priority: "best_effort",
                slice: "telemetry_drop",
                transport: "rpc",
                extraStrings: [
                    "agentstudio.bridge.telemetry.drop_reason": "host_port_message_invalid"
                ],
                extraNumbers: [
                    "agentstudio.bridge.telemetry.dropped_count": 1
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorAcceptsWorktreeFileIntakeRejectTelemetry() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = batchWithWebSample(
            WebSampleProps(
                name: "performance.bridge.web.worktree_file_intake_reject",
                phase: "intake",
                plane: "control",
                priority: "hot",
                slice: "connection_health",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.result": "dropped",
                    "agentstudio.bridge.result_reason": "generation_mismatch",
                ],
                extraNumbers: [
                    "agentstudio.bridge.intake.generation": 2,
                    "agentstudio.bridge.worktree_file.receiver.generation": 1,
                ],
                extraBooleans: [
                    "agentstudio.bridge.reopen_signaled": true,
                    "agentstudio.bridge.stream_id_matches": true,
                ]
            )
        )

        #expect(validator.validate(batch) == .accepted(batch))
    }

    @Test
    func validatorRejectsDisabledScopeWithExplicitDropReason() throws {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.push_apply",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.disabledScope))
    }

    @Test
    func validatorRejectsOversizedRawPayloadBeforeDecode() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let data = Data(repeating: 65, count: BridgeTelemetryLimits.maxEncodedBatchBytes + 1)

        #expect(validator.decodeAndValidate(data) == .dropped(.encodedBatchTooLarge))
    }

    @Test
    func validatorRejectsUnknownEventNamesAndAttributes() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let unknownEventBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.cmd_550e8400-e29b-41d4-a716-446655440000",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let unsafeAttributeBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.push_apply",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.item_id": "private-item-id"
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(unknownEventBatch) == .dropped(.unsafeEventName))
        #expect(validator.validate(unsafeAttributeBatch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsUnknownControlledStringValues() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.web.push_apply",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [
                        "agentstudio.bridge.phase": "phase_550e8400e29b41d4a716446655440000"
                    ],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(batch) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsBrowserBatchesThatClaimNativeScopesOrEvents() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit])
        )
        let nativeScopeBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .swift,
                    name: "performance.bridge.swift.package_build",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )
        let nativeEventBatch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: [
                BridgeTelemetrySample(
                    scope: .web,
                    name: "performance.bridge.webkit.rpc_response",
                    durationMilliseconds: nil,
                    traceContext: nil,
                    stringAttributes: [:],
                    numericAttributes: [:],
                    booleanAttributes: [:]
                )
            ]
        )

        #expect(validator.validate(nativeScopeBatch) == .dropped(.disabledScope))
        #expect(validator.validate(nativeEventBatch) == .dropped(.unsafeEventName))
    }

    @Test
    func validatorRejectsTooManySamples() {
        let validator = BridgeTelemetryBatchValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let samples = Array(
            repeating: BridgeTelemetrySample(
                scope: .web,
                name: "performance.bridge.web.push_apply",
                durationMilliseconds: nil,
                traceContext: nil,
                stringAttributes: [:],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            count: BridgeTelemetryLimits.maxSamplesPerBatch + 1
        )
        let batch = BridgeTelemetryBatch(
            schemaVersion: 1,
            scenario: "package_apply_content_fetch_v1",
            samples: samples
        )

        #expect(validator.validate(batch) == .dropped(.tooManySamples))
    }
}
