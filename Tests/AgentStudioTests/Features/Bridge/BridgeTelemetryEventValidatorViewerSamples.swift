import Foundation
import Testing

@testable import AgentStudio

var bridgeViewerTelemetryContractSamples: [BridgeTelemetrySample] {
    [
        viewerSample(
            name: "performance.bridge.trees.projection_build",
            phase: "projection_build",
            priority: "warm",
            slice: "review_projection",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.fixture_class": "smoke",
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.projection.kind": "all_files",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.tree_path_count_bucket": "small",
                "agentstudio.bridge.worker.lane": "none",
            ]
        ),
        viewerSample(
            name: "performance.bridge.trees.prepare_input",
            phase: "worktree_file_frame_apply",
            priority: "warm",
            slice: "tree_prepare_input",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.fixture_class": "large",
                "agentstudio.bridge.projection.kind": "source",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.tree_path_count_bucket": "large",
            ],
            extraNumbers: [
                "agentstudio.bridge.worktree_file.tree.current_row.count": 2000,
                "agentstudio.bridge.worktree_file.tree.descriptor.count": 8,
                "agentstudio.bridge.worktree_file.tree.incoming_frame.count": 1,
                "agentstudio.bridge.worktree_file.tree.window.row.count": 200,
            ]
        ),
        viewerSample(
            name: "performance.bridge.trees.prepare_input",
            phase: "worktree_file_projection",
            priority: "warm",
            slice: "tree_prepare_input",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.fixture_class": "large",
                "agentstudio.bridge.projection.kind": "source",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.tree_path_count_bucket": "large",
            ],
            extraNumbers: [
                "agentstudio.bridge.worktree_file.tree.current_row.count": 2000,
                "agentstudio.bridge.worktree_file.tree.descriptor.count": 8,
                "agentstudio.bridge.worktree_file.tree.incoming_frame.count": 0,
                "agentstudio.bridge.worktree_file.tree.window.row.count": 0,
            ]
        ),
        viewerSample(
            name: "performance.bridge.web.file_open_ready",
            phase: "file_open_ready",
            priority: "hot",
            slice: "content_fetch",
            transport: "content",
            extraStrings: [
                "agentstudio.bridge.content.role": "file",
                "agentstudio.bridge.demand.disposition": "cold-loaded",
                "agentstudio.bridge.demand.lane": "foreground",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": "none",
                "agentstudio.bridge.viewer": "file",
            ],
            extraNumbers: [
                "agentstudio.bridge.content.body_registry_commit_ms": 1,
                "agentstudio.bridge.content.estimated_bytes": 512,
                "agentstudio.bridge.content.first_chunk_wait_ms": 2,
                "agentstudio.bridge.content.response_wait_ms": 3,
                "agentstudio.bridge.content.stream_read_ms": 4,
                "agentstudio.bridge.demand.executor_in_flight_ms": 5,
                "agentstudio.bridge.demand.executor_pending_wait_ms": 6,
                "agentstudio.bridge.demand.request.sequence": 7,
                "agentstudio.bridge.demand.scheduler_queue_wait_ms": 8,
                "agentstudio.bridge.source.generation": 9,
            ]
        ),
        viewerSample(
            name: "performance.bridge.web.visible_demand_settled",
            phase: "visible_demand_settled",
            priority: "hot",
            slice: "content_fetch",
            transport: "content",
            extraStrings: [
                "agentstudio.bridge.content.role": "file",
                "agentstudio.bridge.demand.lane": "visible",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": "none",
                "agentstudio.bridge.viewer": "file",
            ],
            extraNumbers: [
                "agentstudio.bridge.content.first_chunk_wait_ms": 2,
                "agentstudio.bridge.content.response_wait_ms": 3,
                "agentstudio.bridge.content.stream_read_ms": 4,
                "agentstudio.bridge.demand.enqueue_accepted.count": 12,
                "agentstudio.bridge.demand.enqueue_rejected.count": 0,
                "agentstudio.bridge.demand.executor_in_flight_ms": 5,
                "agentstudio.bridge.demand.executor_pending_wait_ms": 6,
                "agentstudio.bridge.demand.failed.count": 0,
                "agentstudio.bridge.demand.intent.count": 12,
                "agentstudio.bridge.demand.loaded.count": 12,
                "agentstudio.bridge.demand.request.sequence": 8,
                "agentstudio.bridge.demand.scheduler_queue_wait_ms": 7,
                "agentstudio.bridge.visible_item.count": 12,
            ]
        ),
        viewerSample(
            name: "performance.bridge.trees.scroll_visible_demand",
            phase: "scroll_visible_demand",
            priority: "hot",
            slice: "tree_prepare_input",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.demand.disposition": "published",
                "agentstudio.bridge.demand.lane": "visible",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": "none",
                "agentstudio.bridge.viewer": "file",
            ],
            extraNumbers: [
                "agentstudio.bridge.visible_item.count": 12
            ]
        ),
        viewerSample(
            name: "performance.bridge.viewer.content_queue",
            phase: "content_queue",
            priority: "hot",
            slice: "content_fetch",
            transport: "content",
            extraStrings: [
                "agentstudio.bridge.content.interest": "visible",
                "agentstudio.bridge.content.priority": "visible",
                "agentstudio.bridge.content.role": "head",
                "agentstudio.bridge.queue.depth_bucket": "small",
                "agentstudio.bridge.result": "success",
            ]
        ),
        viewerSample(
            name: "performance.bridge.pierre.item_update",
            phase: "item_update",
            priority: "hot",
            slice: "code_view_item",
            transport: "swift",
            extraStrings: [
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.item_update.kind": "hydrate",
                "agentstudio.bridge.result": "success",
            ]
        ),
        viewerSample(
            name: "performance.bridge.web.code_view_item_materialize",
            phase: "code_view_item_materialize",
            priority: "hot",
            slice: "code_view_item",
            transport: "swift",
            extraStrings: [
                "agentstudio.bridge.content_bytes_bucket": "small",
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.language_class": "swift",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.viewer": "review",
            ],
            extraBooleans: [
                "agentstudio.bridge.selected": true
            ]
        ),
        viewerSample(
            name: "performance.bridge.web.selected_content_painted",
            phase: "selected_content_painted",
            priority: "hot",
            slice: "code_view_item",
            transport: "swift",
            extraStrings: [
                "agentstudio.bridge.viewer": "review"
            ],
            extraNumbers: [
                "agentstudio.bridge.selected_content.click_to_paint_ms": 32,
                "agentstudio.bridge.selected_content.frame_wait_ms": 8,
                "agentstudio.bridge.selected_content.materialize_ms": 12,
            ]
        ),
        viewerSample(
            name: "performance.bridge.web.review_content_demand",
            phase: "review_content_demand",
            priority: "hot",
            slice: "content_fetch",
            transport: "content",
            extraStrings: [
                "agentstudio.bridge.content.interest": "selected",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.result_reason": "none",
                "agentstudio.bridge.viewer": "review",
            ],
            extraNumbers: [
                "agentstudio.bridge.demand.active.count": 0,
                "agentstudio.bridge.demand.deferred.count": 0,
                "agentstudio.bridge.demand.duration_ms": 24,
                "agentstudio.bridge.demand.failed.count": 0,
                "agentstudio.bridge.demand.foreground.count": 1,
                "agentstudio.bridge.demand.idle.count": 0,
                "agentstudio.bridge.demand.intent.count": 1,
                "agentstudio.bridge.demand.loaded.count": 1,
                "agentstudio.bridge.demand.nearby.count": 0,
                "agentstudio.bridge.demand.speculative.count": 0,
                "agentstudio.bridge.demand.visible.count": 0,
            ]
        ),
        viewerSample(
            name: "performance.bridge.shiki.highlight",
            phase: "highlight",
            priority: "hot",
            slice: "shiki_highlight",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.content_bytes_bucket": "small",
                "agentstudio.bridge.language_class": "swift",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.worker.lane": "pierre",
            ]
        ),
        viewerSample(
            name: "performance.bridge.worker.task",
            phase: "worker_task",
            priority: "warm",
            slice: "worker_task",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.worker.lane": "pierre",
                "agentstudio.bridge.worker.task_kind": "highlight",
            ]
        ),
        viewerSample(
            name: "performance.bridge.markdown.render_queue",
            phase: "markdown_queue",
            priority: "warm",
            slice: "markdown_preview",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.result": "queued",
                "agentstudio.bridge.worker.lane": "markdown",
            ]
        ),
        viewerSample(
            name: "performance.bridge.markdown.render",
            phase: "markdown_render",
            priority: "warm",
            slice: "markdown_preview",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.content_bytes_bucket": "small",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.worker.lane": "markdown",
            ],
            extraNumbers: [
                "agentstudio.bridge.markdown.input_bytes": 120,
                "agentstudio.bridge.markdown.output_bytes": 240,
            ]
        ),
        viewerSample(
            name: "performance.bridge.markdown.fallback",
            phase: "markdown_decision",
            priority: "warm",
            slice: "markdown_preview",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.markdown.fallback_reason": "notMarkdown",
                "agentstudio.bridge.result": "fallback",
                "agentstudio.bridge.worker.lane": "markdown",
            ]
        ),
        viewerSample(
            name: "performance.bridge.worker.task",
            phase: "worker_task",
            priority: "warm",
            slice: "worker_task",
            transport: "worker",
            extraStrings: [
                "agentstudio.bridge.item_count_bucket": "small",
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.worker.lane": "markdown",
                "agentstudio.bridge.worker.task_kind": "markdown_render",
            ]
        ),
        viewerSample(
            name: "performance.bridge.viewer.time_to_first_interaction",
            phase: "time_to_first_interaction",
            priority: "hot",
            slice: "content_fetch",
            transport: "content",
            extraStrings: [
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.viewer": "file",
                "agentstudio.bridge.viewer.ttfi_variant": "cold",
            ],
            extraNumbers: [
                "agentstudio.bridge.visible_item.count": 12
            ]
        ),
        viewerSample(
            name: "performance.bridge.viewer.time_to_first_interaction",
            phase: "time_to_first_interaction",
            priority: "hot",
            slice: "content_fetch",
            transport: "content",
            extraStrings: [
                "agentstudio.bridge.result": "success",
                "agentstudio.bridge.viewer": "review",
                "agentstudio.bridge.viewer.ttfi_variant": "warm",
            ],
            extraNumbers: [
                "agentstudio.bridge.visible_item.count": 8
            ]
        ),
    ]
}

