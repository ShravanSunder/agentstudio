import AsyncAlgorithms
import Observation
import Testing
import Foundation

// MARK: - Test Support Types

/// Minimal @Observable class used exclusively by spike tests.
/// Two independent properties let us verify property-group isolation.
@Observable
final class SpikeTestState: @unchecked Sendable {
    var propertyA: Int = 0
    var propertyB: String = "initial"
}

// MARK: - @resultBuilder Spike Types

/// Minimal @resultBuilder with a generic type parameter.
/// Validates that Swift 6.2 compiles generic result builders correctly.
@resultBuilder
struct SpikeBuilder<T> {
    static func buildExpression(_ expression: T) -> [T] {
        [expression]
    }

    static func buildBlock(_ components: [T]...) -> [T] {
        components.flatMap { $0 }
    }
}

/// Container that uses SpikeBuilder to collect elements via result-builder syntax.
struct SpikeContainer<T> {
    let elements: [T]

    init(@SpikeBuilder<T> content: () -> [T]) {
        self.elements = content()
    }
}

// MARK: - Tests

/// Verification spike for SE-0475 Observations, AsyncAlgorithms debounce,
/// property-group isolation, and generic @resultBuilder.
///
/// These tests validate that the Swift 6.2 / macOS 26 primitives required
/// by the push pipeline (Slice, PushPlanBuilder) work as documented.
@MainActor
@Suite(.serialized)
final class ObservationSpikeTests {

    // MARK: - 1. Observations Basic Iteration

    /// Verify that `Observations { state.propertyA }` yields values
    /// when propertyA changes, starting with the initial value.
    @Test
    func test_observations_basicIteration_yieldsOnPropertyChange() async throws {
        // Arrange
        let state = SpikeTestState()
        var collectedValues: [Int] = []

        let observationTask = Task { @MainActor in
            let stream = Observations { state.propertyA }
            for await value in stream {
                collectedValues.append(value)
                // Initial value (0) + two mutations = 3 values
                if collectedValues.count >= 3 {
                    break
                }
            }
        }

        // Give the observation loop time to start and receive initial value
        try await Task.sleep(for: .milliseconds(50))

        // Act — mutate propertyA twice
        state.propertyA = 10
        try await Task.sleep(for: .milliseconds(50))
        state.propertyA = 20
        try await Task.sleep(for: .milliseconds(50))

        // Assert
        let didCollectValues = try await waitForCondition {
            collectedValues.count >= 3
        }
        #expect(didCollectValues)
        observationTask.cancel()

        #expect(collectedValues.count >= 3, "Expected initial value + 2 mutations = at least 3 values")
        #expect(collectedValues.first == 0, "First emitted value should be the initial value (0)")
        #expect(collectedValues.contains(10), "Should contain mutation value 10")
        #expect(collectedValues.contains(20), "Should contain mutation value 20")
    }

    // MARK: - 2. Observations Debounce

    /// Verify that `.debounce(for:)` from AsyncAlgorithms coalesces rapid
    /// mutations into fewer emitted values.
    @Test
    func test_observations_debounce_coalescesRapidMutations() async throws {
        // Arrange
        let state = SpikeTestState()
        var collectedValues: [Int] = []

        let observationTask = Task { @MainActor in
            let stream = Observations { state.propertyA }
                .debounce(for: .milliseconds(100))
            for await value in stream {
                collectedValues.append(value)
                // Stop after enough time for all values to settle
                if collectedValues.count >= 3 {
                    break
                }
            }
        }

        // Give the observation loop time to start
        try await Task.sleep(for: .milliseconds(50))

        // Act — rapid mutations (all within 100ms debounce window)
        state.propertyA = 1
        try await Task.sleep(for: .milliseconds(10))
        state.propertyA = 2
        try await Task.sleep(for: .milliseconds(10))
        state.propertyA = 3

        // Wait for debounce to settle (100ms debounce + generous buffer)
        try await Task.sleep(for: .milliseconds(300))

        // Assert
        let didReceiveDebouncedValue = try await waitForCondition {
            collectedValues.count >= 1
        }
        #expect(didReceiveDebouncedValue)
        observationTask.cancel()

        // The debounced stream should have fewer values than the 4 events
        // (initial 0, then 1, 2, 3). The rapid 1/2/3 mutations should
        // coalesce so we get fewer than 4 distinct emissions.
        #expect(collectedValues.count < 4, "Debounce should coalesce rapid mutations: got \(collectedValues) (\(collectedValues.count) values)")

        // The last emitted value should be 3 (the final settled value)
        #expect(collectedValues.last == 3, "Last debounced value should be the final mutation (3), got \(collectedValues)")
    }

