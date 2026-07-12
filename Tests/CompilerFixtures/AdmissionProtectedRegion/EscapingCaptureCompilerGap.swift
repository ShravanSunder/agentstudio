func captureAdmissionProtectedRegionTokenInEscapingClosure() -> () -> Void {
    AdmissionProtectedRegion.withToken { token in
        { _ = token }
    }
}