struct WebSampleProps {
    let name: String
    let phase: String
    let plane: String
    let priority: String
    let slice: String
    let transport: String
    var extraStrings: [String: String] = [:]
    var extraNumbers: [String: Double] = [:]
    var extraBooleans: [String: Bool] = [:]
}

func sampleWithWebAttributes(_ props: WebSampleProps) -> BridgeTelemetrySample {
    var stringAttributes = [
        "agentstudio.bridge.phase": props.phase,
        "agentstudio.bridge.plane": props.plane,
        "agentstudio.bridge.priority": props.priority,
        "agentstudio.bridge.slice": props.slice,
        "agentstudio.bridge.transport": props.transport,
    ]
    stringAttributes.merge(props.extraStrings) { _, new in new }
    return BridgeTelemetrySample(
        scope: .web,
        name: props.name,
        durationMilliseconds: nil,
        traceContext: nil,
        stringAttributes: stringAttributes,
        numericAttributes: props.extraNumbers,
        booleanAttributes: props.extraBooleans
    )
}

func viewerSample(
    name: String,
    phase: String,
    priority: String,
    slice: String,
    transport: String,
    extraStrings: [String: String],
    extraNumbers: [String: Double] = [:],
    extraBooleans: [String: Bool] = [:]
) -> BridgeTelemetrySample {
    var stringAttributes = [
        "agentstudio.bridge.phase": phase,
        "agentstudio.bridge.plane": "data",
        "agentstudio.bridge.priority": priority,
        "agentstudio.bridge.slice": slice,
        "agentstudio.bridge.transport": transport,
    ]
    stringAttributes.merge(extraStrings) { _, new in new }
    return BridgeTelemetrySample(
        scope: .web,
        name: name,
        durationMilliseconds: 1,
        traceContext: nil,
        stringAttributes: stringAttributes,
        numericAttributes: extraNumbers,
        booleanAttributes: extraBooleans
    )
}

