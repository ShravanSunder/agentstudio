import Foundation
import Testing

@testable import AgentStudio

@Suite("Admission age measurement")
struct AdmissionAgeMeasurementTests {
    @Test("precision is explicit in the public diagnostic value")
    func precisionIsExplicit() {
        // Arrange
        let exact: AdmissionAgeMeasurement = .exact(.seconds(3))
        let conservative: AdmissionAgeMeasurement = .pressureConservative(.seconds(5))

        // Act / Assert
        #expect(exact == .exact(.seconds(3)))
        #expect(conservative == .pressureConservative(.seconds(5)))
    }

    @Test("successful drain age represents exact precision only")
    func successfulDrainAgeIsExact() {
        let age = ExactAdmissionAge(duration: .seconds(7))

        #expect(age.duration == .seconds(7))
    }
}
