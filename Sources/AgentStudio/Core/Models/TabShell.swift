import Foundation

struct TabShell: Identifiable, Equatable, Sendable {
    let id: UUID

    private(set) var name: String
    private(set) var colorHex: String?

    init(id: UUID, name: String, colorHex: String? = nil) {
        self.id = id
        self.name = Tab.normalizedName(name)
        self.colorHex = colorHex.map(Self.canonicalColorHex)
    }

    mutating func rename(to rawName: String) {
        name = Tab.normalizedName(rawName)
    }

    mutating func setColorHex(_ rawColorHex: String?) {
        colorHex = rawColorHex.map(Self.canonicalColorHex)
    }

    static func canonicalColorHex(_ rawColorHex: String) -> String {
        rawColorHex.uppercased()
    }
}
