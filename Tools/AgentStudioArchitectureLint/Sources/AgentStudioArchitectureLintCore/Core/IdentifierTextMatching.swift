extension String {
    /// Whether this identifier contains `lowercaseNeedle`, ignoring ASCII
    /// case. Rules call this for every identifier in the corpus; Swift
    /// identifiers the rules look for are ASCII, so a byte scan gives the same
    /// answer as a Foundation case-insensitive search without bridging.
    func containsIgnoringASCIICase(_ lowercaseNeedle: String) -> Bool {
        let haystack = Array(utf8)
        let needle = Array(lowercaseNeedle.utf8)
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return needle.isEmpty
        }
        for start in 0...(haystack.count - needle.count) {
            var matches = true
            for offset in 0..<needle.count {
                var byte = haystack[start + offset]
                if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") {
                    byte += 32
                }
                if byte != needle[offset] {
                    matches = false
                    break
                }
            }
            if matches {
                return true
            }
        }
        return false
    }
}
