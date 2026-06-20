import Foundation

struct TabShell: Identifiable, Equatable {
    let id: UUID

    private(set) var name: String
    var colorHex: String?

    init(id: UUID, name: String, colorHex: String? = nil) {
        self.id = id
        self.name = Tab.normalizedName(name)
        self.colorHex = colorHex
    }

    mutating func rename(to rawName: String) {
        name = Tab.normalizedName(rawName)
    }
}
