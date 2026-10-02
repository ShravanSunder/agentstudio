import Foundation

extension CLIStore {
    // S4 RED stand-in: the lifecycle repository has no writes yet.
    package func appendLifecycleReport(_ record: CLILifecycleReportRecord) -> Result<
        CLILifecycleReport, CLIStoreFailure
    > {
        .failure(.unavailable)
    }

    // S4 RED stand-in: readiness cannot read a lifecycle high-water boundary yet.
    package func lifecycleReportBoundary() -> Result<Int64, CLIStoreFailure> { .failure(.unavailable) }

    // S4 RED stand-in: no stored lifecycle envelope is interpreted yet.
    package func readLifecycleReports(after mark: Int64, through boundary: Int64? = nil)
        -> Result<CLILifecycleReadBatch, CLIStoreFailure>
    {
        .failure(.unavailable)
    }

    // S4 RED stand-in: cleanup leaves every lifecycle row untouched.
    package func purgeHandledLifecycleReports(expectedStoreID: UUID, through mark: Int64, now: Date)
        -> Result<Int, CLIStoreFailure>
    {
        .success(0)
    }
}
