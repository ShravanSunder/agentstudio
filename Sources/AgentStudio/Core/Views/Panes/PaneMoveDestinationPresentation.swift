enum PaneMoveDestinationPresentation {
    static let maximumCharacterCount = 48

    static func title(
        tabOrdinal: Int,
        tabTitle: String
    ) -> String {
        let prefix = "Tab \(tabOrdinal): "
        let fullTitle = prefix + tabTitle
        guard fullTitle.count > maximumCharacterCount else {
            return fullTitle
        }

        let titleCharacterBudget = maximumCharacterCount - prefix.count - 1
        let leadingCharacterCount = max(1, titleCharacterBudget * 2 / 5)
        let trailingCharacterCount = max(
            1,
            titleCharacterBudget - leadingCharacterCount
        )
        return prefix
            + tabTitle.prefix(leadingCharacterCount)
            + "…"
            + tabTitle.suffix(trailingCharacterCount)
    }
}
