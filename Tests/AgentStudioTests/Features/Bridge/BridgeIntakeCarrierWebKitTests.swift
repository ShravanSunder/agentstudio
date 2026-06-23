import Foundation
import Testing
import WebKit

@testable import AgentStudio

extension WebKitSerializedTests {
    @MainActor
    @Suite(.serialized)
    final class BridgeIntakeCarrierWebKitTests {
        private let bridgeContentWorld = WKContentWorld.world(name: "agentStudioBridge")

        init() {
            installTestAtomRegistryIfNeeded()
        }

        @Test
        func test_intakeCarrierWebKitCoversLifecycleErrorsAndByteBounds() async throws {
            let controller = BridgePaneController(
                paneId: UUIDv7.generate(),
                state: BridgePaneState(panelKind: .diffViewer, source: nil)
            )
            defer { controller.teardown() }

            try await WebPageTestHarness.withManagedPage(controller.page) { page in
                try await loadPageAndInstallProbe(page, controller: controller)

                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .snapshot, generation: 1, sequence: 0))
                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .delta, generation: 1, sequence: 2))
                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .reset, generation: 2, sequence: 0))
                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .snapshot, generation: 2, sequence: 1))
                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .close, generation: 1, sequence: 3))
                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .close, generation: 2, sequence: 2))
                try await dispatchIntakeFrame(page, frameJSON: makeFrame(kind: .delta, generation: 2, sequence: 3))

                let didObserveClosedDrop = await waitUntil(timeout: .seconds(5)) {
                    await self.probeDropReasons(page).contains("closed")
                }
                let acceptedKinds = await probeAcceptedKinds(page)
                let dropReasons = await probeDropReasons(page)
                let lifecycleProbeState = await probeDescription(page)

                #expect(didObserveClosedDrop, "Expected post-close frame to be rejected: \(lifecycleProbeState)")
                #expect(acceptedKinds == ["snapshot", "reset", "snapshot", "close"])
                #expect(dropReasons.contains("sequence_gap"))
                #expect(dropReasons.contains("generation_mismatch"))
                #expect(dropReasons.contains("closed"))

                try await resetProbe(page, maxFrameBytes: 1024)
                try await dispatchIntakeFrame(
                    page,
                    frameJSON: makeFrame(
                        kind: .error,
                        generation: 1,
                        sequence: 0,
                        message: "backend stream failed"
                    )
                )

                let didObserveError = await waitUntil(timeout: .seconds(5)) {
                    await self.probeAcceptedMessages(page).contains("backend stream failed")
                }
                let errorProbeState = await probeDescription(page)

                #expect(didObserveError, "Expected page carrier to receive error message: \(errorProbeState)")
                #expect(await probeAcceptedKinds(page) == ["error"])
                #expect(await probeDropReasons(page).isEmpty)

                try await resetProbe(page, maxFrameBytes: 150)
                let frameJSON = try makeFrame(
                    kind: .snapshot,
                    generation: 1,
                    sequence: 0,
                    payload: Data(#"{"value":"\#(String(repeating: "é", count: 48))"}"#.utf8)
                )

                try await dispatchIntakeFrame(page, frameJSON: frameJSON)

                let didObserveFrameLimit = await waitUntil(timeout: .seconds(5)) {
                    await self.probeDropReasons(page).contains("frame_too_large")
                }
                let byteLengths = await probeDroppedByteLengths(page)
                let byteLimitProbeState = await probeDescription(page)

                #expect(didObserveFrameLimit, "Expected UTF-8 byte cap to reject frame: \(byteLimitProbeState)")
                #expect(byteLengths.contains { $0 > 150 })
                #expect(await probeAcceptedKinds(page).isEmpty)
            }
        }

        private func loadPageAndInstallProbe(
            _ page: WebPage,
            controller: BridgePaneController,
            maxFrameBytes: Int = 1024
        ) async throws {
            controller.loadApp()
            try await waitForPageLoad(page)
            let didCompleteBridgeReadyHandshake = await waitUntil {
                controller.isBridgeReady
            }
            try #require(didCompleteBridgeReadyHandshake, "Bridge app did not complete ready handshake")
            try await installIntakeProbe(page, maxFrameBytes: maxFrameBytes)
            let didCapturePushNonce = await waitUntil {
                await self.probePushNonce(page) == controller.pushNonce
            }
            try #require(didCapturePushNonce, "Intake probe did not receive bridge push nonce")
        }

        private func installIntakeProbe(_ page: WebPage, maxFrameBytes: Int) async throws {
            _ = try await page.callJavaScript(
                bridgeIntakeCarrierProbeScript(maxFrameBytes: maxFrameBytes),
                contentWorld: .page
            )
        }

        private func resetProbe(_ page: WebPage, maxFrameBytes: Int) async throws {
            _ = try await page.callJavaScript(
                """
                window.__bridgeIntakeProbe.reset(\(maxFrameBytes));
                """,
                contentWorld: .page
            )
        }

        private func dispatchIntakeFrame(_ page: WebPage, frameJSON: String) async throws {
            let frameLiteral = try javaScriptStringLiteral(frameJSON)
            _ = try await page.callJavaScript(
                """
                window.__bridgeInternal.applyIntakeFrameJSON(\(frameLiteral));
                """,
                contentWorld: bridgeContentWorld
            )
        }

        private func makeFrame(
            kind: BridgeIntakeFrameKind,
            generation: Int,
            sequence: Int,
            message: String? = nil,
            payload: Data = Data(#"{"value":true}"#.utf8)
        ) throws -> String {
            try BridgePushEnvelopeEncoder().encodeIntakeFrame(
                metadata: BridgeIntakeFrameMetadata(
                    kind: kind,
                    streamId: "stream-1",
                    generation: generation,
                    sequence: sequence,
                    message: message
                ),
                payload: payload,
                traceContext: nil
            )
        }

        private func waitForPageLoad(_ page: WebPage, timeout: Duration = .seconds(5)) async throws {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if !page.isLoading { break }
                await Task.yield()
            }
            try #require(!page.isLoading, "Page did not finish loading within \(timeout)")
            await settleAsyncCallbacks(turns: 40)
        }

        private func waitUntil(
            timeout: Duration = .seconds(2),
            _ condition: @escaping () async -> Bool
        ) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if await condition() {
                    return true
                }
                await Task.yield()
            }
            return await condition()
        }

        private func settleAsyncCallbacks(turns: Int) async {
            for _ in 0..<turns {
                await Task.yield()
            }
        }

        private func probePushNonce(_ page: WebPage) async -> String? {
            await evaluateProbeString(page, expression: "window.__bridgeIntakeProbe?.pushNonce ?? null")
        }

        private func probeAcceptedKinds(_ page: WebPage) async -> [String] {
            await evaluateProbeStringArray(
                page,
                expression: "(window.__bridgeIntakeProbe?.accepted ?? []).map((entry) => entry.kind)"
            )
        }

        private func probeAcceptedMessages(_ page: WebPage) async -> [String] {
            await evaluateProbeStringArray(
                page,
                expression: "(window.__bridgeIntakeProbe?.accepted ?? []).map((entry) => entry.message).filter(Boolean)"
            )
        }

        private func probeDropReasons(_ page: WebPage) async -> [String] {
            await evaluateProbeStringArray(
                page,
                expression: "(window.__bridgeIntakeProbe?.drops ?? []).map((entry) => entry.reason)"
            )
        }

        private func probeDroppedByteLengths(_ page: WebPage) async -> [Int] {
            do {
                let result = try await page.callJavaScript(
                    """
                    return JSON.stringify((window.__bridgeIntakeProbe?.drops ?? [])
                      .map((entry) => entry.byteLength)
                      .filter((value) => typeof value === 'number'))
                    """,
                    contentWorld: .page
                )
                guard let json = result as? String,
                    let data = json.data(using: .utf8)
                else {
                    return []
                }
                return (try? JSONDecoder().decode([Int].self, from: data)) ?? []
            } catch {
                return []
            }
        }

        private func probeDescription(_ page: WebPage) async -> String {
            do {
                let result = try await page.callJavaScript(
                    """
                    return JSON.stringify(window.__bridgeIntakeProbe ?? null)
                    """,
                    contentWorld: .page
                )
                return (result as? String) ?? String(describing: result)
            } catch {
                return String(describing: error)
            }
        }

        private func evaluateProbeString(_ page: WebPage, expression: String) async -> String? {
            do {
                let result = try await page.callJavaScript("return \(expression)", contentWorld: .page)
                return result as? String
            } catch {
                return nil
            }
        }

        private func evaluateProbeStringArray(_ page: WebPage, expression: String) async -> [String] {
            do {
                let result = try await page.callJavaScript(
                    "return JSON.stringify(\(expression))",
                    contentWorld: .page
                )
                guard let json = result as? String,
                    let data = json.data(using: .utf8)
                else {
                    return []
                }
                return (try? JSONDecoder().decode([String].self, from: data)) ?? []
            } catch {
                return []
            }
        }

        private func javaScriptStringLiteral(_ value: String) throws -> String {
            let data = try JSONEncoder().encode(value)
            return try #require(String(data: data, encoding: .utf8))
        }
    }
}

