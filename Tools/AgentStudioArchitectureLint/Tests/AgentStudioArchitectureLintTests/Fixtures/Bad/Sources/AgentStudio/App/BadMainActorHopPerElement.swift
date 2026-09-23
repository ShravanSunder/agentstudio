final class BadStreamConsumer {
    var lastValue = 0

    func consume(stream: AsyncStream<Int>) {
        Task.detached {
            for await value in stream {
                await MainActor.run {
                    print(value)
                }
            }
        }
    }

    func consumeOnMainActor(stream: AsyncStream<Int>) {
        Task { @MainActor [weak self] in
            for await value in stream {
                if Task.isCancelled { break }
                self?.lastValue = value
            }
        }
    }

    func consumeWithComparisonThatDoesNotControl(stream: AsyncStream<Int>) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in stream {
                let changed = value != self.lastValue
                print(changed)
                self.lastValue = value
            }
        }
    }
}

@MainActor
final class BadMainActorStreamOwner {
    var lastValue = 0

    func consume(stream: AsyncStream<Int>) async {
        for await value in stream {
            lastValue = value
        }
    }
}
