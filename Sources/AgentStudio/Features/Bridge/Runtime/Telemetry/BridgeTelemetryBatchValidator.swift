import Foundation

enum BridgeTelemetryBatchValidationResult: Equatable, Sendable {
    case accepted(BridgeTelemetryBatch)
    case dropped(BridgeTelemetryDropReason)
}

struct BridgeTelemetryBatchValidator: Sendable {
    private let scopeGate: BridgeTelemetryScopeGate
    private let decoder: JSONDecoder

    init(scopeGate: BridgeTelemetryScopeGate, decoder: JSONDecoder = JSONDecoder()) {
        self.scopeGate = scopeGate
        self.decoder = decoder
    }

    func decodeAndValidate(_ data: Data) -> BridgeTelemetryBatchValidationResult {
        guard data.count <= BridgeTelemetryLimits.maxEncodedBatchBytes else {
            return .dropped(.encodedBatchTooLarge)
        }

        do {
            return try validate(decoder.decode(BridgeTelemetryBatch.self, from: data))
        } catch is BridgeTraceContext.ValidationError {
            return .dropped(.invalidTraceContext)
        } catch {
            return .dropped(.decodingFailed)
        }
    }

    func validate(_ batch: BridgeTelemetryBatch) -> BridgeTelemetryBatchValidationResult {
        guard batch.schemaVersion == 1 else {
            return .dropped(.unsupportedSchemaVersion)
        }
        guard batch.samples.count <= BridgeTelemetryLimits.maxSamplesPerBatch else {
            return .dropped(.tooManySamples)
        }
        guard Self.isSafeControlledString(batch.scenario) else {
            return .dropped(.unsafeAttribute)
        }

        for sample in batch.samples {
            guard sample.scope == .web else {
                return .dropped(.disabledScope)
            }
            guard scopeGate.isEnabled(sample.scope) else {
                return .dropped(.disabledScope)
            }
            guard Self.allowedEventNames.contains(sample.name) else {
                return .dropped(.unsafeEventName)
            }
            if let durationMilliseconds = sample.durationMilliseconds {
                guard durationMilliseconds.isFinite, durationMilliseconds >= 0 else {
                    return .dropped(.invalidDuration)
                }
            }
            guard Self.attributesAreSafe(sample) else {
                return .dropped(.unsafeAttribute)
            }
            guard Self.attributesMatchEventContract(sample) else {
                return .dropped(.unsafeAttribute)
            }
        }

        return .accepted(batch)
    }
}

extension BridgeTelemetryBatchValidator {
    private static func attributesAreSafe(_ sample: BridgeTelemetrySample) -> Bool {
        guard requiredStringAttributeKeys.allSatisfy({ sample.stringAttributes[$0] != nil }) else {
            return false
        }
        for (key, value) in sample.stringAttributes {
            guard allowedStringValuesByAttributeKey[key]?.contains(value) == true else {
                return false
            }
        }
        for (key, value) in sample.numericAttributes {
            guard allowedNumericAttributeKeys.contains(key), value.isFinite else {
                return false
            }
        }
        for key in sample.booleanAttributes.keys {
            guard allowedBooleanAttributeKeys.contains(key) else {
                return false
            }
        }
        return true
    }

    struct BridgeTelemetryEventExpectation: Sendable {
        let phase: String
        let plane: BridgeTelemetryPlane
        let priority: BridgeTelemetryPriority
        let slice: BridgeTelemetrySlice
        let transport: String
        let attributeKeys: BridgeTelemetryEventAttributeKeys

        init(
            phase: String,
            plane: BridgeTelemetryPlane,
            priority: BridgeTelemetryPriority,
            slice: BridgeTelemetrySlice,
            transport: String,
            attributeKeys: BridgeTelemetryEventAttributeKeys = .commonOnly
        ) {
            self.phase = phase
            self.plane = plane
            self.priority = priority
            self.slice = slice
            self.transport = transport
            self.attributeKeys = attributeKeys
        }

