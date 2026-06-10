import Foundation

struct BridgeViewFilter: Codable, Equatable, Sendable {
    let includedPathGlobs: [String]
    let excludedPathGlobs: [String]
    let includedFileClasses: [BridgeFileClass]
    let excludedFileClasses: [BridgeFileClass]
    let includedExtensions: [String]
    let excludedExtensions: [String]
    let changeKinds: [BridgeFileChangeKind]
    let reviewStates: [BridgeFileReviewState]
    let showHiddenFiles: Bool
    let showBinaryFiles: Bool
    let showLargeFiles: Bool

    init(
        includedPathGlobs: [String] = [],
        excludedPathGlobs: [String] = [],
        includedFileClasses: [BridgeFileClass] = [],
        excludedFileClasses: [BridgeFileClass] = [],
        includedExtensions: [String] = [],
        excludedExtensions: [String] = [],
        changeKinds: [BridgeFileChangeKind] = [],
        reviewStates: [BridgeFileReviewState] = [],
        showHiddenFiles: Bool = false,
        showBinaryFiles: Bool = false,
        showLargeFiles: Bool = false
    ) {
        self.includedPathGlobs = includedPathGlobs
        self.excludedPathGlobs = excludedPathGlobs
        self.includedFileClasses = includedFileClasses
        self.excludedFileClasses = excludedFileClasses
        self.includedExtensions = includedExtensions
        self.excludedExtensions = excludedExtensions
        self.changeKinds = changeKinds
        self.reviewStates = reviewStates
        self.showHiddenFiles = showHiddenFiles
        self.showBinaryFiles = showBinaryFiles
        self.showLargeFiles = showLargeFiles
    }
}
