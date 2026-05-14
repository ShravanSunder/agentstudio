import Foundation

private let resourceBundleName = "AgentStudio_AgentStudio.bundle"

extension Bundle {
    /// Resource bundle for both .app distribution and development builds.
    ///
    /// SwiftPM's generated `Bundle.module` looks at the .app root (`bundleURL`),
    /// which codesign forbids ("unsealed contents present in the bundle root").
    /// This accessor checks `Contents/Resources/` first via `resourceURL`,
    /// falling back to `Bundle.module` for `swift run` / `swift test`.
    static var appResources: Bundle {
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(resourceBundleName)
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return Bundle.module
    }
}
