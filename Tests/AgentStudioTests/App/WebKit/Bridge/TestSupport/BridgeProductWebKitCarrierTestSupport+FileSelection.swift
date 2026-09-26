import Foundation
import WebKit

@MainActor
extension BridgeProductWebKitCarrierTestSupport {
    static func selectFilePath(_ page: WebPage, path: String) async -> Bool {
        guard let encodedPathData = try? JSONEncoder().encode(path),
            let encodedPath = String(data: encodedPathData, encoding: .utf8)
        else { return false }
        do {
            let didSelect = try await page.callJavaScript(
                """
                const path = \(encodedPath);
                const selector =
                  `button[data-type="item"][data-item-type="file"][data-item-path="${CSS.escape(path)}"]`;
                const queryInOpenShadowRoots = (root, selector) => {
                  const directMatch = root.querySelector(selector);
                  if (directMatch !== null) return directMatch;
                  for (const element of root.querySelectorAll('*')) {
                    if (element.shadowRoot === null) continue;
                    const shadowMatch = queryInOpenShadowRoots(element.shadowRoot, selector);
                    if (shadowMatch !== null) return shadowMatch;
                  }
                  return null;
                };
                const button = queryInOpenShadowRoots(document, selector);
                if (!(button instanceof HTMLElement)) return false;
                button.click();
                return true;
                """
            )
            return didSelect as? Bool ?? false
        } catch {
            return false
        }
    }

    static func waitForAndSelectFilePath(_ page: WebPage, path: String) async throws -> Bool {
        guard let encodedPathData = try? JSONEncoder().encode(path),
            let encodedPath = String(data: encodedPathData, encoding: .utf8)
        else { return false }

        let didSelect = try await WebPageEventWaits.waitForDocumentValue(
            page,
            reader: """
                const path = \(encodedPath);
                const selector =
                  `button[data-type="item"][data-item-type="file"][data-item-path="${CSS.escape(path)}"]`;
                const queryInOpenShadowRoots = (root, selector) => {
                  const directMatch = root.querySelector(selector);
                  if (directMatch !== null) return directMatch;
                  for (const element of root.querySelectorAll('*')) {
                    if (element.shadowRoot === null) continue;
                    const shadowMatch = queryInOpenShadowRoots(element.shadowRoot, selector);
                    if (shadowMatch !== null) return shadowMatch;
                  }
                  return null;
                };
                const button = queryInOpenShadowRoots(document, selector);
                if (!(button instanceof HTMLElement)) return null;
                button.click();
                return true;
                """,
            arguments: [:]
        )
        return didSelect as? Bool ?? false
    }
}
