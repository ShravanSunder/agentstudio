import Observation

protocol AtomValueTrivialScalar: Equatable {}

extension Bool: AtomValueTrivialScalar {}
extension Double: AtomValueTrivialScalar {}
extension Float: AtomValueTrivialScalar {}
extension Int: AtomValueTrivialScalar {}
extension String: AtomValueTrivialScalar {}

@MainActor
@Observable
final class AtomValue<Value> {
    private let isContentEqual: (Value, Value) -> Bool
    private(set) var value: Value

    init(
        initialValue: Value,
        isContentEqual: @escaping (Value, Value) -> Bool
    ) {
        self.value = initialValue
        self.isContentEqual = isContentEqual
    }

    func setValue(_ newValue: Value, mutation: AtomMutationContext) {
        mutation.assertMutable()
        guard !isContentEqual(value, newValue) else { return }
        value = newValue
        mutation.recordAcceptedChange()
    }
}

extension AtomValue where Value: AtomValueTrivialScalar {
    convenience init(initialValue: Value) {
        self.init(
            initialValue: initialValue,
            isContentEqual: { lhs, rhs in
                lhs == rhs
            })
    }
}
