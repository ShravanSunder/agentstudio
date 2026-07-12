func admissionProtectedRegionReturnsUnrelatedCopyableResult() -> Int {
    AdmissionProtectedRegion.withToken { token in
        _ = token
        return 42
    }
}
