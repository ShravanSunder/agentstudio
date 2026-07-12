struct AdmissionProtectedRegionTokenHolder {
    let token: AdmissionProtectedRegionToken
}

func storeAdmissionProtectedRegionToken() -> AdmissionProtectedRegionTokenHolder {
    AdmissionProtectedRegion.withToken { token in
        AdmissionProtectedRegionTokenHolder(token: token)
    }
}
