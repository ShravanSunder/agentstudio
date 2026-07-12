import Foundation

struct NonEmptyAdmissionBatch<Element: Sendable>: Sendable {
    let first: Element
    let remaining: [Element]

    var count: Int {
        1 + remaining.count
    }

    func forEach(_ body: (Element) throws -> Void) rethrows {
        try body(first)
        for element in remaining {
            try body(element)
        }
    }
}

struct ExactAdmissionAge: Sendable, Equatable {
    let duration: Duration
}

enum AdmissionCleanupQuantum: Sendable, Equatable {
    case entries(maximumEntries: Int)
    case entriesAndBytes(maximumEntries: Int, maximumBytes: Int)

    var isValid: Bool {
        switch self {
        case .entries(let maximumEntries):
            maximumEntries > 0
        case .entriesAndBytes(let maximumEntries, let maximumBytes):
            maximumEntries > 0 && maximumBytes > 0
        }
    }
}

enum AdmissionCleanupRelease: Sendable, Equatable {
    case entries(count: Int)
    case entriesAndBytes(count: Int, bytes: Int)
}

struct AdmissionCleanupTurn: Sendable, Equatable {
    let release: AdmissionCleanupRelease
    let wake: AdmissionWakeDirective
}
