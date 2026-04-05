@MainActor
struct DerivedSelector<Param, Value> {
    let compute: (AtomReader, Param) -> Value

    func value(for param: Param) -> Value {
        compute(AtomReader(), param)
    }
}
