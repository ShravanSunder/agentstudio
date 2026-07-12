func constructImmediateReplayCaptureWithReader()
    -> OrderedFactReplayCapture<Int, Int>
{
    OrderedFactReplayCapture(
        readerIdentity: AdmissionOpaqueIdentity(),
        content: .immediate(.invalidated)
    )
}
