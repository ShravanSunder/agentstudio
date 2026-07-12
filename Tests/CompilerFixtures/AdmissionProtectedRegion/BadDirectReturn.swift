func returnAdmissionProtectedRegionTokenDirectly() -> AdmissionProtectedRegionToken {
    AdmissionProtectedRegion.withToken { token in
        // swiftlint:disable:next implicit_return
        return token
    }
}
