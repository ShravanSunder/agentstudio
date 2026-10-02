/// Suggestions contain visible command identifiers only, ordered by distance
/// then name. The caller's raw identifier is never included as a suggestion.
enum AppCommandClosestMatches {
    static func find(for identifier: String, visibleNames: [String]) -> [String] {
        visibleNames.map { (name: $0, distance: editDistance(identifier, $0)) }
            .sorted { $0.distance == $1.distance ? $0.name < $1.name : $0.distance < $1.distance }
            .prefix(5).map(\.name)
    }

    private static func editDistance(_ first: String, _ second: String) -> Int {
        let firstCharacters = Array(first)
        let secondCharacters = Array(second)
        var previous = Array(0...secondCharacters.count)
        for (firstIndex, firstCharacter) in firstCharacters.enumerated() {
            var current = [firstIndex + 1]
            for (secondIndex, secondCharacter) in secondCharacters.enumerated() {
                current.append(
                    min(
                        min(current[secondIndex] + 1, previous[secondIndex + 1] + 1),
                        previous[secondIndex] + (firstCharacter == secondCharacter ? 0 : 1)))
            }
            previous = current
        }
        return previous[secondCharacters.count]
    }
}
