import Foundation

struct BridgeTelemetryAdmissionDecision: Equatable, Sendable {
    let samples: [BridgeTelemetrySample]
    let droppedCount: Int
    let firstDroppedEventName: String?
}

struct BridgeTelemetryAdmissionController: Sendable {
    private var highVolumeWindowStartUnixNano: UInt64?
    private var highVolumeAcceptedInWindow = 0

    mutating func admit(
        samples: [BridgeTelemetrySample],
        receivedAtUnixNano: UInt64
    ) -> BridgeTelemetryAdmissionDecision {
        var admittedSamples: [BridgeTelemetrySample] = []
        admittedSamples.reserveCapacity(samples.count)
        var droppedCount = 0
        var firstDroppedEventName: String?

        for sample in samples {
            guard Self.isAdmittedThroughHighVolumeBudget(sample) else {
                admittedSamples.append(sample)
                continue
            }

            refreshHighVolumeWindow(receivedAtUnixNano: receivedAtUnixNano)
            guard highVolumeAcceptedInWindow < AppPolicies.Bridge.telemetryHighVolumeAdmissionLimit else {
                droppedCount += 1
                if firstDroppedEventName == nil {
                    firstDroppedEventName = sample.name
                }
                continue
            }

            highVolumeAcceptedInWindow += 1
            admittedSamples.append(sample)
        }

        return BridgeTelemetryAdmissionDecision(
            samples: admittedSamples,
            droppedCount: droppedCount,
            firstDroppedEventName: firstDroppedEventName
        )
    }

    private mutating func refreshHighVolumeWindow(receivedAtUnixNano: UInt64) {
        let windowNanoseconds = AppPolicies.Bridge.telemetryHighVolumeAdmissionWindow.nanosecondsForTaskSleep
        guard let windowStart = highVolumeWindowStartUnixNano,
            receivedAtUnixNano >= windowStart,
            receivedAtUnixNano - windowStart < windowNanoseconds
        else {
            highVolumeWindowStartUnixNano = receivedAtUnixNano
            highVolumeAcceptedInWindow = 0
            return
        }
    }

    private static func isAdmittedThroughHighVolumeBudget(_ sample: BridgeTelemetrySample) -> Bool {
        sample.scope == .web
            && AppPolicies.Bridge.telemetryHighVolumeEventNames.contains(sample.name)
            && !isProofRequiredSelectedSample(sample)
    }

    private static func isProofRequiredSelectedSample(_ sample: BridgeTelemetrySample) -> Bool {
        if AppPolicies.Bridge.telemetryAlwaysProofRequiredEventNames.contains(sample.name) {
            return true
        }
        guard AppPolicies.Bridge.telemetrySelectedProofRequiredEventNames.contains(sample.name) else {
            return false
        }
        return sample.booleanAttributes[AppPolicies.Bridge.telemetrySelectedBooleanAttributeKey] == true
    }
}
