import SwiftUI

enum SpokeStyle {
    static let background = Color(white: 18 / 255)
    static let surface = Color(white: 28 / 255)
    static let elevatedSurface = Color(white: 42 / 255)
    static let text = Color.white
    static let secondaryText = Color(white: 184 / 255)
    static let primaryAction = Color(red: 235 / 255, green: 23 / 255, blue: 0)
    // Lighter red keeps small labels and icons legible on dark surfaces.
    static let accent = Color(red: 255 / 255, green: 111 / 255, blue: 92 / 255)
    static let success = Color(red: 104 / 255, green: 211 / 255, blue: 145 / 255)
    static let caution = Color(red: 255 / 255, green: 200 / 255, blue: 87 / 255)
    static let danger = Color(red: 255 / 255, green: 128 / 255, blue: 121 / 255)
    static let separator = Color(white: 56 / 255)
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
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
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 16)
            .background(
                SpokeStyle.primaryAction,
                in: Capsule()
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
    }
}

struct SpokeToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(SpokeStyle.text)
            .frame(width: size, height: size)
            .background(SpokeStyle.elevatedSurface, in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SpokeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(configuration.role == .destructive ? SpokeStyle.danger : SpokeStyle.text)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(SpokeStyle.elevatedSurface, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