@Suite
struct BridgeTelemetryCommWorkerContractTests {
    @Test
    func validatorAcceptsCurrentCommWorkerTaskTelemetryContracts() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let messageHandlerSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "hot",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.command": "select",
                    "agentstudio.bridge.worker.lane": "selected",
                    "agentstudio.bridge.worker.task_kind": "message_handler",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 2,
                    "agentstudio.bridge.worker.queue_wait_ms": 4,
                ],
                extraBooleans: [
                    "agentstudio.bridge.worker.file_metadata_selected_path_resolved": true
                ]
            )
        )
        let contentPreparationSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "warm",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.lane": "visible",
                    "agentstudio.bridge.worker.payload_class": "inline",
                    "agentstudio.bridge.worker.task_kind": "content_preparation",
                    "agentstudio.bridge.worker.work_kind": "review_content_ready",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 3,
                    "agentstudio.bridge.worker.queue_wait_ms": 5,
                    "agentstudio.bridge.worker.source_epoch": 7,
                ]
            )
        )
        let storeActionSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "hot",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.action": "applySelectedFact",
                    "agentstudio.bridge.worker.lane": "selected",
                    "agentstudio.bridge.worker.task_kind": "store_action",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 2,
                    "agentstudio.bridge.worker.patch_count": 2,
                    "agentstudio.bridge.worker.touched_key_count": 5,
                ]
            )
        )
        #expect(validator.validate(messageHandlerSample) == .accepted)
        #expect(validator.validate(contentPreparationSample) == .accepted)
        #expect(validator.validate(storeActionSample) == .accepted)
    }

    @Test
    func validatorAcceptsCurrentCommWorkerCommandAndStoreActionVocabularies() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let commands = [
            "activeViewerModeUpdate",
            "fileDisplayResync",
            "fileQueryUpdate",
            "hover",
            "markFileViewed",
            "metadataInterestUpdate",
            "mode",
            "renderDisposition",
            "reviewIntakeReady",
            "reviewInvalidate",
            "reviewProjectionUpdate",
            "select",
            "viewport",
        ]
        for command in commands {
            let sample = sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.worker.task",
                    phase: "worker_task",
                    plane: "data",
                    priority: "warm",
                    slice: "worker_task",
                    transport: "worker",
                    extraStrings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.worker.command": command,
                        "agentstudio.bridge.worker.lane": "background",
                        "agentstudio.bridge.worker.task_kind": "message_handler",
                    ],
                    extraNumbers: [
                        "agentstudio.bridge.worker.handler_duration_ms": 1,
                        "agentstudio.bridge.worker.queue_wait_ms": 1,
                    ]
                )
            )
            #expect(validator.validate(sample) == .accepted)
        }

        let storeActions = [
            "applyContentReady",
            "applyContentTerminalAvailability",
            "applyFileViewSourceMutationFact",
            "applyFileViewSourceUpdateFact",
            "applyReviewInvalidationFact",
            "applyReviewRowMutationFact",
            "applyReviewSourceUpdateFact",
            "applySelectedFact",
            "applySelectedSourceChurnFact",
            "applyViewportFact",
        ]
        for action in storeActions {
            let sample = sampleWithWebAttributes(
                WebSampleProps(
                    name: "performance.bridge.worker.task",
                    phase: "worker_task",
                    plane: "data",
                    priority: "warm",
                    slice: "worker_task",
                    transport: "worker",
                    extraStrings: [
                        "agentstudio.bridge.result": "success",
                        "agentstudio.bridge.worker.action": action,
                        "agentstudio.bridge.worker.lane": "background",
                        "agentstudio.bridge.worker.task_kind": "store_action",
                    ],
                    extraNumbers: [
                        "agentstudio.bridge.worker.handler_duration_ms": 1,
                        "agentstudio.bridge.worker.patch_count": 0,
                        "agentstudio.bridge.worker.touched_key_count": 0,
                    ]
                )
            )
            #expect(validator.validate(sample) == .accepted)
        }
    }

    @Test
    func validatorAcceptsReviewSourceUpdateStoreActionWithoutResultReason() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let sample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "warm",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.action": "applyReviewSourceUpdateFact",
                    "agentstudio.bridge.worker.lane": "background",
                    "agentstudio.bridge.worker.task_kind": "store_action",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 0,
                    "agentstudio.bridge.worker.patch_count": 0,
                    "agentstudio.bridge.worker.source_epoch": 2,
                    "agentstudio.bridge.worker.touched_key_count": 2,
                ]
            )
        )

        #expect(validator.validate(sample) == .accepted)
    }

    @Test
    func validatorAcceptsReasonedCommWorkerTerminalTelemetryContracts() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let terminalStoreActionSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "warm",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "load_failed",
                    "agentstudio.bridge.worker.action": "applyContentTerminalAvailability",
                    "agentstudio.bridge.worker.lane": "visible",
                    "agentstudio.bridge.worker.task_kind": "store_action",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 2,
                    "agentstudio.bridge.worker.patch_count": 1,
                    "agentstudio.bridge.worker.source_epoch": 7,
                    "agentstudio.bridge.worker.touched_key_count": 1,
                ]
            )
        )
        let sourceResetStoreActionSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "warm",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.result_reason": "source_reset",
                    "agentstudio.bridge.worker.action": "applyFileViewSourceUpdateFact",
                    "agentstudio.bridge.worker.lane": "file_view",
                    "agentstudio.bridge.worker.task_kind": "store_action",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 2,
                    "agentstudio.bridge.worker.patch_count": 2,
                    "agentstudio.bridge.worker.source_epoch": 12,
                    "agentstudio.bridge.worker.touched_key_count": 4,
                ]
            )
        )

        #expect(validator.validate(terminalStoreActionSample) == .accepted)
        #expect(validator.validate(sourceResetStoreActionSample) == .accepted)
    }

    @Test
    func validatorRejectsUnsafeCommWorkerTaskTelemetry() {
        let validator = BridgeTelemetryEventValidator(
            scopeGate: BridgeTelemetryScopeGate(enabledScopes: [.web])
        )
        let unknownCommandSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "hot",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.command": "openRawPath",
                    "agentstudio.bridge.worker.lane": "selected",
                    "agentstudio.bridge.worker.task_kind": "message_handler",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 2,
                    "agentstudio.bridge.worker.queue_wait_ms": 4,
                ]
            )
        )
        let unknownAttributeSample = sampleWithWebAttributes(
            WebSampleProps(
                name: "performance.bridge.worker.task",
                phase: "worker_task",
                plane: "data",
                priority: "hot",
                slice: "worker_task",
                transport: "worker",
                extraStrings: [
                    "agentstudio.bridge.result": "success",
                    "agentstudio.bridge.worker.command": "select",
                    "agentstudio.bridge.worker.lane": "selected",
                    "agentstudio.bridge.worker.raw_payload": "selection_payload",
                    "agentstudio.bridge.worker.task_kind": "message_handler",
                ],
                extraNumbers: [
                    "agentstudio.bridge.worker.handler_duration_ms": 2,
                    "agentstudio.bridge.worker.queue_wait_ms": 4,
                ]
            )
        )

        #expect(validator.validate(unknownCommandSample) == .dropped(.unsafeAttribute))
        #expect(validator.validate(unknownAttributeSample) == .dropped(.unsafeAttribute))
    }
}
