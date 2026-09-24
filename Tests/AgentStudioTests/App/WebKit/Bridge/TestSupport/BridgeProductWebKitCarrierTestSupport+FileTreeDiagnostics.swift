import Foundation
import WebKit

@MainActor
extension BridgeProductWebKitCarrierTestSupport {
    /// Every mounted File tree item path, for diagnosing a selection that
    /// could not find its row.
    static func mountedFileTreeItemPaths(_ page: WebPage) async -> [String] {
        let paths = try? await page.callJavaScript(
            """
            const collect = (root, into) => {
              for (const element of root.querySelectorAll('[data-item-path]')) {
                into.push(element.getAttribute('data-item-path') ?? '');
              }
              for (const element of root.querySelectorAll('*')) {
                if (element.shadowRoot !== null) collect(element.shadowRoot, into);
              }
              return into;
            };
            const fileTree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
            if (fileTree === null) return ['<no File tree>'];
            const paths = collect(fileTree, []);
            if (paths.length > 0) return paths;
            // An empty tree names the page state that decides whether queued
            // tree patches drain (they apply on animation frames).
            const scroll = fileTree
              .querySelector('file-tree-container')
              ?.shadowRoot?.querySelector('[data-file-tree-virtualized-scroll="true"]');
            return [
              `<no rows: visibility=${document.visibilityState}` +
                ` scrollClient=${scroll?.clientHeight ?? 'none'} scrollContent=${scroll?.scrollHeight ?? 'none'}>`
            ];
            """
        )
        return paths as? [String] ?? []
    }
}
