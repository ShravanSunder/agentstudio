import Foundation
import os.log

private let bridgePushTransportLogger = Logger(subsystem: "com.agentstudio", category: "BridgePushTransport")

struct BridgePushDedupEntry {
    let epoch: Int
    let payload: Data
}

private actor BridgeDeliveryResult {
    private var didDeliver = false

    var delivered: Bool {
        didDeliver
    }

    func setDelivered() {
        didDeliver = true
    }

    func setFailed() {
        didDeliver = false
    }
}

@MainActor
extension BridgePaneController: PushTransport {
    func pushJSON(
        metadata: BridgePushEnvelopeMetadata,
        json: Data
    ) async {
        // Content guard — skip identical pushes to same store+op+slice within the same epoch.
        // Keyed by store+op+slice (not epoch) so the cache is bounded by declared push slices.
        // Epoch is stored in the entry value — a new epoch always goes through even with
        // identical bytes, because React needs to see epoch transitions for tracking.
        // Including op and slice ensures different semantic lanes do not suppress one another.
        let dedupKey = "\(metadata.store.rawValue):\(metadata.op.rawValue):\(metadata.slice.rawValue)"
        if let previous = lastPushed[dedupKey],
            previous.epoch == metadata.epoch,
            previous.payload == json
        {
            return
        }

        // Phase 1: encode the push envelope (encoding bugs are NOT connection errors).
        let envelopeString: String
        let traceContext = makePushTraceContext(for: metadata.store)
        do {
            envelopeString = try BridgePushEnvelopeEncoder().encode(
                metadata: metadata,
                payload: json,
                pushId: UUID(),
                traceContext: traceContext
            )
        } catch {
            bridgePushTransportLogger.error(
                "[Bridge] envelope encoding bug store=\(metadata.store.rawValue) rev=\(metadata.revision): \(error)"
            )
            return
        }

        // Transport the envelope to React; transport failures are connection errors.
        // WebKit accepts overlapping callJavaScript requests but does not reliably
        // deliver every page event when several push/intake plans fire at bridge-ready.
        let previousDelivery = bridgeDeliveryTail
        let delivery = Task { @MainActor [weak self] in
            await previousDelivery?.value
            guard let self else { return }
            await self.deliverPushEnvelope(
                metadata: metadata,
                json: json,
                dedupKey: dedupKey,
                envelopeString: envelopeString,
                traceContext: traceContext
            )
        }
        bridgeDeliveryTail = delivery
        await delivery.value
    }

    func deliverIntakeFrame(_ frame: PreEncodedIntakeFrame) async -> Bool {
        let result = BridgeDeliveryResult()
        let previousDelivery = bridgeDeliveryTail
        let delivery = Task { @MainActor [weak self] in
            await previousDelivery?.value
            guard let self else { return }
            do {
                try await self.intakeFrameSink(self.page, frame)
                await result.setDelivered()
            } catch {
                await result.setFailed()
                self.paneState.connection.setHealth(.error)
            }
        }
        bridgeDeliveryTail = delivery
        await delivery.value
        return await result.delivered
    }

    private func deliverPushEnvelope(
        metadata: BridgePushEnvelopeMetadata,
        json: Data,
        dedupKey: String,
        envelopeString: String,
        traceContext: BridgeTraceContext?
    ) async {
        let pushStart = ContinuousClock.now
        do {
            try await pushEnvelopeSink(page, envelopeString, pushNonce)
            lastPushed[dedupKey] = BridgePushDedupEntry(epoch: metadata.epoch, payload: json)
            await recordPackagePushTelemetry(
                slice: metadata.slice,
                traceContext: traceContext,
                durationMilliseconds: AgentStudioPerformanceTraceRecorder.milliseconds(
                    from: pushStart.duration(to: ContinuousClock.now)
                )
            )
            bridgePushTransportLogger.debug(
                "[BridgePaneController] pushJSON store=\(metadata.store.rawValue) op=\(metadata.op.rawValue) level=\(String(describing: metadata.level)) rev=\(metadata.revision) epoch=\(metadata.epoch) bytes=\(json.count)"
            )
        } catch {
            bridgePushTransportLogger.warning(
                "[Bridge] JS transport failed store=\(metadata.store.rawValue) rev=\(metadata.revision) epoch=\(metadata.epoch): \(error)"
            )
            paneState.connection.setHealth(.error)
        }
    }

    func makeRootTraceContext() -> BridgeTraceContext? {
        guard telemetryScopeGate.isEnabled else {
            return nil
        }
        return traceContextFactory.makeRootContext()
    }

    func makeChildTraceContext(parent: BridgeTraceContext?) -> BridgeTraceContext? {
        guard telemetryScopeGate.isEnabled else {
            return nil
        }
        return traceContextFactory.makeChildContext(parent: parent)
    }

