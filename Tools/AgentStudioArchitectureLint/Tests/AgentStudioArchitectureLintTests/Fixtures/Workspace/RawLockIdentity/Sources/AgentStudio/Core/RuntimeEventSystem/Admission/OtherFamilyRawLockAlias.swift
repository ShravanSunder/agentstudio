private typealias OtherFamilyRawLock<State> = OSAllocatedUnfairLock<State>

private struct OtherAdmissionFamilyRawOwner {
    let lock: OtherFamilyRawLock<Int>
}
