import WebKit

#if DEBUG
    extension BridgePaneController {
        static func makePageDiagnosticsProbeScript() -> WKUserScript {
            WKUserScript(
                source: pageDiagnosticsProbeScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            )
        }

        private static let pageDiagnosticsProbeScriptSource = """
            (() => {
              const maxEntries = 40;
              const clip = (value, limit) => String(value ?? '').slice(0, limit);
              const pushBounded = (target, entry) => {
                target.push(entry);
                if (target.length > maxEntries) {
                  target.splice(0, target.length - maxEntries);
                }
              };
              window.__bridgeErrorProbe = [];
              window.__bridgePushProbe = [];
              window.__bridgeCommandProbe = [];
              window.__bridgeIntakeReadyCommandProbe = [];
              window.__bridgeWorktreeOpenSourceCommandProbe = [];
              window.__bridgeWorktreeDescriptorRequestCommandProbe = [];
              window.__bridgeResponseProbe = [];
              window.__bridgeIntakeProbe = [];
              const requestLabel = (input) => {
                if (typeof input === 'string') { return input; }
                if (input instanceof URL) { return input.href; }
                return input?.url ?? String(input);
              };
              const recordRPCCommand = (body) => {
                let payload = null;
                if (typeof body === 'string') {
                  try {
                    payload = JSON.parse(body);
                  } catch {
                    payload = null;
                  }
                }
                const commandEntry = {
                  hasDetail: payload !== null,
                  method: clip(payload?.method, 120),
                  protocolId: clip(payload?.params?.protocolId, 120),
                  streamId: clip(payload?.params?.streamId, 160),
                  hasNonce: false,
                  hasCommandId: typeof payload?.__commandId === 'string' || typeof payload?.id === 'string'
                };
                pushBounded(window.__bridgeCommandProbe, commandEntry);
                if (commandEntry.method === 'bridge.intakeReady') {
                  pushBounded(window.__bridgeIntakeReadyCommandProbe, commandEntry);
                }
                if (commandEntry.method === 'worktreeFileSurface.openSourceStream') {
                  pushBounded(window.__bridgeWorktreeOpenSourceCommandProbe, commandEntry);
                }
                if (commandEntry.method === 'worktreeFileSurface.requestFileDescriptor') {
                  pushBounded(window.__bridgeWorktreeDescriptorRequestCommandProbe, commandEntry);
                }
                return commandEntry;
              };
              const recordRPCResponse = (response, commandEntry) => {
                const responseEntry = {
                  hasDetail: true,
                  method: commandEntry?.method || '',
                  status: Number(response?.status || 0),
                  hasResult: false,
                  hasError: false
                };
                try {
                  response.clone().json().then((payload) => {
                    responseEntry.hasResult = payload?.result !== undefined;
                    responseEntry.hasError = payload?.error !== undefined;
                    pushBounded(window.__bridgeResponseProbe, responseEntry);
                  }).catch(() => {
                    pushBounded(window.__bridgeResponseProbe, responseEntry);
                  });
                } catch {
                  pushBounded(window.__bridgeResponseProbe, responseEntry);
                }
              };
              window.addEventListener('error', (event) => {
                pushBounded(window.__bridgeErrorProbe, {
                  kind: 'error',
                  message: clip(event.message, 300),
                  stack: clip(event.error?.stack, 800)
                });
              });
              window.addEventListener('unhandledrejection', (event) => {
                pushBounded(window.__bridgeErrorProbe, {
                  kind: 'unhandledrejection',
                  message: clip(event.reason?.message ?? event.reason, 300),
                  stack: clip(event.reason?.stack, 800)
                });
              });
              if (typeof window.fetch === 'function') {
                const originalFetch = window.fetch.bind(window);
                window.fetch = (input, init) => {
                  const url = requestLabel(input);
                  const rpcCommandEntry = url === 'agentstudio://rpc/command'
                    ? recordRPCCommand(init?.body)
                    : null;
                  return originalFetch(input, init).then((response) => {
                    if (rpcCommandEntry !== null) {
                      recordRPCResponse(response, rpcCommandEntry);
                    }
                    return response;
                  }).catch((error) => {
                    pushBounded(window.__bridgeErrorProbe, {
                      kind: 'fetch_error',
                      message: clip(url + ': ' + (error?.message ?? error), 300),
                      stack: clip(error?.stack, 800)
                    });
                    throw error;
                  });
                };
              }
              document.addEventListener('__bridge_push_json', (event) => {
                pushBounded(window.__bridgePushProbe, {
                  hasDetail: Boolean(event.detail),
                  hasJson: typeof event.detail?.json === 'string',
                  jsonLength: typeof event.detail?.json === 'string'
                    ? event.detail.json.length
                    : -1,
                  nonceLength: typeof event.detail?.nonce === 'string'
                    ? event.detail.nonce.length
                    : -1
                });
              });
              document.addEventListener('__bridge_intake_json', (event) => {
                let parsedFrame = null;
                if (typeof event.detail?.json === 'string') {
                  try {
                    parsedFrame = JSON.parse(event.detail.json);
                  } catch {
                    parsedFrame = null;
                  }
                }
                pushBounded(window.__bridgeIntakeProbe, {
                  hasDetail: Boolean(event.detail),
                  hasJson: typeof event.detail?.json === 'string',
                  jsonLength: typeof event.detail?.json === 'string'
                    ? event.detail.json.length
                    : -1,
                  kind: clip(parsedFrame?.kind, 80),
                  streamId: clip(parsedFrame?.streamId, 160),
                  generation: Number.isFinite(Number(parsedFrame?.generation))
                    ? Number(parsedFrame.generation)
                    : -1,
                  sequence: Number.isFinite(Number(parsedFrame?.sequence))
                    ? Number(parsedFrame.sequence)
                    : -1,
                  payloadFrameKind: clip(parsedFrame?.payload?.frameKind, 120)
                });
              });
            })();
            """
    }
#endif
