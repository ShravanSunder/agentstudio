import SwiftUI

package struct OcticonImage: View {
    package let name: String
    package let size: CGFloat
    package let loader: OcticonLoader

    package init(name: String, size: CGFloat, loader: OcticonLoader) {
        self.name = name
        self.size = size
        self.loader = loader
    }

    package var body: some View {
        Group {
            if let image = loader.image(named: name) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
}
