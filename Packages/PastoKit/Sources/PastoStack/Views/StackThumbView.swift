import AppKit
import PastoCoreUI
import SwiftUI

/// The picture at the trailing edge of a card.
struct StackThumbView: View {
    let thumb: StackCardContent.Thumb

    var body: some View {
        switch thumb {
        case .color(let code):
            Color(.sRGB, red: code.red, green: code.green, blue: code.blue, opacity: code.alpha)
        case .symbol(let name):
            backdrop.overlay {
                Image(systemName: name)
                    .font(.system(size: StackMetrics.Card.thumbSymbolSize, weight: .medium))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        case .icon(let data):
            backdrop.overlay {
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: StackMetrics.Card.thumbIconSide, height: StackMetrics.Card.thumbIconSide)
                }
            }
        case .image(let data):
            backdrop.overlay {
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
        }
    }

    private var backdrop: Color {
        Color(nsColor: .quaternarySystemFill)
    }
}
