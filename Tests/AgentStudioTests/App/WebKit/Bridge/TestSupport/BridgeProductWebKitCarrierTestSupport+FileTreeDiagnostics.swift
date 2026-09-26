import Foundation
import WebKit

struct BridgeProductWebKitFileTreeDOMSnapshot: Decodable {
    let shellTreeRowCount: Int
    let mountedPathRowCount: Int
    let mountedFileDisplayPaths: [String]
    let filteredFileRelativePaths: [String]
    let unmatchedFileRowCount: Int
}

@MainActor
extension BridgeProductWebKitCarrierTestSupport {
    static func fileTreeDOMSnapshot(
        _ page: WebPage,
        memberGroupDisplayPath: String
    ) async throws -> BridgeProductWebKitFileTreeDOMSnapshot {
        let encodedSnapshot = try await page.callJavaScript(
            """
            const readFileTreeDOMSnapshot = () => {
              const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
              const fileTree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
              if (fileTree === null) return null;
              const collectRows = (root, into) => {
                for (const element of root.querySelectorAll('[data-item-path]')) {
                  into.push({
                    path: element.getAttribute('data-item-path') ?? '',
                    type: element.getAttribute('data-item-type') ?? ''
                  });
                }
                for (const element of root.querySelectorAll('*')) {
                  if (element.shadowRoot !== null) collectRows(element.shadowRoot, into);
                }
              };
              const rows = [];
              collectRows(fileTree, rows);
              const mountedFileDisplayPaths = rows
                .filter((row) => row.type === 'file')
                .map((row) => row.path)
                .sort();
              const memberPrefix = memberGroupDisplayPath.endsWith('/')
                ? memberGroupDisplayPath
                : `${memberGroupDisplayPath}/`;
              const filteredFileRelativePaths = mountedFileDisplayPaths
                .filter((path) => path.startsWith(memberPrefix))
                .map((path) => path.slice(memberPrefix.length))
                .sort();
              return JSON.stringify({
                shellTreeRowCount: Number(fileShell?.getAttribute('data-file-display-tree-row-count') ?? '0'),
                mountedPathRowCount: rows.length,
                mountedFileDisplayPaths,
                filteredFileRelativePaths,
                unmatchedFileRowCount: mountedFileDisplayPaths.filter((path) => !path.startsWith(memberPrefix)).length
              });
            };
            const snapshot = readFileTreeDOMSnapshot();
            return snapshot;
            """,
            arguments: ["memberGroupDisplayPath": memberGroupDisplayPath]
        )
        return try decodeFileTreeDOMSnapshot(encodedSnapshot)
    }

    /// Suspends on tree DOM mutations until the exact member-relative file row set is mounted.
    static func waitForFileTreeItemPaths(
        _ page: WebPage,
        memberGroupDisplayPath: String,
        equals expectedRelativePaths: [String]
    ) async throws -> BridgeProductWebKitFileTreeDOMSnapshot {
        let encodedSnapshot = try await WebPageEventWaits.waitForDocumentValue(
            page,
            reader: """
                const readFileTreeDOMSnapshot = () => {
                  const fileShell = document.querySelector('[data-testid="bridge-file-viewer-shell"]');
                  const fileTree = document.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
                  if (fileTree === null) return null;
                  const collectRows = (root, into) => {
                    for (const element of root.querySelectorAll('[data-item-path]')) {
                      into.push({
                        path: element.getAttribute('data-item-path') ?? '',
                        type: element.getAttribute('data-item-type') ?? ''
                      });
                    }
                    for (const element of root.querySelectorAll('*')) {
                      if (element.shadowRoot !== null) collectRows(element.shadowRoot, into);
                    }
                  };
                  const rows = [];
                  collectRows(fileTree, rows);
                  const mountedFileDisplayPaths = rows
                    .filter((row) => row.type === 'file')
                    .map((row) => row.path)
                    .sort();
                  const memberPrefix = memberGroupDisplayPath.endsWith('/')
                    ? memberGroupDisplayPath
                    : `${memberGroupDisplayPath}/`;
                  const filteredFileRelativePaths = mountedFileDisplayPaths
                    .filter((path) => path.startsWith(memberPrefix))
                    .map((path) => path.slice(memberPrefix.length))
                    .sort();
                  const expected = expectedRelativePaths.slice().sort();
                  const unmatchedFileRowCount = mountedFileDisplayPaths
                    .filter((path) => !path.startsWith(memberPrefix)).length;
                  const exactMemberFileSetMatches =
                    expected.length === filteredFileRelativePaths.length &&
                    expected.every((path, index) => path === filteredFileRelativePaths[index]);
                  if (!exactMemberFileSetMatches || unmatchedFileRowCount !== 0) return null;
                  return JSON.stringify({
                    shellTreeRowCount: Number(fileShell?.getAttribute('data-file-display-tree-row-count') ?? '0'),
                    mountedPathRowCount: rows.length,
                    mountedFileDisplayPaths,
                    filteredFileRelativePaths,
                    unmatchedFileRowCount
                  });
                };
                return readFileTreeDOMSnapshot();
                """,
            arguments: [
                "expectedRelativePaths": expectedRelativePaths,
                "memberGroupDisplayPath": memberGroupDisplayPath,
            ]
        )
        return try decodeFileTreeDOMSnapshot(encodedSnapshot)
    }

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

private func decodeFileTreeDOMSnapshot(
    _ encodedSnapshot: Any?
) throws -> BridgeProductWebKitFileTreeDOMSnapshot {
    guard let encodedSnapshot = encodedSnapshot as? String,
        let data = encodedSnapshot.data(using: .utf8)
    else {
        throw BridgeProductWebKitFileTreeDiagnosticsError.snapshotWasNotReturned
    }
    return try JSONDecoder().decode(BridgeProductWebKitFileTreeDOMSnapshot.self, from: data)
}

private enum BridgeProductWebKitFileTreeDiagnosticsError: Error {
    case snapshotWasNotReturned
}
