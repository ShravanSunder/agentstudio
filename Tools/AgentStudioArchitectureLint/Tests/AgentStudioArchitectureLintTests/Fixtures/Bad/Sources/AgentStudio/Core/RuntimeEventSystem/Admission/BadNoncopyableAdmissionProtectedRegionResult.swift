struct AdmissionProtectedRegionToken: ~Copyable, Sendable {
    fileprivate init() {}
}

enum AdmissionProtectedRegion {
    static func withToken<Result: ~Copyable>(
        _ body: (borrowing AdmissionProtectedRegionToken) throws -> Result
    ) rethrows -> Result {
        try body(AdmissionProtectedRegionToken())
    }
}
