import Foundation

extension BridgeTelemetryBatchValidator {
    static func attributesMatchEventContract(_ sample: BridgeTelemetrySample) -> Bool {
        guard let contract = BridgeTelemetryEventContract(sample: sample) else {
            return false
        }

        if let webContractResult = browserWebContractMatches(name: sample.name, contract: contract) {
            return webContractResult
        }
        if let treeContractResult = treeContractMatches(name: sample.name, contract: contract) {
            return treeContractResult
        }
        return auxiliaryContractMatches(name: sample.name, contract: contract) ?? false
    }

    private static func browserWebContractMatches(
        name: String,
        contract: BridgeTelemetryEventContract
    ) -> Bool? {
        switch name {
        case "performance.bridge.web.code_view_item_materialize":
            codeViewItemMaterializeContractMatches(contract)
        case "performance.bridge.web.content_fetch":
            contentFetchContractMatches(contract)
        case "performance.bridge.web.file_open_ready":
            fileOpenReadyContractMatches(contract)
        case "performance.bridge.web.visible_demand_settled":
            visibleDemandSettledContractMatches(contract)
        case "performance.bridge.web.first_render":
            firstRenderContractMatches(contract)
        case "performance.bridge.web.intake_apply":
            packageApplyContractMatches(contract)
        case "performance.bridge.web.push_apply":
            packageApplyContractMatches(contract)
        case "performance.bridge.web.projection_input_build",
            "performance.bridge.web.projection_store_apply",
            "performance.bridge.web.projection_total":
            projectionCoordinatorContractMatches(contract)
        case "performance.bridge.web.intake_frame":
            intakeFrameContractMatches(contract)
        case "performance.bridge.web.review_ready",
            "performance.bridge.web.review_metadata_apply",
            "performance.bridge.web.selection_commit",
            "performance.bridge.web.selected_content_ready":
            reviewStartupContractMatches(contract)
        case "performance.bridge.web.review_content_demand":
            reviewContentDemandContractMatches(contract)
        case "performance.bridge.web.selected_content_dropped":
            selectedContentDroppedContractMatches(contract)
        case "performance.bridge.web.selected_content_painted":
            selectedContentPaintedContractMatches(contract)
        case "performance.bridge.web.rpc_send":
            rpcSendContractMatches(contract)
        case "performance.bridge.web.telemetry_drop":
            telemetryDropContractMatches(contract)
        case "performance.bridge.web.worktree_file_intake_reject":
            worktreeFileIntakeRejectContractMatches(contract)
        default:
            nil
        }
    }

    private static func treeContractMatches(name: String, contract: BridgeTelemetryEventContract) -> Bool? {
        switch name {
        case "performance.bridge.markdown.render_queue":
            markdownRenderQueueContractMatches(contract)
        case "performance.bridge.markdown.render":
            markdownRenderContractMatches(contract)
        case "performance.bridge.markdown.fallback":
            markdownFallbackContractMatches(contract)
        case "performance.bridge.trees.projection_build":
            projectionBuildContractMatches(contract)
        case "performance.bridge.trees.prepare_input":
            prepareInputContractMatches(contract)
        case "performance.bridge.trees.scroll_visible_demand":
            scrollVisibleDemandContractMatches(contract)
        case "performance.bridge.trees.click_to_row_highlight":
            clickToRowHighlightContractMatches(contract)
        case "performance.bridge.trees.hover_to_render":
            hoverToRenderContractMatches(contract)
        case "performance.bridge.trees.scroll_frame_gap":
            scrollFrameGapContractMatches(contract)
        case "performance.bridge.trees.anchor_restore":
            anchorRestoreContractMatches(contract)
        case "performance.bridge.trees.scroll_to_path":
            scrollToPathContractMatches(contract)
        case "performance.bridge.trees.visible_ids_capture":
            visibleIdsCaptureContractMatches(contract)
        case "performance.bridge.trees.mode_switch":
            modeSwitchContractMatches(contract)
        case "performance.bridge.trees.search_filter":
            searchFilterContractMatches(contract)
        default:
            nil
        }
    }

