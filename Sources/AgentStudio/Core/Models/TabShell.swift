import Foundation

struct TabShell: Identifiable, Equatable {
    let id: UUID

    private(set) var name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = Tab.normalizedName(name)
    }

    mutating func rename(to rawName: String) {
        name = Tab.normalizedName(rawName)
    }
}
