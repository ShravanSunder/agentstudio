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

    private struct BridgeTelemetryEventExpectation: Sendable {
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

    private struct BridgeTelemetryEventAttributeKeys: Sendable {
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

    private struct BridgeTelemetryEventContract: Sendable {
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

        switch sample.name {
        case "performance.bridge.web.content_fetch":
            return contentFetchContractMatches(contract)
        case "performance.bridge.web.first_render":
            return firstRenderContractMatches(contract)
        case "performance.bridge.web.package_apply":
            return packageApplyContractMatches(contract)
        case "performance.bridge.web.rpc_send":
            return rpcSendContractMatches(contract)
        case "performance.bridge.web.telemetry_drop":
            return telemetryDropContractMatches(contract)
        case "performance.bridge.trees.projection_build":
            return projectionBuildContractMatches(contract)
        case "performance.bridge.trees.prepare_input":
            return prepareInputContractMatches(contract)
        case "performance.bridge.trees.mode_switch":
            return modeSwitchContractMatches(contract)
        case "performance.bridge.trees.search_filter":
            return searchFilterContractMatches(contract)
        case "performance.bridge.viewer.content_queue":
            return contentQueueContractMatches(contract)
        case "performance.bridge.viewer.content_cache":
            return contentCacheContractMatches(contract)
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
            return false
        }
    }

    private static func contentFetchContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
            .init(
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
        )
    }

    private static func firstRenderContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.phase == "render"
            && contract.plane == .data
            && contract.priority == .hot
            && pushSliceIsBrowserRenderable(contract.slice)
            && contract.transport == "push"
            && contract.hasOnlyCommonKeys()
    }

    private static func packageApplyContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.phase == "apply"
            && contract.plane == planeForBrowserPushSlice(contract.slice)
            && contract.priority == priorityForBrowserPushSlice(contract.slice)
            && pushSliceIsBrowserReceivable(contract.slice)
            && contract.transport == "push"
            && contract.hasOnlyCommonKeys()
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

    private static func prepareInputContractMatches(_ contract: BridgeTelemetryEventContract) -> Bool {
        contract.matches(
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
            .diffPackageMetadata,
            .diffPackageDelta,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles:
            true
        case .connectionHealth,
            .commandAcks,
            .reviewRPC,
            .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
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
        case .diffPackageDelta, .reviewThreads, .reviewViewedFiles, .commandAcks:
            .warm
        case .diffPackageMetadata, .diffFiles:
            .cold
        case .reviewRPC:
            .warm
        case .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
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
            .diffPackageMetadata,
            .diffPackageDelta,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .shikiHighlight,
            .workerTask,
            .unknown:
            .data
        }
    }

    private static func pushSliceIsBrowserReceivable(_ slice: BridgeTelemetrySlice) -> Bool {
        switch slice {
        case .diffStatus,
            .diffPackageMetadata,
            .diffPackageDelta,
            .diffFiles,
            .reviewThreads,
            .reviewViewedFiles,
            .connectionHealth,
            .commandAcks:
            true
        case .reviewRPC,
            .contentFetch,
            .reviewProjection,
            .treePrepareInput,
            .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .shikiHighlight,
            .workerTask,
            .telemetryBatch,
            .telemetryIngest,
            .telemetryDrop,
            .unknown:
            false
        }
    }

    private static let requiredStringAttributeKeys: Set<String> = [
        "agentstudio.bridge.phase",
        "agentstudio.bridge.plane",
        "agentstudio.bridge.priority",
        "agentstudio.bridge.slice",
        "agentstudio.bridge.transport",
    ]

    private static let allowedEventNames: Set<String> = [
        "performance.bridge.web.content_fetch",
        "performance.bridge.web.first_render",
        "performance.bridge.web.package_apply",
        "performance.bridge.web.rpc_send",
        "performance.bridge.web.telemetry_drop",
        "performance.bridge.trees.projection_build",
        "performance.bridge.trees.prepare_input",
        "performance.bridge.trees.mode_switch",
        "performance.bridge.trees.search_filter",
        "performance.bridge.viewer.content_queue",
        "performance.bridge.viewer.content_cache",
        "performance.bridge.pierre.item_update",
        "performance.bridge.pierre.scroll_target",
        "performance.bridge.pierre.virtualized_range",
        "performance.bridge.shiki.highlight",
        "performance.bridge.worker.task",
    ]

    private static let allowedStringValuesByAttributeKey: [String: Set<String>] = [
        "agentstudio.bridge.cache.result": [
            "cache_hit",
            "provider_load",
            "in_flight_coalesced",
            "rejected",
        ],
        "agentstudio.bridge.content.correlation_mode": [
            "summary",
            "traceparent",
        ],
        "agentstudio.bridge.content.role": [
            "base",
            "head",
            "diff",
            "file",
            "unknown",
        ],
        "agentstudio.bridge.content.priority": [
            "prefetch",
            "selected",
            "visible",
        ],
        "agentstudio.bridge.content_bytes_bucket": [
            "empty",
            "small",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.diff_row_count_bucket": [
            "small",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.fixture_class": [
            "smoke",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.generation.relation": [
            "current",
            "stale",
            "unknown",
        ],
        "agentstudio.bridge.phase": [
            "accepted",
            "apply",
            "content_register",
            "delta_build",
            "dispatch",
            "dropped",
            "error",
            "fetch",
            "package_apply",
            "package_build",
            "render",
            "send",
            "success",
            "transport",
            "content_queue",
            "content_cache",
            "highlight",
            "item_update",
            "mode_switch",
            "prepare_input",
            "projection_build",
            "scroll_target",
            "search_filter",
            "virtualized_range",
            "worker_task",
        ],
        "agentstudio.bridge.plane": Set(
            BridgeTelemetryPlane.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.priority": Set(
            BridgeTelemetryPriority.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.rpc.method_class": [
            "other",
            "review",
            "telemetry",
        ],
        "agentstudio.bridge.item_count_bucket": [
            "empty",
            "small",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.item_update.kind": [
            "add",
            "hydrate",
            "replace",
        ],
        "agentstudio.bridge.language_class": [
            "config",
            "markdown",
            "other",
            "swift",
            "text",
            "typescript",
        ],
        "agentstudio.bridge.projection.kind": [
            "all_files",
            "changed_files",
            "current_change_set",
            "custom",
            "docs_and_plans",
            "guided_review",
            "source",
            "tests",
        ],
        "agentstudio.bridge.query_class": [
            "empty",
            "extension",
            "path",
            "symbol",
        ],
        "agentstudio.bridge.queue.depth_bucket": [
            "empty",
            "small",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.result": [
            "dropped",
            "error",
            "success",
        ],
        "agentstudio.bridge.scroll_target.kind": [
            "item",
            "line",
            "position",
            "range",
        ],
        "agentstudio.bridge.slice": Set(
            BridgeTelemetrySlice.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.telemetry.drop_reason": Set(
            BridgeTelemetryDropReason.allCases.map(\.rawValue)
        ),
        "agentstudio.bridge.test.scenario": [
            "package_apply_content_fetch_v1"
        ],
        "agentstudio.bridge.transport": [
            "content",
            "push",
            "rpc",
            "swift",
            "worker",
        ],
        "agentstudio.bridge.tree_path_count_bucket": [
            "empty",
            "small",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.visible_row_bucket": [
            "empty",
            "small",
            "medium",
            "large",
            "huge",
        ],
        "agentstudio.bridge.worker.lane": [
            "none",
            "pierre",
            "projection",
        ],
        "agentstudio.bridge.worker.task_kind": [
            "highlight",
            "pool_init",
            "projection",
        ],
    ]

    private static let allowedNumericAttributeKeys: Set<String> = [
        "agentstudio.bridge.batch.sample_count",
        "agentstudio.bridge.content.byte_size_bucket",
        "agentstudio.bridge.content.line_count_bucket",
        "agentstudio.bridge.telemetry.dropped_count",
    ]

    private static let allowedBooleanAttributeKeys: Set<String> = [
        "agentstudio.bridge.cache_hit",
        "agentstudio.bridge.content.binary",
        "agentstudio.bridge.content.stale",
        "agentstudio.bridge.header_missing",
        "agentstudio.bridge.header_supported",
    ]

    private static func isSafeControlledString(_ value: String) -> Bool {
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
