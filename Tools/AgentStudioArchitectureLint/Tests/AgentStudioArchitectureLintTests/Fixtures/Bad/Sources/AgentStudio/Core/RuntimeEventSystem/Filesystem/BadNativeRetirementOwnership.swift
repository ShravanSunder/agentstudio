struct BadNativeRetirementOwnership {
    func forgeReleaseAuthority() {
        _ = FilesystemObservationContextReleaseAuthority(value: UUID())
    }
}
