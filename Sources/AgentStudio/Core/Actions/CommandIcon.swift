import AppKit
import SwiftUI

enum SystemSymbol: String, CaseIterable, Equatable, Sendable {
    case arrowDown = "arrow.down"
    case arrowDownToLine = "arrow.down.to.line"
    case arrowClockwise = "arrow.clockwise"
    case arrowLeft = "arrow.left"
    case arrowLeftAndRightSquare = "arrow.left.and.right.square"
    case arrowLeftCircle = "arrow.left.circle"
    case arrowRight = "arrow.right"
    case arrowRightCircle = "arrow.right.circle"
    case arrowTriangleBranch = "arrow.triangle.branch"
    case arrowUp = "arrow.up"
    case arrowUpLeftAndArrowDownRight = "arrow.up.left.and.arrow.down.right"
    case arrowUpArrowDown = "arrow.up.arrow.down"
    case arrowUpRightSquare = "arrow.up.right.square"
    case arrowUturnBackward = "arrow.uturn.backward"
    case bell = "bell"
    case bellBadge = "bell.badge"
    case bookmark = "bookmark"
    case bookmarkFill = "bookmark.fill"
    case checkmarkCircle = "checkmark.circle"
    case chevronDown = "chevron.down"
    case chevronLeft = "chevron.left"
    case chevronLeftForwardslashChevronRight = "chevron.left.forwardslash.chevron.right"
    case chevronRight = "chevron.right"
    case chevronUpChevronDown = "chevron.up.chevron.down"
    case command = "command"
    case deleteLeft = "delete.left"
    case docOnClipboard = "doc.on.clipboard"
    case docText = "doc.text"
    case dotCircleViewfinder = "dot.circle.viewfinder"
    case ellipsisCircle = "ellipsis.circle"
    case envelopeBadge = "envelope.badge"
    case equalSquare = "equal.square"
    case eye = "eye"
    case eyeSlash = "eye.slash"
    case filemenuAndPointerArrow = "filemenu.and.pointer.arrow"
    case finder = "finder"
    case folder = "folder"
    case folderBadgeMinus = "folder.badge.minus"
    case folderFillBadgePlus = "folder.fill.badge.plus"
    case globe = "globe"
    case house = "house"
    case line3Horizontal = "line.3.horizontal"
    case longTextPageAndPencil = "long.text.page.and.pencil"
    case macwindowBadgePlus = "macwindow.badge.plus"
    case magnifyingglass = "magnifyingglass"
    case minusCircle = "minus.circle"
    case paintpalette = "paintpalette"
    case paintpaletteFill = "paintpalette.fill"
    case pencil = "pencil"
    case personBadgeKey = "person.badge.key"
    case plus = "plus"
    case plusCircle = "plus.circle"
    case plusMagnifyingglass = "plus.magnifyingglass"
    case plusRectangle = "plus.rectangle"
    case plusSquare = "plus.square"
    case rectangle3Group = "rectangle.3.group"
    case rectangle3GroupBubble = "rectangle.3.group.bubble"
    case rectangle3GroupFill = "rectangle.3.group.fill"
    case rectangleGrid1x3 = "rectangle.grid.1x3"
    case rectangleBottomhalfFilled = "rectangle.bottomhalf.filled"
    case rectangleBottomhalfInsetFilled = "rectangle.bottomhalf.inset.filled"
    case rectangleExpandVertical = "rectangle.expand.vertical"
    case rectanglePortraitAndArrowRight = "rectangle.portrait.and.arrow.right"
    case rectangleSplit1x2 = "rectangle.split.1x2"
    case rectangleSplit2x1 = "rectangle.split.2x1"
    case rectangleSplit2x2 = "rectangle.split.2x2"
    case rectangleSplit2x2Fill = "rectangle.split.2x2.fill"
    case rectangleSplit3x1 = "rectangle.split.3x1"
    case rectangleStack = "rectangle.stack"
    case scope = "scope"
    case sidebarLeft = "sidebar.left"
    case squareStack3dUp = "square.stack.3d.up"
    case star = "star"
    case starFill = "star.fill"
    case terminal = "terminal"
    case terminalFill = "terminal.fill"
    case trash = "trash"
    case trashFill = "trash.fill"
    case xmark = "xmark"
    case xmarkCircle = "xmark.circle"
    case xmarkCircleFill = "xmark.circle.fill"
    case xmarkRectangle = "xmark.rectangle"
    case xmarkRectanglePortrait = "xmark.rectangle.portrait"
    case xmarkSquare = "xmark.square"
}

enum OcticonSymbol: String, CaseIterable, Equatable, Sendable {
    case codeSquare = "octicon-code-square"
    case vscode = "octicon-vscode"
}

enum CommandIcon: Equatable, Sendable {
    case system(SystemSymbol)
    case octicon(OcticonSymbol)
}

extension CommandIcon {
    @ViewBuilder
    func swiftUIImage(size: CGFloat? = nil) -> some View {
        switch self {
        case .system(let systemSymbol):
            let image = Image(systemName: systemSymbol.rawValue)
            if let size {
                image
                    .font(.system(size: size, weight: .medium))
            } else {
                image
            }
        case .octicon(let octiconSymbol):
            OcticonImage(name: octiconSymbol.rawValue, size: size ?? 16)
        }
    }

    func nsImage(accessibilityDescription: String?) -> NSImage? {
        switch self {
        case .system(let systemSymbol):
            NSImage(
                systemSymbolName: systemSymbol.rawValue,
                accessibilityDescription: accessibilityDescription
            )
        case .octicon:
            nil
        }
    }
}
