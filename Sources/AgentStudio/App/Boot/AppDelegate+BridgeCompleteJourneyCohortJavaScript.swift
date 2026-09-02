import Foundation

#if DEBUG
    struct BridgeCompleteJourneyBrowserResult: Decodable {
        let outcome: String
        let failureReason: String?
        let pageApplicationEpochMilliseconds: Double?
        let handshakeWorkerEpochMilliseconds: Double?
        let sourceMetadataEpochMilliseconds: Double?
        let selectionContentEpochMilliseconds: Double?
        let commitPaintEpochMilliseconds: Double?
    }

    extension AppDelegate {
        // The embedded verifier returns synchronously so Swift retains the bounded
        // deadline even when WebKit pauses animation frames. Page-local state owns
        // the two-frame witness across bounded native polls.
        // swiftlint:disable:next function_body_length
        nonisolated static func bridgeCompleteJourneyUsablePaintJavaScript(
            surface: BridgeCompleteJourneySurface
        ) -> String {
            let surfaceLiteral = surface.rawValue
            return """
                const requestedSurface = '\(surfaceLiteral)';
                const probes = globalThis.__bridgeCompleteJourneyUsablePaintProbes ??= {};
                const probe = probes[requestedSurface] ??= {
                  commitPaintEpochMilliseconds: null,
                  frameSequence: 0,
                  frameWitnessScheduled: false,
                  pageApplicationEpochMilliseconds: null,
                  selectionContentEpochMilliseconds: null,
                  sourceMetadataEpochMilliseconds: null,
                };
                const isVisible = (element) => {
                  if (!(element instanceof HTMLElement)) return false;
                  const rectangle = element.getBoundingClientRect();
                  const style = window.getComputedStyle(element);
                  return style.display !== 'none' && style.visibility !== 'hidden'
                    && rectangle.width > 0 && rectangle.height > 0;
                };
                const isEnabledButton = (control) => control instanceof HTMLButtonElement && !control.disabled
                  && control.getAttribute('aria-disabled') !== 'true';
                const inspect = () => {
                  const diagnostic = globalThis.__bridgeReviewSelectionDiagnostic ?? {};
                  const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
                  const host = document.querySelector(
                    `[data-testid="bridge-viewer-mode-host-${requestedSurface}"]`
                  );
                  if (appRoot instanceof HTMLElement
                    && probe.pageApplicationEpochMilliseconds === null
                  ) {
                    probe.pageApplicationEpochMilliseconds = Date.now();
                  }
                  const handshakeTimes = [
                    diagnostic.pageReadyFirstObservedAtEpochMilliseconds,
                    diagnostic.commWorkerSessionReadyFirstObservedAtEpochMilliseconds,
                    diagnostic.nativeBootstrapInstallAcceptedFirstObservedAtEpochMilliseconds,
                  ].filter(Number.isFinite);
                  const handshakeWorkerEpochMilliseconds = handshakeTimes.length > 0
                    ? Math.max(...handshakeTimes) : null;
                  const foundationReady = probe.pageApplicationEpochMilliseconds !== null
                    && handshakeWorkerEpochMilliseconds !== null
                    && appRoot instanceof HTMLElement;
                  const hostReady = foundationReady && host instanceof HTMLElement
                    && host.getAttribute('data-bridge-viewer-mode-active') === 'true'
                    && !host.inert && isVisible(host);
                  if (requestedSurface === 'review') {
                    const shell = document.querySelector('[data-testid="review-viewer-shell"]');
                    const tree = document.querySelector('[data-testid="bridge-review-trees-panel"]');
                    const content = document.querySelector('[data-testid="bridge-code-view-panel"]');
                    const navigationControl = document.querySelector('[data-testid="bridge-viewer-context-file"]');
                    const readingControl = document.querySelector('[data-testid="bridge-review-view-settings-trigger"]');
                    const metadataReady = hostReady && Number(
                      shell?.getAttribute('data-review-metadata-item-count') ?? '0'
                    ) > 0 && (shell?.getAttribute('data-review-metadata-id')?.length ?? 0) > 0
                      && (shell?.getAttribute('data-review-metadata-generation')?.length ?? 0) > 0;
                    const selectionReady = metadataReady
                      && shell?.getAttribute('data-selected-content-state') === 'ready'
                      && Number(content?.getAttribute('data-selected-content-character-count') ?? '0') > 0
                      && diagnostic.latestReviewSelectLifecycleState === 'acked';
                    return {
                      commitReady: selectionReady && isVisible(shell) && isVisible(tree) && isVisible(content)
                        && isEnabledButton(navigationControl) && isEnabledButton(readingControl),
                      diagnostic,
                      handshakeWorkerEpochMilliseconds,
                      metadataReady,
                      pageApplicationEpochMilliseconds: probe.pageApplicationEpochMilliseconds,
                      selectionReady,
                    };
                  }
                  const shell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                  const tree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
                  const content = document.querySelector('[data-testid="bridge-file-viewer-code-canvas"]');
                  const navigationControl = document.querySelector('[data-testid="bridge-viewer-context-review"]');
                  const readingControl = document.querySelector('[data-testid="bridge-file-view-settings-trigger"]');
                  const metadataReady = hostReady && shell?.getAttribute('data-file-display-status') === 'ready'
                    && Number(shell?.getAttribute('data-file-display-item-count') ?? '0') > 0
                    && (shell?.getAttribute('data-file-display-source-id')?.length ?? 0) > 0
                    && (shell?.getAttribute('data-file-display-generation')?.length ?? 0) > 0;
                  const selectionReady = metadataReady
                    && shell?.getAttribute('data-worktree-open-file-state') === 'ready'
                    && (shell?.getAttribute('data-worktree-open-file-path')?.length ?? 0) > 0
                    && Number(shell?.getAttribute('data-file-display-payload-byte-count') ?? '0') > 0
                    && diagnostic.latestFileSelectLifecycleState === 'acked';
                  return {
                    commitReady: selectionReady && isVisible(shell) && isVisible(tree) && isVisible(content)
                      && isEnabledButton(navigationControl) && isEnabledButton(readingControl),
                    diagnostic,
                    handshakeWorkerEpochMilliseconds,
                    metadataReady,
                    pageApplicationEpochMilliseconds: probe.pageApplicationEpochMilliseconds,
                    selectionReady,
                  };
                };
                const state = inspect();
                if (state.metadataReady && probe.sourceMetadataEpochMilliseconds === null) {
                  probe.sourceMetadataEpochMilliseconds = Date.now();
                }
                if (state.selectionReady && probe.selectionContentEpochMilliseconds === null) {
                  probe.selectionContentEpochMilliseconds = Date.now();
                }
                const readyForFrameWitness = state.commitReady
                  && document.visibilityState === 'visible'
                  && document.readyState === 'complete';
                if (!readyForFrameWitness) {
                  probe.frameSequence += 1;
                  probe.frameWitnessScheduled = false;
                  probe.commitPaintEpochMilliseconds = null;
                } else if (probe.commitPaintEpochMilliseconds === null
                  && !probe.frameWitnessScheduled
                ) {
                  probe.frameWitnessScheduled = true;
                  const frameSequence = ++probe.frameSequence;
                  requestAnimationFrame(() => {
                    if (probe.frameSequence !== frameSequence) return;
                    const firstFrameState = inspect();
                    if (!firstFrameState.commitReady || document.visibilityState !== 'visible') {
                      probe.frameWitnessScheduled = false;
                      return;
                    }
                    requestAnimationFrame(() => {
                      if (probe.frameSequence !== frameSequence) return;
                      const finalFrameState = inspect();
                      probe.frameWitnessScheduled = false;
                      if (finalFrameState.commitReady && document.visibilityState === 'visible') {
                        probe.commitPaintEpochMilliseconds = Date.now();
                      }
                    });
                  });
                }
                const terminalFailure = state.diagnostic.pageReadyState === 'failed'
                  || state.diagnostic.sessionState === 'disposed'
                  || document.querySelector('[data-testid$="failed-shell"]') !== null;
                const finalState = inspect();
                if (terminalFailure) {
                  return JSON.stringify({
                    outcome: 'failed',
                    failureReason: 'terminal_state',
                    pageApplicationEpochMilliseconds: finalState.pageApplicationEpochMilliseconds,
                    handshakeWorkerEpochMilliseconds: finalState.handshakeWorkerEpochMilliseconds,
                    sourceMetadataEpochMilliseconds: probe.sourceMetadataEpochMilliseconds,
                    selectionContentEpochMilliseconds: probe.selectionContentEpochMilliseconds,
                  });
                }
                if (probe.commitPaintEpochMilliseconds !== null && finalState.commitReady
                  && document.visibilityState === 'visible'
                ) {
                  return JSON.stringify({
                    outcome: 'succeeded',
                    pageApplicationEpochMilliseconds: finalState.pageApplicationEpochMilliseconds,
                    handshakeWorkerEpochMilliseconds: finalState.handshakeWorkerEpochMilliseconds,
                    sourceMetadataEpochMilliseconds: probe.sourceMetadataEpochMilliseconds,
                    selectionContentEpochMilliseconds: probe.selectionContentEpochMilliseconds,
                    commitPaintEpochMilliseconds: probe.commitPaintEpochMilliseconds,
                  });
                }
                return JSON.stringify({
                  outcome: 'pending',
                  pageApplicationEpochMilliseconds: finalState.pageApplicationEpochMilliseconds,
                  handshakeWorkerEpochMilliseconds: finalState.handshakeWorkerEpochMilliseconds,
                  sourceMetadataEpochMilliseconds: probe.sourceMetadataEpochMilliseconds,
                  selectionContentEpochMilliseconds: probe.selectionContentEpochMilliseconds,
                });
                """
        }
    }
#endif
