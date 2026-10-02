package struct GitPRSummaryChipModel: Equatable, Sendable {
    package let model: GitPRSummaryPopoverModel
    package let presentation: GitPRSummaryPresentationModel
    package let control: PaneContextControlModel
    package init(
        model: GitPRSummaryPopoverModel, presentation: GitPRSummaryPresentationModel, control: PaneContextControlModel
    ) {
        self.model = model
        self.presentation = presentation
        self.control = control
    }
}
