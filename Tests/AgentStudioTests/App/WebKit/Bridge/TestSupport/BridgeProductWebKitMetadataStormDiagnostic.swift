/// Formats bounded existing telemetry for the hidden-pane journey failure.
enum BridgeProductWebKitMetadataStormDiagnostic {
    static func message(
        nativeBefore: BridgeProductWebKitCarrierNativeSnapshot,
        nativeAfter: BridgeProductWebKitCarrierNativeSnapshot,
        traceBefore: BridgeProductWebKitCarrierTrace,
        traceAfter: BridgeProductWebKitCarrierTrace
    ) -> String {
        let paneEvents = appendedValues(
            traceAfter.panePresentationEvents,
            after: traceBefore.panePresentationEvents
        )
        let filePhases = appendedValues(
            traceAfter.fileMetadataPhases,
            after: traceBefore.fileMetadataPhases
        )
        let reviewPhases = appendedValues(
            traceAfter.reviewMetadataPhases,
            after: traceBefore.reviewMetadataPhases
        )
        return "hidden metadata storm: sequence=\(nativeBefore.nextMetadataStreamSequence)"
            + "->\(nativeAfter.nextMetadataStreamSequence), "
            + "control=next:\(nativeBefore.nextControlRequestSequence)"
            + "->\(nativeAfter.nextControlRequestSequence)"
            + "/inFlight:\(String(describing: nativeBefore.inFlightControlRequestSequence))"
            + "->\(String(describing: nativeAfter.inFlightControlRequestSequence)), "
            + "frames=queued:\(nativeBefore.queuedFrameCount)->\(nativeAfter.queuedFrameCount)"
            + "/inFlight:\(nativeBefore.inFlightFrameReceiptCount)"
            + "->\(nativeAfter.inFlightFrameReceiptCount), "
            + "pane=\(boundedDescription(paneEvents)), "
            + "file=\(boundedDescription(filePhases)), "
            + "review=\(boundedDescription(reviewPhases))"
    }

    private static func appendedValues<Element>(
        _ values: [Element],
        after baseline: [Element]
    ) -> ArraySlice<Element> {
        values.dropFirst(min(values.count, baseline.count))
    }

    private static func boundedDescription<Element>(
        _ values: ArraySlice<Element>
    ) -> String {
        let visibleValues = values.prefix(8).map { String(describing: $0) }
        let omittedCount = values.count - visibleValues.count
        let suffix = omittedCount == 0 ? "" : ",+\(omittedCount) more"
        return "+\(values.count)[\(visibleValues.joined(separator: ","))\(suffix)]"
    }
}