    private func makePushTraceContext(for store: StoreKey) -> BridgeTraceContext? {
        guard telemetryScopeGate.isEnabled else {
            return nil
        }
        guard store == .diff else {
            return traceContextFactory.makeRootContext()
        }
        return traceContextFactory.makeChildContext(parent: lastReviewPackageTraceContext)
    }

    func recordSwiftTelemetry(
        name: String,
        phase: String,
        priorityHint: PushLevel,
        traceContext: BridgeTraceContext?,
        stringAttributes additionalStringAttributes: [String: String] = [:],
        durationMilliseconds: Double?
    ) async {
        guard let telemetryRecorder else {
            return
        }
        var stringAttributes = [
            "agentstudio.bridge.phase": phase,
            "agentstudio.bridge.plane": nativeTelemetryPlane(
                for: name
            ).rawValue,
            "agentstudio.bridge.priority": nativeTelemetryPriority(
                for: name,
                fallback: priorityHint
            ).rawValue,
            "agentstudio.bridge.slice": nativeTelemetrySlice(for: name).rawValue,
            "agentstudio.bridge.transport": "swift",
        ]
        stringAttributes.merge(additionalStringAttributes) { _, newValue in newValue }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .swift,
                name: name,
                durationMilliseconds: durationMilliseconds,
                traceContext: traceContext,
                stringAttributes: stringAttributes,
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func recordPackagePushTelemetry(
        slice: BridgeTelemetrySlice,
        traceContext: BridgeTraceContext?,
        durationMilliseconds: Double
    ) async {
        guard let telemetryRecorder else {
            return
        }
        await telemetryRecorder.record(
            sample: BridgeTelemetrySample(
                scope: .webKit,
                name: "performance.bridge.webkit.push_envelope",
                durationMilliseconds: durationMilliseconds,
                traceContext: traceContext,
                stringAttributes: [
                    "agentstudio.bridge.phase": "transport",
                    "agentstudio.bridge.plane": pushTelemetryPlane(for: slice).rawValue,
                    "agentstudio.bridge.priority": pushTelemetryPriority(for: slice).rawValue,
                    "agentstudio.bridge.slice": slice.rawValue,
                    "agentstudio.bridge.transport": "push",
                ],
                numericAttributes: [:],
                booleanAttributes: [:]
            ),
            receivedAtUnixNano: UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        )
    }

    private func nativeTelemetryPlane(for name: String) -> BridgeTelemetryPlane {
        switch name {
        case "performance.bridge.swift.telemetry_ingest":
            .observability
        default:
            .data
        }
    }

    private func nativeTelemetryPriority(
        for name: String,
        fallback: PushLevel
    ) -> BridgeTelemetryPriority {
        switch name {
        case "performance.bridge.swift.content_load":
            .hot
        case "performance.bridge.swift.delta_build":
            .warm
        case "performance.bridge.swift.package_build",
            "performance.bridge.swift.content_register",
            "performance.bridge.swift.review_metadata_window_batch":
            .cold
        case "performance.bridge.swift.telemetry_ingest":
            .bestEffort
        default:
            switch fallback {
            case .hot:
                .hot
            case .warm:
                .warm
            case .cold:
                .cold
            }
        }
    }

    private func nativeTelemetrySlice(for name: String) -> BridgeTelemetrySlice {
        switch name {
        case "performance.bridge.swift.package_build",
            "performance.bridge.swift.content_register",
            "performance.bridge.swift.review_metadata_window_batch":
            .reviewMetadata
        case "performance.bridge.swift.delta_build":
            .reviewDelta
        case "performance.bridge.swift.content_load":
            .contentFetch
        case "performance.bridge.swift.telemetry_ingest":
            .telemetryIngest
        default:
            .unknown
        }
    }

    private func pushTelemetryPlane(for slice: BridgeTelemetrySlice) -> BridgeTelemetryPlane {
        switch slice {
        case .connectionHealth, .commandAcks, .reviewRPC:
            .control
        case .telemetryBatch, .telemetryDrop, .telemetryIngest:
            .observability
        default:
            .data
        }
    }

    private func pushTelemetryPriority(for slice: BridgeTelemetrySlice) -> BridgeTelemetryPriority {
        switch slice {
        case .diffStatus, .connectionHealth:
            .hot
        case .codeViewItem,
            .codeViewScroll,
            .codeViewVirtualRange,
            .shikiHighlight:
            .hot
        case .reviewDelta,
            .reviewInvalidation,
            .reviewReset,
            .reviewThreads,
            .reviewViewedFiles,
            .commandAcks,
            .reviewRPC,
            .reviewProjection,
            .treePrepareInput,
            .markdownPreview,
            .workerTask:
            .warm
        case .reviewMetadata, .diffFiles, .contentFetch, .unknown:
            .cold
        case .telemetryBatch, .telemetryDrop, .telemetryIngest:
            .bestEffort
        }
    }
}
