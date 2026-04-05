@MainActor
struct DerivedSelector<Param, Value> {
    private let compute: (AtomReader, Param) -> Value

    init(_ compute: @escaping (AtomReader, Param) -> Value) {
        self.compute = compute
    }

    func value(for param: Param) -> Value {
        compute(AtomReader(), param)
    }
}
