import Foundation

extension GitWorkingDirectoryProjector {
    nonisolated static func pathsIntersect(_ lhs: String, _ rhs: String) -> Bool {
        isSameOrDescendantPath(lhs, of: rhs) || isSameOrDescendantPath(rhs, of: lhs)
    }

    nonisolated private static func isSameOrDescendantPath(_ path: String, of rootPath: String) -> Bool {
        let comparisonPath = path.lowercased()
        let comparisonRootPath = rootPath.lowercased()
        if comparisonPath == comparisonRootPath {
            return true
        }
        if comparisonRootPath == "/" {
            return comparisonPath.hasPrefix("/")
        }
        return comparisonPath.hasPrefix(comparisonRootPath + "/")
    }
}
