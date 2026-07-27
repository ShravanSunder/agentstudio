import AppKit

@MainActor
package final class OcticonLoader {
    private let resourceRootURL: URL
    private var cache: [String: NSImage] = [:]

    package init(resourceRootURL: URL) {
        self.resourceRootURL = resourceRootURL
    }

    package func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        let subdirectory = "Icons.xcassets/\(name).imageset"
        let imageSetRoot = resourceRootURL.appending(path: subdirectory)
        let svgURL = imageSetRoot.appending(path: "\(name).svg")
        if let image = NSImage(contentsOf: svgURL) {
            image.isTemplate = true
            cache[name] = image
            return image
        }

        let pdfURL = imageSetRoot.appending(path: "\(name).pdf")
        if let image = NSImage(contentsOf: pdfURL) {
            image.isTemplate = true
            cache[name] = image
            return image
        }

        return nil
    }
}