        init(
            phase: String,
            plane: BridgeTelemetryPlane,
            priority: BridgeTelemetryPriority,
            slice: BridgeTelemetrySlice,
            transport: String,
            additionalStringKeys: Set<String>
        ) {
            self.init(
                phase: phase,
                plane: plane,
                priority: priority,
                slice: slice,
                transport: transport,
                attributeKeys: .init(additionalStringKeys: additionalStringKeys)
            )
        }
    }

    struct BridgeTelemetryEventAttributeKeys: Sendable {
        static let commonOnly = Self()

        let additionalStringKeys: Set<String>
        let numericKeys: Set<String>
        let booleanKeys: Set<String>

        init(
            additionalStringKeys: Set<String> = [],
            numericKeys: Set<String> = [],
            booleanKeys: Set<String> = []
        ) {
            self.additionalStringKeys = additionalStringKeys
            self.numericKeys = numericKeys
            self.booleanKeys = booleanKeys
        }
    }

    struct BridgeTelemetryEventContract: Sendable {
        let phase: String
        let plane: BridgeTelemetryPlane
        let priority: BridgeTelemetryPriority
        let slice: BridgeTelemetrySlice
        let transport: String
        let stringKeys: Set<String>
        let numericKeys: Set<String>
        let booleanKeys: Set<String>

        init?(sample: BridgeTelemetrySample) {
            guard let phase = sample.stringAttributes["agentstudio.bridge.phase"],
                let planeValue = sample.stringAttributes["agentstudio.bridge.plane"],
                let plane = BridgeTelemetryPlane(rawValue: planeValue),
                let priorityValue = sample.stringAttributes["agentstudio.bridge.priority"],
                let priority = BridgeTelemetryPriority(rawValue: priorityValue),
                let sliceValue = sample.stringAttributes["agentstudio.bridge.slice"],
                let slice = BridgeTelemetrySlice(rawValue: sliceValue),
                let transport = sample.stringAttributes["agentstudio.bridge.transport"]
            else {
                return nil
            }

            self.phase = phase
            self.plane = plane
            self.priority = priority
            self.slice = slice
            self.transport = transport
            stringKeys = Set(sample.stringAttributes.keys)
            numericKeys = Set(sample.numericAttributes.keys)
            booleanKeys = Set(sample.booleanAttributes.keys)
        }

        func matches(_ expectation: BridgeTelemetryEventExpectation) -> Bool {
            let expectedStringKeys = BridgeTelemetryBatchValidator.requiredStringAttributeKeys
                .union(expectation.attributeKeys.additionalStringKeys)
            return phase == expectation.phase
                && plane == expectation.plane
                && priority == expectation.priority
                && slice == expectation.slice
                && transport == expectation.transport
                && stringKeys == expectedStringKeys
                && numericKeys == expectation.attributeKeys.numericKeys
                && booleanKeys == expectation.attributeKeys.booleanKeys
        }

        func hasOnlyCommonKeys() -> Bool {
            stringKeys == BridgeTelemetryBatchValidator.requiredStringAttributeKeys
                && numericKeys.isEmpty
                && booleanKeys.isEmpty
        }
    }

