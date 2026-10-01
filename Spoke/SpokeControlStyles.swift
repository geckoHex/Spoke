import SwiftUI

enum SpokeStyle {
    static let background = Color.black
    static let surface = Color(white: 0.11)
    static let elevatedSurface = Color(white: 0.18)
    static let text = Color.white
    static let secondaryText = Color(white: 0.68)
    static let accent = Color.blue
    static let caution = Color.orange
    static let danger = Color.red
    static let separator = text.opacity(0.14)
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let pageInset: CGFloat = 20
}

extension View {
    func spokeCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                SpokeStyle.surface,
                in: RoundedRectangle(cornerRadius: SpokeStyle.cardRadius, style: .continuous)
            )
    }
}

struct SpokePrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 16)
            .background(
                .white,
                in: RoundedRectangle(cornerRadius: SpokeStyle.controlRadius, style: .continuous)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}

struct SpokeToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .frame(width: size, height: size)
            .background(.white, in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SpokeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(SpokeStyle.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
