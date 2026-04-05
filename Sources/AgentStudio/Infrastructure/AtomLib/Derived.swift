@MainActor
struct Derived<Value> {
    let compute: (AtomReader) -> Value

    var value: Value {
        compute(AtomReader())
    }
}
