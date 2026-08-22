import Foundation

extension BridgeTelemetryWireSchema {
    static func auxiliaryContractMatches(name: String, contract: EventContract) -> Bool? {
        switch name {
        case "performance.bridge.web.annotation_lifecycle":
            webAnnotationLifecycleContractMatches(contract)
        case "performance.bridge.web.operation_lifecycle":
            webOperationLifecycleContractMatches(contract)
        case "performance.bridge.swift.annotation_lifecycle":
            annotationLifecycleContractMatches(contract)
        case "performance.bridge.swift.operation_lifecycle":
            operationLifecycleContractMatches(contract)
        case "performance.bridge.swift.review_refresh_lifecycle":
            swiftReviewRefreshLifecycleContractMatches(contract)
        case "performance.bridge.web.review_refresh_lifecycle":
            webReviewRefreshLifecycleContractMatches(contract)
        case "performance.bridge.viewer.content_queue":
            contentQueueContractMatches(contract)
        case "performance.bridge.viewer.content_cache":
            contentCacheContractMatches(contract)
        case "performance.bridge.viewer.time_to_first_interaction":
            timeToFirstInteractionContractMatches(contract)
        case "performance.bridge.pierre.item_update":
            itemUpdateContractMatches(contract)
        case "performance.bridge.pierre.scroll_target":
            scrollTargetContractMatches(contract)
        case "performance.bridge.pierre.virtualized_range":
            virtualizedRangeContractMatches(contract)
        case "performance.bridge.web.pane_presentation":
            panePresentationContractMatches(contract)
        case "performance.bridge.shiki.highlight":
            shikiHighlightContractMatches(contract)
        case "performance.bridge.worker.task":
            workerTaskContractMatches(contract)
        default:
            nil
        }
    }

