final class GoodStreamConsumer {
    var lastValue = 0

    func consumeWithGuard(stream: AsyncStream<Int>) {
        Task { @MainActor [weak self] in
            for await value in stream {
                guard !Task.isCancelled else { break }
                guard let self, value != self.lastValue else { continue }
                self.lastValue = value
            }
        }
    }

    func consumeWithSkip(stream: AsyncStream<Int>) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in stream {
                if value == self.lastValue { continue }
                self.lastValue = value
            }
        }
    }

    func consumeNestedInChange(stream: AsyncStream<Int>) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for await value in stream {
                if value != self.lastValue {
                    self.lastValue = value
                }
            }
        }
    }

    func consumeOffMainActor(stream: AsyncStream<Int>) {
        Task.detached {
            for await value in stream {
                print(value)
            }
        }
    }
}

actor GoodStreamActor {
    var lastValue = 0

    func consume(stream: AsyncStream<Int>) async {
        for await value in stream {
            lastValue = value
        }
    }
}
