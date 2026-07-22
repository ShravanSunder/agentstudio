import Foundation
import Testing

@testable import AgentStudio

@Suite
struct BridgeTelemetryEventValidatorTests {
    @Test
    func scopeGateExposesOnlyBrowserOwnedScopesToBridgeWeb() {
        let scopeGate = BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit])

        #expect(scopeGate.browserExposedScopes == [.web])
    }

    @Test
    func validatorAcceptsSafeEnabledSamples() throws {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = BridgeTelemetrySample(
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

        let result = validator.validate(sample)

        #expect(result == .accepted)
    }

    @Test
    func validatorAcceptsFrameJankTelemetrySamples() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.frame_jank",
                phase: "frame_jank",
                plane: "control",
                priority: "hot",
                slice: "frame_jank",
                transport: "local",
                extraStrings: [
                    "agentstudio.bridge.frame_jank.kind": "dropped_frame",
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.viewer": "review",
                ],
                extraNumbers: [
                    "agentstudio.bridge.frame_jank.dropped_frame.count": 3,
                    "agentstudio.bridge.frame_jank.dropped_frame.worst_gap_ms": 72,
                    "agentstudio.bridge.frame_jank.long_task.count": 2,
                    "agentstudio.bridge.frame_jank.long_task.max_ms": 54,
                    "agentstudio.bridge.frame_jank.long_task.total_ms": 94,
                ],
                extraBooleans: [
                    "agentstudio.bridge.viewer.active": false
                ]
            )
        )

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorRejectsReviewPackageDataOverPushTransport() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packagePushSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "push"
            )
        )
        let deltaPushSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "warm",
                slice: "diff_package_delta",
                transport: "push"
            )
        )

        #expect(validator.validate(packagePushSample) == .dropped(.unsafeAttribute))
        #expect(validator.validate(deltaPushSample) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorAcceptsReviewFirstRenderAfterIntakeTransport() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.first_render",
                phase: "render",
                plane: "data",
                priority: "hot",
                slice: "review_metadata",
                transport: "intake"
            )
        )

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorRejectsLegacyReviewPackageSlicesOverIntakeTransport() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packageApplySample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "diff_package_metadata",
                transport: "intake"
            )
        )
        let firstRenderSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.first_render",
                phase: "render",
                plane: "data",
                priority: "hot",
                slice: "diff_package_metadata",
                transport: "intake"
            )
        )
        let intakeFrameSample = sampleWithWebAttributes(
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

        #expect(validator.validate(packageApplySample) == .dropped(.unsafeAttribute))
        #expect(validator.validate(firstRenderSample) == .dropped(.unsafeAttribute))
        #expect(validator.validate(intakeFrameSample) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorAcceptsReviewProtocolSlicesOverIntakeTransport() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let snapshotIntakeApplySample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.intake_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "review_metadata",
                transport: "intake"
            )
        )
        let snapshotPackageApplySample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "cold",
                slice: "review_metadata",
                transport: "intake"
            )
        )
        let deltaPackageApplySample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "data",
                priority: "warm",
                slice: "review_delta",
                transport: "intake"
            )
        )
        let windowIntakeFrameSample = sampleWithWebAttributes(
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

        #expect(validator.validate(snapshotIntakeApplySample) == .accepted)
        #expect(validator.validate(snapshotPackageApplySample) == .accepted)
        #expect(validator.validate(deltaPackageApplySample) == .accepted)
        #expect(validator.validate(windowIntakeFrameSample) == .accepted)
    }

    @Test
    func validatorAcceptsCurrentReviewStartupEmitterShapes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let reviewMetadataApplySample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.review_metadata_apply",
                phase: "review_metadata_apply",
                plane: "data",
                priority: "hot",
                slice: "review_metadata",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "none",
                ],
                extraNumbers: [
                    "agentstudio.bridge.review.item_count": 8,
                    "agentstudio.bridge.review.metadata_carry_forward.unverified_keep.count": 0,
                    "agentstudio.bridge.review.metadata_carry_forward.verified_drop.count": 0,
                    "agentstudio.bridge.review.metadata_carry_forward.verified_keep.count": 0,
                ]
            )
        )
        let reviewReadySample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.review_ready",
                phase: "review_ready",
                plane: "data",
                priority: "hot",
                slice: "review_projection",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "none",
                ],
                extraNumbers: [
                    "agentstudio.bridge.review.item_count": 8
                ]
            )
        )
        let reviewMetadataCarryForwardSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.review_metadata_apply",
                phase: "review_metadata_apply",
                plane: "data",
                priority: "hot",
                slice: "review_metadata",
                transport: "intake",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "metadata_carry_forward_verification",
                ],
                extraNumbers: [
                    "agentstudio.bridge.review.metadata_carry_forward.unverified_keep.count": 0,
                    "agentstudio.bridge.review.metadata_carry_forward.verified_drop.count": 1,
                    "agentstudio.bridge.review.metadata_carry_forward.verified_keep.count": 2,
                ]
            )
        )

        #expect(validator.validate(reviewMetadataApplySample) == .accepted)
        #expect(validator.validate(reviewReadySample) == .accepted)
        #expect(validator.validate(reviewMetadataCarryForwardSample) == .accepted)
    }

    @Test
    func validatorAcceptsUnknownReviewIntakeDropTelemetry() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsContentFetchTelemetryWithContentOnlyAttributes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsDemandContentFetchTelemetryWithResultAttributes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsSelectedContentDroppedTelemetryContract() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.selected_content_dropped",
                phase: "selected_content_dropped",
                plane: "data",
                priority: "hot",
                slice: "content_fetch",
                transport: "content",
                extraStrings: [
                    "agentstudio.bridge.drop_reason": "revision_churn",
                    "agentstudio.bridge.result": "dropped",
                    "agentstudio.bridge.viewer": "review",
                ]
            )
        )

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsWorkerSelectedContentDroppedStaleReasons() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )

        for reason in ["stale_before_fetch", "stale_after_fetch", "stale_before_publish"] {
            let sample = sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.web.selected_content_dropped",
                    phase: "selected_content_dropped",
                    plane: "data",
                    priority: "hot",
                    slice: "content_fetch",
                    transport: "content",
                    extraStrings: [
                        "agentstudio.bridge.drop_reason": reason,
                        "agentstudio.bridge.result": "dropped",
                        "agentstudio.bridge.viewer": "review",
                    ]
                )
            )

            #expect(validator.validate(sample) == .accepted)
        }
    }

    @Test
    func validatorAcceptsWorktreeFileContentFetchTelemetryWithTimingAttributes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsDemandContentQueueTelemetryWithInterestAttribute() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsConnectionPushApplyTelemetryAsControlPlane() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.push_apply",
                phase: "apply",
                plane: "control",
                priority: "hot",
                slice: "connection_health",
                transport: "push"
            )
        )

        #expect(validator.validate(sample) == .accepted)
    }

}

