import SwiftUI

struct RemoteImageIconView: View {
    let url: URL?
    let systemImage: String
    let tint: Color
    var padding: CGFloat = 10

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty, .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .padding(padding)
            .foregroundStyle(tint)
    }
}
