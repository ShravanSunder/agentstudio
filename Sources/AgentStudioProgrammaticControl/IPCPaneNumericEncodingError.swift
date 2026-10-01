/// A new monotonic wire counter above the JSON safe-integer range is an
/// internal invariant failure, never a rounded response.
package enum IPCPaneNumericEncodingError: Error, Equatable, Sendable {
    case aboveSafeIntegerBound
}