@Suite
struct BridgeTelemetryEventValidatorContractTests {
    @Test
    func validatorAcceptsViewerTelemetryContracts() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        for sample in bridgeViewerTelemetryContractSamples {
            #expect(validator.validate(sample) == .accepted)
        }
    }

    @Test
    func validatorAcceptsCurrentReviewProjectionModeTelemetry() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let projectionKinds = [
            "normal_review",
            "guided_review",
            "plans_and_specs",
        ]

        for projectionKind in projectionKinds {
            let sample = sampleWithWebAttributes(
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

            #expect(validator.validate(sample) == .accepted)
        }
    }

}

@Suite
struct BridgeTelemetryEventValidatorSafetyTests {
    @Test
    func validatorRejectsEventInappropriateAuxiliaryAttributes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let packageApplyWithRPCClass = sampleWithWebAttributes(
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
        let rpcSendWithoutMethodClass = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "control",
                priority: "warm",
                slice: "review_rpc",
                transport: "rpc"
            )
        )
        let telemetryDropWithoutDroppedCount = sampleWithWebAttributes(
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
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = BridgeTelemetrySample(
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

        #expect(validator.validate(sample) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsSamplesMissingRequiredTaxonomyFields() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = BridgeTelemetrySample(
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

        #expect(validator.validate(sample) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsSpoofedBrowserTelemetryCombinations() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )

        let telemetryDropAsHot = sampleWithWebAttributes(
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
        let rpcSendAsObservability = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.web.rpc_send",
                phase: "send",
                plane: "observability",
                priority: "best_effort",
                slice: "review_rpc",
                transport: "rpc"
            )
        )
        let contentFetchAsSwift = sampleWithWebAttributes(
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
        #expect(BridgeTelemetryDropReason.rateLimited.rawValue == "rate_limited")
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
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsWorktreeFileIntakeRejectTelemetry() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
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

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorRejectsDisabledScopeWithExplicitDropReason() throws {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift])
        )
        let sample = BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.push_apply",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [:],
            numericAttributes: [:],
            booleanAttributes: [:]
        )

        #expect(validator.validate(sample) == .dropped(.disabledScope))
    }

    @Test
    func validatorRejectsUnknownEventNamesAndAttributes() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let unknownEventSample = BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.web.cmd_550e8400-e29b-41d4-a716-446655440000",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [:],
            numericAttributes: [:],
            booleanAttributes: [:]
        )
        let unsafeAttributeSample = BridgeTelemetrySample(
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

        #expect(validator.validate(unknownEventSample) == .dropped(.unsafeEventName))
        #expect(validator.validate(unsafeAttributeSample) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsUnknownControlledStringValues() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = BridgeTelemetrySample(
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

        #expect(validator.validate(sample) == .dropped(.unsafeAttribute))
    }

    @Test
    func validatorRejectsBrowserEventsThatClaimNativeScopesOrNames() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.swift, .web, .webKit])
        )
        let nativeScopeSample = BridgeTelemetrySample(
            scope: .swift,
            name: "performance.bridge.swift.package_build",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [:],
            numericAttributes: [:],
            booleanAttributes: [:]
        )
        let nativeEventSample = BridgeTelemetrySample(
            scope: .web,
            name: "performance.bridge.webkit.rpc_response",
            durationMilliseconds: nil,
            traceContext: nil,
            stringAttributes: [:],
            numericAttributes: [:],
            booleanAttributes: [:]
        )

        #expect(validator.validate(nativeScopeSample) == .dropped(.disabledScope))
        #expect(validator.validate(nativeEventSample) == .dropped(.unsafeEventName))
    }

}
