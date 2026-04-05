import AppKit

@MainActor
final class OcticonLoader {
    static let shared = OcticonLoader()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        let subdirectory = "Icons.xcassets/\(name).imageset"
        if let svgURL = Bundle.appResources.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: svgURL)
        {
            image.isTemplate = true
            cache[name] = image
            return image
        }

        if let pdfURL = Bundle.appResources.url(
            forResource: name,
            withExtension: "pdf",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: pdfURL)
        {
            image.isTemplate = true
            cache[name] = image
            return image
        }

        return nil
    }
}
