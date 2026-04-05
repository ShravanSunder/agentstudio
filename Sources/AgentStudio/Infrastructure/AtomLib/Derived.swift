@MainActor
struct Derived<Value> {
    private let compute: (AtomReader) -> Value

    init(_ compute: @escaping (AtomReader) -> Value) {
        self.compute = compute
    }

    var value: Value {
        compute(AtomReader())
    }
}
