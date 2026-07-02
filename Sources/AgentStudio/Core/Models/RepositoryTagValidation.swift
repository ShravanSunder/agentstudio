import Foundation

enum RepositoryTagValidation {
    static func isValid(_ tag: String) -> Bool {
        guard tag == tag.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        guard (1...64).contains(tag.count) else { return false }
        return tag.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !isBidiControlScalar(scalar)
        }
    }

    private static func isBidiControlScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
            return true
        default:
            return false
        }
    }
}