private func bridgeIntakeCarrierProbeScript(maxFrameBytes: Int) -> String {
    bridgeIntakeCarrierProbeScriptTemplate.replacingOccurrences(
        of: "__MAX_FRAME_BYTES__",
        with: String(maxFrameBytes)
    )
}

private let bridgeIntakeCarrierProbeScriptTemplate = """
    (() => {
      const maxFrameBytes = __MAX_FRAME_BYTES__;
      const makeState = () => ({
        streamId: 'stream-1',
        generation: 1,
        nextSequence: 0,
        resetRequired: false,
        closed: false
      });
      const probe = {
        pushNonce: null,
        accepted: [],
        drops: [],
        maxFrameBytes: maxFrameBytes,
        state: makeState()
      };
      const textEncoder = new TextEncoder();
      const drop = (reason, extra) => {
        probe.drops.push(Object.assign({ reason: reason }, extra || {}));
      };
      const accept = (frame) => {
        probe.accepted.push({
          kind: frame.kind,
          generation: frame.generation,
          sequence: frame.sequence,
          message: frame.message || null
        });
      };
      const receiveFrame = (frame) => {
        if (frame.streamId !== probe.state.streamId) {
          drop('stream_mismatch');
          return;
        }
        if (probe.state.closed) {
          drop('closed');
          return;
        }
        if (frame.generation < probe.state.generation) {
          drop('generation_mismatch');
          return;
        }
        if (frame.generation > probe.state.generation) {
          if (frame.kind !== 'reset') {
            drop('generation_mismatch');
            return;
          }
          probe.state.generation = frame.generation;
          probe.state.nextSequence = frame.sequence;
          probe.state.resetRequired = false;
        }
        if (probe.state.resetRequired && frame.kind !== 'reset') {
          drop('reset_required');
          return;
        }
        if (frame.sequence < probe.state.nextSequence) {
          drop('stale_sequence');
          return;
        }
        if (frame.sequence > probe.state.nextSequence) {
          probe.state.resetRequired = true;
          drop('sequence_gap');
          return;
        }
        accept(frame);
        probe.state.nextSequence = frame.sequence + 1;
        if (frame.kind === 'close') {
          probe.state.closed = true;
        }
      };
      document.addEventListener('__bridge_handshake', (event) => {
        probe.pushNonce = event.detail?.pushNonce || null;
      });
      document.addEventListener('__bridge_intake_json', (event) => {
        const detail = event.detail;
        if (!detail || detail.nonce !== probe.pushNonce) {
          drop('carrier_nonce_mismatch');
          return;
        }
        if (typeof detail.json !== 'string') {
          drop('frame_decode_failed');
          return;
        }
        const byteLength = textEncoder.encode(detail.json).byteLength;
        if (byteLength > probe.maxFrameBytes) {
          drop('frame_too_large', { byteLength: byteLength, jsonLength: detail.json.length });
          return;
        }
        let frame = null;
        try {
          frame = JSON.parse(detail.json);
        } catch (error) {
          drop('frame_decode_failed');
          return;
        }
        if (
          typeof frame.streamId !== 'string' ||
          typeof frame.generation !== 'number' ||
          typeof frame.sequence !== 'number' ||
          typeof frame.kind !== 'string'
        ) {
          drop('frame_decode_failed');
          return;
        }
        if (frame.kind === 'error' && typeof frame.message !== 'string') {
          drop('frame_decode_failed');
          return;
        }
        receiveFrame(frame);
      });
      probe.reset = (nextMaxFrameBytes) => {
        probe.accepted = [];
        probe.drops = [];
        probe.maxFrameBytes = nextMaxFrameBytes;
        probe.state = makeState();
      };
      window.__bridgeIntakeProbe = probe;
      document.dispatchEvent(new CustomEvent('__bridge_handshake_request'));
    })();
    """
