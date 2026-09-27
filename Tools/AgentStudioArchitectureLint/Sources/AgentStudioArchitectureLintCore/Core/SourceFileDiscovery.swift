import Foundation

struct SourceFileDiscovery {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    /// Swift sources and agent instruction documents (`AGENTS.md`) under the
    /// roots, or the roots themselves when they name such files.
    func lintedFiles(under roots: [String]) throws -> [String] {
        var files: [String] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory) else {
                continue
            }
            if isDirectory.boolValue {
                files.append(contentsOf: try lintedFiles(inDirectory: root))
            } else if Self.isLinted(path: root), !shouldSkip(path: root) {
                files.append(URL(fileURLWithPath: root).standardizedFileURL.path)
            }
        }
        return files.sorted()
    }

    private func lintedFiles(inDirectory directory: String) throws -> [String] {
        guard
            let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: directory),
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [String] = []
        for case let url as URL in enumerator {
            let path = url.path
            if shouldSkip(path: path) {
                if isDirectory(url: url) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if Self.isLinted(path: path), isRegularFile(url: url) {
                files.append(path)
            }
        }
        return files
    }

    private func shouldSkip(path: String) -> Bool {
        let skippedComponents = Set(["vendor", ".build", "Frameworks", "node_modules"])
        return URL(fileURLWithPath: path).pathComponents.contains { component in
            skippedComponents.contains(component)
        }
    }

    private static func isLinted(path: String) -> Bool {
        path.hasSuffix(".swift") || AgentDocumentContext.isAgentDocument(path)
    }

    private func isRegularFile(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isDirectory(url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