    private static func webAnnotationLifecycleContractMatches(_ contract: EventContract) -> Bool {
        let phases: Set<String> = [
            "refresh_reserved",
            "refresh_operation_terminal",
            "annotation_invalidation_received",
            "annotation_paint_started",
            "annotation_paint_terminal",
            "content_transfer_started",
            "content_transfer_terminal",
            "descriptor_claim_started",
            "descriptor_claim_terminal",
            "main_thread_install_started",
            "main_thread_install_terminal",
            "metadata_delivery_started",
            "metadata_delivery_terminal",
            "metadata_delivery_terminal",
            "native_annotation_work_started",
            "native_annotation_work_terminal",
            "projection_store_started",
            "projection_content_transfer_terminal",
            "projection_convergence_started",
            "projection_convergence_terminal",
            "projection_query_started",
            "projection_query_terminal",
            "projection_store_terminal",
            "projection_validation_started",
            "projection_validation_terminal",
            "worker_application_started",
            "worker_application_terminal",
        ]
        guard phases.contains(contract.phase) else { return false }
        return contract.matches(
            .init(
                phase: contract.phase,
                plane: .data,
                priority: .hot,
                slice: .reviewProjection,
                transport: contract.transport,
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.operation.id",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.viewer",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.source.generation",
                        "agentstudio.bridge.stage.attempt",
                    ]
                )
            )
        ) && (contract.transport == "worker" || contract.transport == "local")
    }

    private static func annotationLifecycleContractMatches(_ contract: EventContract) -> Bool {
        let phases: Set<String> = [
            "annotation_invalidation_admitted",
            "annotation_notification_delivery_terminal",
            "content_transfer_started",
            "content_transfer_terminal",
            "metadata_delivery_started",
            "native_annotation_work_started",
            "native_annotation_work_terminal",
            "projection_content_transfer_started",
            "projection_content_transfer_terminal",
            "projection_query_started",
            "projection_query_terminal",
        ]
        guard phases.contains(contract.phase) else { return false }
        return contract.matches(
            .init(
                phase: contract.phase,
                plane: .data,
                priority: .hot,
                slice: .reviewProjection,
                transport: "swift",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.operation.id",
                        "agentstudio.bridge.protocol",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.viewer",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.source.generation",
                        "agentstudio.bridge.stage.attempt",
                    ]
                )
            )
        )
    }

    private static func operationLifecycleContractMatches(_ contract: EventContract) -> Bool {
        let phases: Set<String> = [
            "file_prepare_started",
            "file_prepare_terminal",
            "review_prepare_started",
            "review_prepare_terminal",
            "refresh_commit_started",
            "refresh_commit_terminal",
            "metadata_enqueue_started",
            "metadata_enqueue_terminal",
            "metadata_delivery_started",
            "metadata_delivery_terminal",
        ]
        guard phases.contains(contract.phase),
            contract.slice == .treePrepareInput || contract.slice == .reviewMetadata
        else { return false }
        return contract.matches(
            .init(
                phase: contract.phase,
                plane: .data,
                priority: .hot,
                slice: contract.slice,
                transport: "swift",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.operation.id",
                        "agentstudio.bridge.protocol",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.viewer",
                    ],
                    numericKeys: ["agentstudio.bridge.stage.attempt"]
                )
            )
        )
    }

    private static func webOperationLifecycleContractMatches(_ contract: EventContract) -> Bool {
        let phases: Set<String> = [
            "worker_application_started",
            "worker_application_terminal",
            "panel_chrome_publish_started",
            "panel_chrome_publish_terminal",
            "file_content_operation_started",
            "file_content_operation_terminal",
            "file_descriptor_wait_started",
            "file_descriptor_wait_terminal",
            "content_operation_started",
            "content_operation_terminal",
            "main_thread_install_started",
            "main_thread_install_terminal",
            "render_operation_started",
            "render_operation_terminal",
            "paint_fulfillment_started",
            "paint_fulfillment_terminal",
        ]
        guard phases.contains(contract.phase) else { return false }
        return contract.matches(
            .init(
                phase: contract.phase,
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "worker",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.operation.id",
                        "agentstudio.bridge.protocol",
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.viewer",
                    ],
                    numericKeys: ["agentstudio.bridge.stage.attempt"]
                )
            )
        )
    }

    private static func swiftReviewRefreshLifecycleContractMatches(
        _ contract: EventContract
    ) -> Bool {
        let commonStringKeys: Set<String> = [
            "agentstudio.bridge.result",
            "agentstudio.bridge.result_reason",
        ]
        switch contract.phase {
        case "review_refresh_classified":
            let stringKeys = commonStringKeys.union([
                "agentstudio.bridge.review.refresh.presentation_class"
            ])
            let commonNumericKeys: Set<String> = [
                "agentstudio.bridge.review.generation",
                "agentstudio.bridge.review.refresh.affected_stable_file.count",
            ]
            let exactNumericKeys = commonNumericKeys.union([
                "agentstudio.bridge.review.refresh.imported_commit.count",
                "agentstudio.bridge.review.refresh.affected_file.count",
                "agentstudio.bridge.review.refresh.changed_line.count",
            ])
            return contract.matches(
                .init(
                    phase: contract.phase,
                    plane: .control,
                    priority: .hot,
                    slice: .reviewMetadata,
                    transport: "swift",
                    attributeKeys: .init(
                        additionalStringKeys: stringKeys,
                        numericKeys: commonNumericKeys
                    )
                )
            )
                || contract.matches(
                    .init(
                        phase: contract.phase,
                        plane: .control,
                        priority: .hot,
                        slice: .reviewMetadata,
                        transport: "swift",
                        attributeKeys: .init(
                            additionalStringKeys: stringKeys,
                            numericKeys: exactNumericKeys
                        )
                    )
                )
        case "review_refresh_source_cleanup_terminal":
            return contract.matches(
                .init(
                    phase: contract.phase,
                    plane: .control,
                    priority: .hot,
                    slice: .reviewMetadata,
                    transport: "swift",
                    attributeKeys: .init(
                        additionalStringKeys: commonStringKeys,
                        numericKeys: [
                            "agentstudio.bridge.review.refresh.retained_publication.count",
                            "agentstudio.bridge.review.refresh.source_lease.count",
                        ]
                    )
                )
            )
        default:
            return false
        }
    }

    private static func webReviewRefreshLifecycleContractMatches(
        _ contract: EventContract
    ) -> Bool {
        let candidateStringKeys: Set<String> = [
            "agentstudio.bridge.result",
            "agentstudio.bridge.result_reason",
            "agentstudio.bridge.review.refresh.presentation_class",
            "agentstudio.bridge.review.refresh.promotion_reason",
        ]
        let candidateNumericKeys: Set<String> = [
            "agentstudio.bridge.review.generation",
            "agentstudio.bridge.review.refresh.affected_stable_file.count",
        ]
        switch contract.phase {
        case "review_refresh_candidate_ready",
            "review_refresh_candidate_held",
            "review_refresh_candidate_superseded",
            "review_refresh_receipt_failed":
            return contract.matches(
                .init(
                    phase: contract.phase,
                    plane: .control,
                    priority: .hot,
                    slice: .reviewMetadata,
                    transport: "worker",
                    attributeKeys: .init(
                        additionalStringKeys: candidateStringKeys,
                        numericKeys: candidateNumericKeys
                    )
                )
            )
        case "review_refresh_install_requested", "review_refresh_install_terminal":
            return contract.matches(
                .init(
                    phase: contract.phase,
                    plane: .control,
                    priority: .hot,
                    slice: .reviewMetadata,
                    transport: "worker",
                    attributeKeys: .init(
                        additionalStringKeys: candidateStringKeys.union([
                            "agentstudio.bridge.review.refresh.install_trigger"
                        ]),
                        numericKeys: candidateNumericKeys
                    )
                )
            )
        case "review_refresh_cleanup_terminal":
            return contract.matches(
                .init(
                    phase: contract.phase,
                    plane: .control,
                    priority: .hot,
                    slice: .reviewMetadata,
                    transport: "worker",
                    attributeKeys: .init(
                        additionalStringKeys: [
                            "agentstudio.bridge.result",
                            "agentstudio.bridge.result_reason",
                        ],
                        numericKeys: [
                            "agentstudio.bridge.review.refresh.active_bank.count",
                            "agentstudio.bridge.review.refresh.candidate_bank.count",
                        ]
                    )
                )
            )
        default:
            return false
        }
    }

    private static func contentQueueContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "content_queue",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                additionalStringKeys: [
                    "agentstudio.bridge.content.interest",
                    "agentstudio.bridge.content.priority",
                    "agentstudio.bridge.content.role",
                    "agentstudio.bridge.queue.depth_bucket",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func contentCacheContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "content_cache",
                plane: .data,
                priority: .hot,
                slice: .contentFetch,
                transport: "content",
                additionalStringKeys: [
                    "agentstudio.bridge.cache.result",
                    "agentstudio.bridge.content.role",
                    "agentstudio.bridge.content_bytes_bucket",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func itemUpdateContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "item_update",
                plane: .data,
                priority: .hot,
                slice: .codeViewItem,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.item_update.kind",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func scrollTargetContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "scroll_target",
                plane: .control,
                priority: .hot,
                slice: .codeViewScroll,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.scroll_target.kind",
                ]
            )
        )
    }

    private static func virtualizedRangeContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "virtualized_range",
                plane: .data,
                priority: .hot,
                slice: .codeViewVirtualRange,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.diff_row_count_bucket",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.visible_row_bucket",
                ]
            )
        )
    }

    private static func shikiHighlightContractMatches(_ contract: EventContract) -> Bool {
        contract.matches(
            .init(
                phase: "highlight",
                plane: .data,
                priority: .hot,
                slice: .shikiHighlight,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.content_bytes_bucket",
                    "agentstudio.bridge.language_class",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                ]
            )
        )
    }

    private static func workerTaskContractMatches(_ contract: EventContract) -> Bool {
        legacyWorkerTaskContractMatches(contract)
            || commWorkerMessageHandlerContractMatches(contract)
            || commWorkerProductControlContractMatches(contract)
            || commWorkerContentPreparationContractMatches(contract)
            || commWorkerStoreActionContractMatches(contract)
    }

    private static func panePresentationContractMatches(_ contract: EventContract) -> Bool {
        let commonKeys = PanePresentationContractKeys(
            stringKeys: [
                "agentstudio.bridge.comparison.attempt.status",
                "agentstudio.bridge.presentation.disposition",
                "agentstudio.bridge.result",
            ],
            numericKeys: ["agentstudio.bridge.presentation.revision"],
            booleanKeys: ["agentstudio.bridge.refreshing.review"]
        )
        return panePresentationApplyContractMatches(contract, commonKeys: commonKeys)
            || panePresentationPublicationContractMatches(contract, commonKeys: commonKeys)
            || panePresentationApplicationContractMatches(contract, commonKeys: commonKeys)
            || comparisonPaneRenderedContractMatches(contract)
    }

    private static func panePresentationApplyContractMatches(
        _ contract: EventContract,
        commonKeys: PanePresentationContractKeys
    ) -> Bool {
        let applyExpectation = EventExpectation(
            phase: "pane_presentation_applied",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "worker",
            attributeKeys: .init(
                additionalStringKeys: commonKeys.stringKeys,
                numericKeys: commonKeys.numericKeys,
                booleanKeys: commonKeys.booleanKeys
            )
        )
        let applyWithGenerationExpectation = EventExpectation(
            phase: "pane_presentation_applied",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "worker",
            attributeKeys: .init(
                additionalStringKeys: commonKeys.stringKeys,
                numericKeys: commonKeys.numericKeys.union([
                    "agentstudio.bridge.review.generation"
                ]),
                booleanKeys: commonKeys.booleanKeys
            )
        )
        return contract.matches(applyExpectation)
            || contract.matches(applyWithGenerationExpectation)
    }

    private static func panePresentationPublicationContractMatches(
        _ contract: EventContract,
        commonKeys: PanePresentationContractKeys
    ) -> Bool {
        let publicationStringKeys = commonKeys.stringKeys.union([
            "agentstudio.bridge.panel.operation",
            "agentstudio.bridge.viewer",
        ])
        let publicationNumericKeys = commonKeys.numericKeys.union([
            "agentstudio.bridge.presentation.publication_sequence",
            "agentstudio.bridge.worker.derivation_epoch",
        ])
        let publicationExpectation = EventExpectation(
            phase: "panel_chrome_published",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "worker",
            attributeKeys: .init(
                additionalStringKeys: publicationStringKeys,
                numericKeys: publicationNumericKeys,
                booleanKeys: commonKeys.booleanKeys
            )
        )
        let publicationWithGenerationExpectation = EventExpectation(
            phase: "panel_chrome_published",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "worker",
            attributeKeys: .init(
                additionalStringKeys: publicationStringKeys,
                numericKeys: publicationNumericKeys.union([
                    "agentstudio.bridge.review.generation"
                ]),
                booleanKeys: commonKeys.booleanKeys
            )
        )
        return contract.matches(publicationExpectation)
            || contract.matches(publicationWithGenerationExpectation)
    }

    private static func panePresentationApplicationContractMatches(
        _ contract: EventContract,
        commonKeys: PanePresentationContractKeys
    ) -> Bool {
        let applicationStringKeys = commonKeys.stringKeys.union([
            "agentstudio.bridge.panel.operation",
            "agentstudio.bridge.viewer",
        ])
        let applicationNumericKeys = commonKeys.numericKeys.union([
            "agentstudio.bridge.presentation.publication_sequence",
            "agentstudio.bridge.worker.derivation_epoch",
        ]).subtracting([
            "agentstudio.bridge.presentation.revision"
        ])
        let applicationExpectation = EventExpectation(
            phase: "panel_chrome_applied",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "local",
            attributeKeys: .init(
                additionalStringKeys: applicationStringKeys,
                numericKeys: applicationNumericKeys,
                booleanKeys: []
            )
        )
        let applicationWithGenerationExpectation = EventExpectation(
            phase: "panel_chrome_applied",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "local",
            attributeKeys: .init(
                additionalStringKeys: applicationStringKeys,
                numericKeys: applicationNumericKeys.union([
                    "agentstudio.bridge.review.generation"
                ]),
                booleanKeys: []
            )
        )
        return contract.matches(applicationExpectation)
            || contract.matches(applicationWithGenerationExpectation)
    }

    private static func comparisonPaneRenderedContractMatches(_ contract: EventContract) -> Bool {
        let renderedExpectation = EventExpectation(
            phase: "comparison_pane_rendered",
            plane: .control,
            priority: .hot,
            slice: .reviewMetadata,
            transport: "local",
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.comparison.attempt.status",
                    "agentstudio.bridge.comparison.package_match",
                    "agentstudio.bridge.comparison.pane_state",
                    "agentstudio.bridge.presentation.disposition",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.viewer",
                ],
                numericKeys: [],
                booleanKeys: []
            )
        )
        return contract.matches(renderedExpectation)
    }

    private struct PanePresentationContractKeys {
        let stringKeys: Set<String>
        let numericKeys: Set<String>
        let booleanKeys: Set<String>
    }

    private static func legacyWorkerTaskContractMatches(_ contract: EventContract) -> Bool {
        workerTaskContractMatches(
            contract,
            priority: .warm,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
                ]
            )
        )
    }

    private static func commWorkerMessageHandlerContractMatches(
        _ contract: EventContract
    ) -> Bool {
        let additionalStringKeys: Set<String> = [
            "agentstudio.bridge.result",
            "agentstudio.bridge.worker.command",
            "agentstudio.bridge.worker.lane",
            "agentstudio.bridge.worker.task_kind",
        ]
        let numericKeys: Set<String> = [
            "agentstudio.bridge.worker.handler_duration_ms",
            "agentstudio.bridge.worker.queue_wait_ms",
        ]
        return workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: additionalStringKeys,
                numericKeys: numericKeys
            )
        )
            || workerTaskContractMatches(
                contract,
                attributeKeys: .init(
                    additionalStringKeys: additionalStringKeys,
                    numericKeys: numericKeys,
                    booleanKeys: [
                        "agentstudio.bridge.worker.file_metadata_selected_path_resolved"
                    ]
                )
            )
    }

    private static func commWorkerContentPreparationContractMatches(
        _ contract: EventContract
    ) -> Bool {
        workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.payload_class",
                    "agentstudio.bridge.worker.task_kind",
                    "agentstudio.bridge.worker.work_kind",
                ],
                numericKeys: [
                    "agentstudio.bridge.worker.handler_duration_ms",
                    "agentstudio.bridge.worker.queue_wait_ms",
                    "agentstudio.bridge.worker.source_epoch",
                ]
            )
        )
    }

    private static func commWorkerProductControlContractMatches(
        _ contract: EventContract
    ) -> Bool {
        workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.command",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
                ],
                numericKeys: ["agentstudio.bridge.worker.handler_duration_ms"]
            )
        )
    }

    private static func commWorkerStoreActionContractMatches(
        _ contract: EventContract
    ) -> Bool {
        workerTaskContractMatches(
            contract,
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.action",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
                ],
                numericKeys: [
                    "agentstudio.bridge.worker.handler_duration_ms",
                    "agentstudio.bridge.worker.patch_count",
                    "agentstudio.bridge.worker.touched_key_count",
                ]
            )
        )
            || workerTaskContractMatches(
                contract,
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.worker.action",
                        "agentstudio.bridge.worker.lane",
                        "agentstudio.bridge.worker.task_kind",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.worker.handler_duration_ms",
                        "agentstudio.bridge.worker.patch_count",
                        "agentstudio.bridge.worker.source_epoch",
                        "agentstudio.bridge.worker.touched_key_count",
                    ]
                )
            )
            || workerTaskContractMatches(
                contract,
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.result_reason",
                        "agentstudio.bridge.worker.action",
                        "agentstudio.bridge.worker.lane",
                        "agentstudio.bridge.worker.task_kind",
                    ],
                    numericKeys: [
                        "agentstudio.bridge.worker.handler_duration_ms",
                        "agentstudio.bridge.worker.patch_count",
                        "agentstudio.bridge.worker.source_epoch",
                        "agentstudio.bridge.worker.touched_key_count",
                    ]
                )
            )
    }

    private static func workerTaskContractMatches(
        _ contract: EventContract,
        attributeKeys: EventAttributeKeys
    ) -> Bool {
        workerTaskContractMatches(contract, priority: .hot, attributeKeys: attributeKeys)
            || workerTaskContractMatches(contract, priority: .warm, attributeKeys: attributeKeys)
    }

    private static func workerTaskContractMatches(
        _ contract: EventContract,
        priority: BridgeTelemetryPriority,
        attributeKeys: EventAttributeKeys
    ) -> Bool {
        contract.matches(
            .init(
                phase: "worker_task",
                plane: .data,
                priority: priority,
                slice: .workerTask,
                transport: "worker",
                attributeKeys: attributeKeys
            )
        )
    }
}