    private static func attributesMatchEventContract(_ sample: BridgeTelemetrySample) -> Bool {
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
            return codeViewItemMaterializeContractMatches(contract)
        case "performance.bridge.web.content_fetch":
            return contentFetchContractMatches(contract)
        case "performance.bridge.web.file_open_ready":
            return fileOpenReadyContractMatches(contract)
        case "performance.bridge.web.visible_demand_settled":
            return visibleDemandSettledContractMatches(contract)
        case "performance.bridge.web.first_render":
            return firstRenderContractMatches(contract)
        case "performance.bridge.web.intake_apply":
            return packageApplyContractMatches(contract)
        case "performance.bridge.web.push_apply":
            return packageApplyContractMatches(contract)
        case "performance.bridge.web.projection_input_build",
            "performance.bridge.web.projection_store_apply",
            "performance.bridge.web.projection_total":
            return projectionCoordinatorContractMatches(contract)
        case "performance.bridge.web.intake_frame":
            return intakeFrameContractMatches(contract)
        case "performance.bridge.web.review_ready",
            "performance.bridge.web.review_metadata_apply",
            "performance.bridge.web.selection_commit",
            "performance.bridge.web.selected_content_ready":
            return reviewStartupContractMatches(contract)
        case "performance.bridge.web.review_content_demand":
            return reviewContentDemandContractMatches(contract)
        case "performance.bridge.web.selected_content_painted":
            return selectedContentPaintedContractMatches(contract)
        case "performance.bridge.web.rpc_send":
            return rpcSendContractMatches(contract)
        case "performance.bridge.web.telemetry_drop":
            return telemetryDropContractMatches(contract)
        case "performance.bridge.web.worktree_file_intake_reject":
            return worktreeFileIntakeRejectContractMatches(contract)
        default:
            return nil
        }
    }

    private static func treeContractMatches(name: String, contract: BridgeTelemetryEventContract) -> Bool? {
        switch name {
        case "performance.bridge.markdown.render_queue":
            return markdownRenderQueueContractMatches(contract)
        case "performance.bridge.markdown.render":
            return markdownRenderContractMatches(contract)
        case "performance.bridge.markdown.fallback":
            return markdownFallbackContractMatches(contract)
        case "performance.bridge.trees.projection_build":
            return projectionBuildContractMatches(contract)
        case "performance.bridge.trees.prepare_input":
            return prepareInputContractMatches(contract)
        case "performance.bridge.trees.scroll_visible_demand":
            return scrollVisibleDemandContractMatches(contract)
        case "performance.bridge.trees.mode_switch":
            return modeSwitchContractMatches(contract)
        case "performance.bridge.trees.search_filter":
            return searchFilterContractMatches(contract)
        default:
            return nil
        }
    }

    private static func auxiliaryContractMatches(name: String, contract: BridgeTelemetryEventContract) -> Bool? {
        switch name {
        case "performance.bridge.viewer.content_queue":
            return contentQueueContractMatches(contract)
        case "performance.bridge.viewer.content_cache":
            return contentCacheContractMatches(contract)
        case "performance.bridge.viewer.time_to_first_interaction":
            return timeToFirstInteractionContractMatches(contract)
        case "performance.bridge.pierre.item_update":
            return itemUpdateContractMatches(contract)
        case "performance.bridge.pierre.scroll_target":
            return scrollTargetContractMatches(contract)
        case "performance.bridge.pierre.virtualized_range":
            return virtualizedRangeContractMatches(contract)
        case "performance.bridge.shiki.highlight":
            return shikiHighlightContractMatches(contract)
        case "performance.bridge.worker.task":
            return workerTaskContractMatches(contract)
        default:
            return nil
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
        contract.matches(
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
        let expectedNumericKeys: Set<String> =
            switch contract.phase {
            case "review_ready":
                ["agentstudio.bridge.review.item_count"]
            case "review_metadata_apply" where contract.numericKeys.contains("agentstudio.bridge.review.item_count"):
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

    private static func contentQueueContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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

    private static func contentCacheContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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

    private static func itemUpdateContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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

    private static func scrollTargetContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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

    private static func virtualizedRangeContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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

    private static func shikiHighlightContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
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

    private static func workerTaskContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
                phase: "worker_task",
                plane: .data,
                priority: .warm,
                slice: .workerTask,
                transport: "worker",
                additionalStringKeys: [
                    "agentstudio.bridge.item_count_bucket",
                    "agentstudio.bridge.result",
                    "agentstudio.bridge.worker.lane",
                    "agentstudio.bridge.worker.task_kind",
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

    static func isSafeControlledString(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
                || scalar == ":"
        }
    }
}
