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
              const requestLabel = (input) => {
                if (typeof input === 'string') { return input; }
                if (input instanceof URL) { return input.href; }
                return input?.url ?? String(input);
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
                  return originalFetch(input, init).catch((error) => {
                    pushBounded(window.__bridgeErrorProbe, {
                      kind: 'fetch_error',
                      message: clip(url + ': ' + (error?.message ?? error), 300),
                      stack: clip(error?.stack, 800)
                    });
                    throw error;
                  });
                };
              }
            })();
            """
    }
#endif
