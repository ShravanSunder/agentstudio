struct AdmissionProtectedRegionToken: ~Copyable, Sendable {
    fileprivate init() {}
}

enum AdmissionProtectedRegion {
    static func withToken<Result>(
        _ body: (AdmissionProtectedRegionToken) throws -> Result
    ) rethrows -> Result {
        try body(AdmissionProtectedRegionToken())
    }
}
