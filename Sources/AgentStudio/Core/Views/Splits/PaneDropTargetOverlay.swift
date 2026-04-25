import SwiftUI

/// Renders a single split drop target overlay in tab-container coordinates.
struct PaneDropTargetOverlay: View {
    let target: PaneDropTarget?
    let paneFrames: [UUID: CGRect]
    var debugOptions: AgentStudioDragDebugOptions = .fromEnvironment()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if debugOptions.showsDestinations {
                ForEach(Self.debugDestinations(for: paneFrames)) { destination in
                    debugDestination(destination)
                }
            }

            if let target,
                let paneFrame = paneFrames[target.paneId]
            {
                let previewRect = target.zone.overlayRect(in: paneFrame)
                let markerRect = target.zone.markerRect(in: paneFrame)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: previewRect.width, height: previewRect.height)
                    .offset(x: previewRect.minX, y: previewRect.minY)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: markerRect.width, height: markerRect.height)
                    .offset(x: markerRect.minX, y: markerRect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func debugDestination(_ destination: DebugDestination) -> some View {
        let previewRect = destination.zone.overlayRect(in: destination.paneFrame)
        let markerRect = destination.zone.markerRect(in: destination.paneFrame)

        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.orange.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: previewRect.width, height: previewRect.height)
            .offset(x: previewRect.minX, y: previewRect.minY)

        Rectangle()
            .fill(Color.orange.opacity(0.36))
            .frame(width: markerRect.width, height: markerRect.height)
            .offset(x: markerRect.minX, y: markerRect.minY)

        Text("\(destination.paneId.uuidString.prefix(6)) \(destination.zone.rawValue)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 3))
            .offset(x: previewRect.minX + 6, y: previewRect.minY + 6)
    }

    static func debugDestinations(for paneFrames: [UUID: CGRect]) -> [DebugDestination] {
        paneFrames
            .flatMap { paneId, paneFrame in
                DropZone.allCases.map { zone in
                    DebugDestination(paneId: paneId, zone: zone, paneFrame: paneFrame)
                }
            }
            .sorted()
    }

    struct DebugDestination: Identifiable, Comparable, Equatable {
        let paneId: UUID
        let zone: DropZone
        let paneFrame: CGRect

        var id: String {
            "\(paneId.uuidString)-\(zone.rawValue)"
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.paneFrame.minY != rhs.paneFrame.minY {
                return lhs.paneFrame.minY < rhs.paneFrame.minY
            }
            if lhs.paneFrame.minX != rhs.paneFrame.minX {
                return lhs.paneFrame.minX < rhs.paneFrame.minX
            }
            if lhs.paneId != rhs.paneId {
                return lhs.paneId.uuidString < rhs.paneId.uuidString
            }
            return lhs.zone.rawValue < rhs.zone.rawValue
        }
    }
}