    // MARK: - 3. Property-Group Isolation (CRITICAL)

    /// CRITICAL TEST: Verify that observing propertyA does NOT fire when
    /// only propertyB changes, and vice versa.
    ///
    /// If this test fails, the entire Slice design from section 6.5 is broken
    /// because each Slice capture closure would fire on unrelated property changes.
    @Test
    func test_observations_propertyGroupIsolation_onlyFiresForTrackedProperties() async throws {
        // Arrange
        let state = SpikeTestState()
        var propertyAValues: [Int] = []
        var propertyBValues: [String] = []

        // Observer for propertyA
        let propertyATask = Task { @MainActor in
            let stream = Observations { state.propertyA }
            for await value in stream {
                propertyAValues.append(value)
                // We only expect the initial value; do NOT expect more
            }
        }

        // Observer for propertyB
        let propertyBTask = Task { @MainActor in
            let stream = Observations { state.propertyB }
            for await value in stream {
                propertyBValues.append(value)
                // Initial value + 1 mutation = 2 values
                if propertyBValues.count >= 2 {
                    break
                }
            }
        }

        // Give both observation loops time to start and receive initial values
        try await Task.sleep(for: .milliseconds(100))

        // Record propertyA observation count BEFORE mutating propertyB
        let propertyACountBeforeMutation = propertyAValues.count

        // Act — change ONLY propertyB
        state.propertyB = "changed"

        // Give time for any erroneous propertyA firing
        try await Task.sleep(for: .milliseconds(200))

        // Assert
        let didReceivePropertyBUpdate = try await waitForCondition {
            propertyBValues.count >= 2
        }
        #expect(didReceivePropertyBUpdate)
        propertyATask.cancel()
        propertyBTask.cancel()

        // propertyB observer MUST have fired
        #expect(propertyBValues.contains("changed"), "propertyB observer must fire when propertyB changes. Got: \(propertyBValues)")

        // CRITICAL: propertyA observer must NOT have received new values
        // after the initial emission
        #expect(propertyAValues.count == propertyACountBeforeMutation, """
            CRITICAL FAILURE: Property-group isolation is broken!
            propertyA observer fired when only propertyB changed.
            propertyA values before mutation: \(propertyACountBeforeMutation)
            propertyA values after mutation: \(propertyAValues.count)
            propertyA collected: \(propertyAValues)
            This means the Slice design from section 6.5 will NOT work —
            each Slice would fire on every property change regardless of capture.
            """)
    }

    // MARK: - 4. @resultBuilder with Generic Type Parameter

    /// Verify that a generic @resultBuilder compiles and produces correct output.
    @Test
    func test_resultBuilder_genericTypeParameter_compilesAndProducesCorrectOutput() {
        // Arrange & Act — Int container
        let intContainer = SpikeContainer<Int> {
            1
            2
            3
        }

        // Assert
        #expect(intContainer.elements == [1, 2, 3], "SpikeBuilder<Int> should collect integer expressions into an array")

        // Arrange & Act — String container
        let stringContainer = SpikeContainer<String> {
            "hello"
            "world"
        }

        // Assert
        #expect(stringContainer.elements == ["hello", "world"], "SpikeBuilder<String> should collect string expressions into an array")
    }

    private func waitForCondition(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
        condition: () -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if condition() {
                return true
            }

            try await clock.sleep(for: pollInterval)
        }

        return condition()
    }
}