    private static func contentFetchContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let contentResourceFetchExpectation = BridgeTelemetryEventExpectation(
            phase: "fetch",
            plane: .data,
            priority: .hot,
            slice: .contentFetch,
            transport: "content",
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.content.correlation_mode",
                    "agentstudio.bridge.content.role",
                ],
                booleanKeys: [
                    "agentstudio.bridge.header_missing",
                    "agentstudio.bridge.header_supported",
                ]
            )
        )
        let demandContentFetchExpectation = BridgeTelemetryEventExpectation(
            phase: "fetch",
            plane: .data,
            priority: .hot,
            slice: .contentFetch,
            transport: "content",
            attributeKeys: .init(
                additionalStringKeys: [
                    "agentstudio.bridge.content.correlation_mode",
                    "agentstudio.bridge.content.interest",
                    "agentstudio.bridge.content.role",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.result_reason",
                ],
                booleanKeys: [
                    "agentstudio.bridge.header_missing",
                    "agentstudio.bridge.header_supported",
                ]
            )
        )
        return contract.matches(contentResourceFetchExpectation)
            || contract.matches(demandContentFetchExpectation)
            || worktreeFileContentFetchContractMatches(contract)
    }

    private static func firstRenderContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.phase == "render"
            && contract.plane == .data
            && contract.priority == .hot
            && firstRenderSliceIsBrowserRenderable(contract.slice, transport: contract.transport)
            && contract.hasOnlyCommonKeys()
    }

    private static func packageApplyContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let transportMatches: Bool =
            if contract.transport == "push" {
                pushSliceIsBrowserReceivable(contract.slice)
            } else if contract.transport == "intake" {
                intakePackageApplySliceIsBrowserReceivable(contract.slice)
            } else {
                false
            }
        return contract.phase == "apply"
            && contract.plane == planeForBrowserPushSlice(contract.slice)
            && contract.priority == priorityForBrowserPushSlice(contract.slice)
            && transportMatches
            && contract.hasOnlyCommonKeys()
    }

    private static func intakeFrameContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.phase == "intake"
            && contract.plane == planeForBrowserPushSlice(contract.slice)
            && contract.priority == priorityForBrowserPushSlice(contract.slice)
            && intakeSliceIsBrowserReceivable(contract.slice)
            && contract.transport == "intake"
            && contract.stringKeys
                == requiredStringAttributeKeys.union([
                    "agentstudio.bridge.intake.frame_kind",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.result_reason",
                ])
            && contract.numericKeys == [
                "agentstudio.bridge.intake.generation",
                "agentstudio.bridge.intake.sequence",
            ]
            && contract.booleanKeys.isEmpty
    }

    private static func rpcSendContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "send",
                plane: .control,
                priority: .warm,
                slice: .reviewRPC,
                transport: "rpc",
                additionalStringKeys: ["agentstudio.bridge.rpc.method_class"]
            )
        )
    }

    private static func telemetryDropContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let browserDropMatches = contract.matches(
            .init(
                phase: "dropped",
                plane: .observability,
                priority: .bestEffort,
                slice: .telemetryDrop,
                transport: "scheme",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.telemetry.drop_reason",
                        "agentstudio.bridge.telemetry.event_name",
                        "agentstudio.bridge.telemetry.lane",
                        "agentstudio.bridge.telemetry.result",
                    ],
                    numericKeys: ["agentstudio.bridge.telemetry.dropped_count"]
                )
            )
        )
        let legacyBrowserDropMatches = contract.matches(
            .init(
                phase: "dropped",
                plane: .observability,
                priority: .bestEffort,
                slice: .telemetryDrop,
                transport: "rpc",
                attributeKeys: .init(
                    additionalStringKeys: ["agentstudio.bridge.telemetry.drop_reason"],
                    numericKeys: ["agentstudio.bridge.telemetry.dropped_count"]
                )
            )
        )
        let validatorDropDetailMatches = contract.matches(
            .init(
                phase: "dropped",
                plane: .observability,
                priority: .bestEffort,
                slice: .telemetryDrop,
                transport: "rpc",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.telemetry.drop_reason",
                        "agentstudio.bridge.telemetry.first_rejected_event",
                    ],
                    numericKeys: ["agentstudio.bridge.telemetry.dropped_count"]
                )
            )
        )
        return browserDropMatches || legacyBrowserDropMatches || validatorDropDetailMatches
    }

    private static func markdownRenderQueueContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "markdown_queue",
                plane: .data,
                priority: .warm,
                slice: .markdownPreview,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                ]
            )
        )
    }

    private static func markdownRenderContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let expectedStringKeys = requiredStringAttributeKeys.union([
            "agentstudio.bridge.content_bytes_bucket",
            "agentstudio.bridge.result",
            "agentstudio.bridge.worker.lane",
        ])
        return contract.phase == "markdown_render"
            && contract.plane == .data
            && contract.priority == .warm
            && contract.slice == .markdownPreview
            && contract.transport == "worker"
            && contract.stringKeys == expectedStringKeys
            && (contract.numericKeys.isEmpty
                || contract.numericKeys == [
                    "agentstudio.bridge.markdown.input_bytes",
                    "agentstudio.bridge.markdown.output_bytes",
                ])
            && contract.booleanKeys.isEmpty
    }

    private static func markdownFallbackContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "markdown_decision",
                plane: .data,
                priority: .warm,
                slice: .markdownPreview,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.markdown.fallback_reason",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                ]
            )
        )
    }

    private static func reviewStartupContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        if contract.phase == "review_metadata_apply" {
            return reviewMetadataApplyContractMatches(contract)
        }
        if contract.phase == "review_ready" {
            return reviewReadyContractMatches(contract)
        }

        let expectedNumericKeys: Set<String> =
            switch contract.phase {
            case "review_ready":
                ["agentstudio.bridge.review.item_count"]
            case "selected_content_ready":
                ["agentstudio.bridge.content.resource_count"]
            default:
                []
            }

        return contract.matches(
            .init(
                phase: contract.phase,
                plane: .data,
                priority: reviewStartupPriority(for: contract.phase),
                slice: reviewStartupSlice(for: contract.phase),
                transport: reviewStartupTransport(for: contract.phase),
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.result_reason",
                    ],
                    numericKeys: expectedNumericKeys
                )
            )
        )
    }

    private static func reviewMetadataApplyContractMatches(
        _ contract: BridgeTelemetryEventContract
    ) -> Bool {
        let carryForwardNumericKeys: Set<String> = [
            "agentstudio.bridge.review.metadata_carry_forward.unverified_keep.count",
            "agentstudio.bridge.review.metadata_carry_forward.verified_drop.count",
            "agentstudio.bridge.review.metadata_carry_forward.verified_keep.count",
        ]
        let itemCountNumericKeys: Set<String> = [
            "agentstudio.bridge.review.item_count"
        ]
        let snapshotSuccessNumericKeys = carryForwardNumericKeys.union([
            "agentstudio.bridge.review.item_count"
        ])
        let allowedNumericKeySets: Set<Set<String>> = [
            [],
            carryForwardNumericKeys,
            itemCountNumericKeys,
            snapshotSuccessNumericKeys,
        ]

        guard allowedNumericKeySets.contains(contract.numericKeys) else {
            return false
        }

        return contract.matches(
            .init(
                phase: "review_metadata_apply",
                plane: .data,
                priority: .hot,
                slice: .reviewMetadata,
                transport: "intake",
                attributeKeys: .init(
                    additionalStringKeys: [
                        "agentstudio.bridge.result",
                        "agentstudio.bridge.result_reason",
                    ],
                    numericKeys: contract.numericKeys
                )
            )
        )
    }

    private static func reviewReadyContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let routeMatches =
            switch (contract.slice, contract.transport) {
            case (.reviewProjection, "intake"),
                (.reviewMetadata, "intake"),
                (.reviewDelta, "intake"),
                (.reviewInvalidation, "intake"),
                (.reviewReset, "intake"):
                true
            default:
                false
            }

        return contract.phase == "review_ready"
            && contract.plane == .data
            && contract.priority == .hot
            && routeMatches
            && contract.stringKeys
                == requiredStringAttributeKeys.union([
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.result_reason",
                ])
            && contract.numericKeys == ["agentstudio.bridge.review.item_count"]
            && contract.booleanKeys.isEmpty
    }

    private static func reviewStartupSlice(for phase: String) -> BridgeTelemetrySlice {
        switch phase {
        case "selection_commit":
            .reviewProjection
        case "selected_content_ready":
            .contentFetch
        default:
            .reviewMetadata
        }
    }

    private static func reviewStartupTransport(for phase: String) -> String {
        switch phase {
        case "review_metadata_apply":
            "intake"
        case "selection_commit":
            "worker"
        default:
            "content"
        }
    }

    private static func reviewStartupPriority(for phase: String) -> BridgeTelemetryPriority {
        switch phase {
        case "selection_commit":
            .warm
        default:
            .hot
        }
    }

    private static func projectionBuildContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "projection_build",
                plane: .data,
                priority: .warm,
                slice: .reviewProjection,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.fixture_class",
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.projection.kind",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.tree_path_count_bucket",
                    "agentstudio.bridge.worker.lane",
                ]
            )
        )
    }

    private static func projectionCoordinatorContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        switch contract.phase {
        case "projection_input_build",
            "projection_store_apply",
            "projection_total":
            contract.matches(
                .init(
                    phase: contract.phase,
                    plane: .data,
                    priority: .warm,
                    slice: .reviewProjection,
                    transport: "worker",
                    attributeKeys: .init(
                        additionalStringKeys: [
                            "agentstudio.bridge.result",
                            "agentstudio.bridge.worker.lane",
                        ],
                        numericKeys: ["agentstudio.bridge.review.item_count"]
                    )
                )
            )
        default:
            false
        }
    }

    private static func prepareInputContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        let reviewTreePrepareInputMatches = contract.matches(
            .init(
                phase: "prepare_input",
                plane: .data,
                priority: .warm,
                slice: .treePrepareInput,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.fixture_class",
                    "agentstudio.bridge.projection.kind",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.tree_path_count_bucket",
                ]
            )
        )
        let worktreeFileTreePrepareInputStringKeys = requiredStringAttributeKeys.union([
            "agentstudio.bridge.fixture_class",
            "agentstudio.bridge.projection.kind",
            "agentstudio.bridge.result",
            "agentstudio.bridge.tree_path_count_bucket",
        ])
        let worktreeFileTreePrepareInputMatches =
            (contract.phase == "worktree_file_frame_apply" || contract.phase == "worktree_file_projection")
            && contract.plane == .data
            && contract.priority == .warm
            && contract.slice == .treePrepareInput
            && contract.transport == "worker"
            && contract.stringKeys == worktreeFileTreePrepareInputStringKeys
            && contract.numericKeys == [
                "agentstudio.bridge.worktree_file.tree.current_row.count",
                "agentstudio.bridge.worktree_file.tree.descriptor.count",
                "agentstudio.bridge.worktree_file.tree.incoming_frame.count",
                "agentstudio.bridge.worktree_file.tree.window.row.count",
            ]
            && contract.booleanKeys.isEmpty
        return reviewTreePrepareInputMatches || worktreeFileTreePrepareInputMatches
    }

    private static func modeSwitchContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "mode_switch",
                plane: .control,
                priority: .warm,
                slice: .reviewProjection,
                transport: "swift",
                additionalStringKeys: [
                    "agentstudio.bridge.projection.kind",
                    "agentstudio.bridge.result",
                ]
            )
        )
    }

    private static func clickToRowHighlightContractMatches(
        _ contract: BridgeTelemetryEventContract
    ) -> Bool {
        contract.matches(
            treeInstrumentationExpectation(
                phase: "click_to_row_highlight",
                additionalStringKeys: [
                    "agentstudio.bridge.input.source",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.viewer",
                ],
                numericKeys: ["agentstudio.bridge.visible_item.count"],
                booleanKeys: [
                    "agentstudio.bridge.already_selected",
                    "agentstudio.bridge.scroll.active",
                ]
            )
        )
    }

    private static func hoverToRenderContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            treeInstrumentationExpectation(
                phase: "hover_to_render",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.viewer",
                ],
                numericKeys: ["agentstudio.bridge.visible_item.count"],
                booleanKeys: ["agentstudio.bridge.row_mounted"]
            )
        )
    }

    private static func scrollFrameGapContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            treeInstrumentationExpectation(
                phase: "scroll_frame_gap",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.viewer",
                ],
                numericKeys: [
                    "agentstudio.bridge.scroll.frame_gap.max_ms",
                    "agentstudio.bridge.scroll.frame_gap.over_16ms.count",
                    "agentstudio.bridge.scroll.frame_gap.over_33ms.count",
                    "agentstudio.bridge.scroll.frame_gap.over_50ms.count",
                    "agentstudio.bridge.scroll.frame_gap.p95_ms",
                    "agentstudio.bridge.visible_publisher.skipped.count",
                    "agentstudio.bridge.visible_row.count",
                ]
            )
        )
    }

    private static func anchorRestoreContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            treeInstrumentationExpectation(
                phase: "anchor_restore",
                additionalStringKeys: [
                    "agentstudio.bridge.anchor_restore.phase",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.viewer",
                ],
                numericKeys: [
                    "agentstudio.bridge.anchor_restore.call.count",
                    "agentstudio.bridge.anchor_restore.direct_scroll_top_write.count",
                    "agentstudio.bridge.anchor_restore.synthetic_scroll.count",
                ]
            )
        )
    }

    private static func scrollToPathContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            treeInstrumentationExpectation(
                phase: "scroll_to_path",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.scroll.offset",
                    "agentstudio.bridge.scroll.reason",
                    "agentstudio.bridge.viewer",
                ],
                booleanKeys: ["agentstudio.bridge.focus"]
            )
        )
    }

    private static func visibleIdsCaptureContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            treeInstrumentationExpectation(
                phase: "visible_ids_capture",
                additionalStringKeys: [
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.viewer",
                ],
                numericKeys: [
                    "agentstudio.bridge.visible_descriptor.count",
                    "agentstudio.bridge.visible_item.count",
                    "agentstudio.bridge.visible_row.count",
                ]
            )
        )
    }

    private static func treeInstrumentationExpectation(
        phase: String,
        additionalStringKeys: Set<String>,
        numericKeys: Set<String> = [],
        booleanKeys: Set<String> = []
    ) -> BridgeTelemetryEventExpectation {
        .init(
            phase: phase,
            plane: .data,
            priority: .hot,
            slice: .treePrepareInput,
            transport: "worker",
            attributeKeys: .init(
                additionalStringKeys: additionalStringKeys,
                numericKeys: numericKeys,
                booleanKeys: booleanKeys
            )
        )
    }

    private static func searchFilterContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "search_filter",
                plane: .data,
                priority: .warm,
                slice: .reviewProjection,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.fixture_class",
                    "agentstudio.bridge.query_class",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.tree_path_count_bucket",
                ]
            )
        )
    }

    private static func pushSliceIsBrowserRenderable(_ slice: BridgeTelemetrySlice) -> Bool {
        switch slice {
        case .diffStatus,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles:
            true
        case .reviewMetadata,
            .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .connectionHealth,
            .commandAcks,
            .reviewRPC,
            .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .markdownPreview,
            .shikiHighlight,
            .workerTask,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }

    private static func firstRenderSliceIsBrowserRenderable(
        _ slice: BridgeTelemetrySlice,
        transport: String
    ) -> Bool {
        switch slice {
        case .reviewMetadata,
            .reviewDelta:
            transport == "intake"
        default:
            transport == "push" && pushSliceIsBrowserRenderable(slice)
        }
    }

    private static func intakePackageApplySliceIsBrowserReceivable(
        _ slice: BridgeTelemetrySlice
    ) -> Bool {
        switch slice {
        case .reviewMetadata,
            .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .reviewProjection:
            true
        case .diffStatus,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .connectionHealth,
            .commandAcks,
            .reviewRPC,
            .contentFetch,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .markdownPreview,
            .shikiHighlight,
            .workerTask,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }

    private static func priorityForBrowserPushSlice(_ slice: BridgeTelemetrySlice) -> BridgeTelemetryPriority {
        switch slice {
        case .diffStatus, .connectionHealth:
            .hot
        case .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .reviewThreads,
            .reviewViewedFiles,
            .commandAcks,
            .reviewProjection:
            .warm
        case .reviewMetadata, .diffFiles:
            .cold
        case .reviewRPC:
            .warm
        case .contentFetch,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .markdownPreview,
            .shikiHighlight,
            .workerTask,
            .unknown:
            .cold
        case .telemetryBatch, .telemetryIngest, .telemetryDrop:
            .bestEffort
        }
    }

    private static func planeForBrowserPushSlice(_ slice: BridgeTelemetrySlice) -> BridgeTelemetryPlane {
        switch slice {
        case .connectionHealth, .commandAcks, .reviewRPC:
            .control
        case .telemetryBatch, .telemetryIngest, .telemetryDrop:
            .observability
        case .diffStatus,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .reviewMetadata,
            .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .markdownPreview,
            .shikiHighlight,
            .workerTask,
            .unknown:
            .data
        }
    }

    private static func pushSliceIsBrowserReceivable(_ slice: BridgeTelemetrySlice) -> Bool {
        switch slice {
        case .diffStatus,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .connectionHealth,
            .commandAcks:
            true
        case .reviewMetadata,
            .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .reviewRPC,
            .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .markdownPreview,
            .shikiHighlight,
            .workerTask,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }

    private static func intakeSliceIsBrowserReceivable(_ slice: BridgeTelemetrySlice) -> Bool {
        switch slice {
        case .reviewMetadata,
            .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .reviewProjection:
            true
        case .diffStatus,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .connectionHealth,
            .commandAcks,
            .reviewRPC,
            .contentFetch,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .markdownPreview,
            .shikiHighlight,
            .workerTask,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }
}
