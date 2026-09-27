import AgentStudioInfrastructure
import Foundation

extension RepoExplorerProjectionWorker {
    func updatePresentationDeadline(
        _ preparedDeadline: RepoExplorerPreparedPresentationDeadline?,
        demanded: Bool,
        generation: Int
    ) async {
        guard generation > latestPresentationDeadlineGeneration else { return }
        latestPresentationDeadlineGeneration = generation
        let precedingTask = presentationDeadlineTask
        presentationDeadlineTask = nil
        precedingTask?.cancel()
        await precedingTask?.value
        guard generation == latestPresentationDeadlineGeneration,
            demanded,
            let preparedDeadline
        else { return }

        let maximumDelaySeconds = Double(Int64.max / 1_000_000_000)
        let remainingSeconds: Double
        if let referenceInstant = preparedDeadline.referenceInstant,
            let referenceDate = preparedDeadline.referenceDate
        {
            let elapsed = referenceInstant.duration(to: presentationDeadlineContinuousNow()).components
            let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
            remainingSeconds = preparedDeadline.deadline.timeIntervalSince(referenceDate) - elapsedSeconds
        } else {
            remainingSeconds = preparedDeadline.deadline.timeIntervalSince(presentationDeadlineNow())
        }
        let delaySeconds = max(
            0,
            min(remainingSeconds, maximumDelaySeconds)
        )
        let duration = Duration.nanoseconds(Int64(delaySeconds * 1_000_000_000))
        let delay = presentationDeadlineDelay
        presentationDeadlineTask = Task { [weak self] in
            do {
                try await delay.wait(duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.presentationDeadlineFired(preparedDeadline, generation: generation)
        }
    }

    func hasPendingPresentationDeadline() -> Bool {
        presentationDeadlineTask != nil
    }

    private func presentationDeadlineFired(
        _ preparedDeadline: RepoExplorerPreparedPresentationDeadline,
        generation: Int
    ) async {
        guard generation == latestPresentationDeadlineGeneration else { return }
        presentationDeadlineTask = nil
        await onPresentationDeadline(generation, preparedDeadline)
    }
}
