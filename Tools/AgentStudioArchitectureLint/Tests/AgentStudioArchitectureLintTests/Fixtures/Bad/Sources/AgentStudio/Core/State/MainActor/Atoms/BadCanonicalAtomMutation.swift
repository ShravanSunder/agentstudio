final class BadCanonicalAtomMutation {
    var externallyWritableCount = 0
    var observedValue = 0 { didSet {} }
    @Binding private var writableSelection: Int
    package lazy var writableDerivedReader = BadPaneDerived()

    private(set) var allowedReadOnlyCount = 0
    private var allowedPrivateCount = 0
}

final class BadPaneDerived {}
