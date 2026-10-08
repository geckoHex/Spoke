import SwiftUI

enum SpokeStyle {
    static let background = Color(red: 23 / 255, green: 28 / 255, blue: 24 / 255)
    static let surface = Color(red: 37 / 255, green: 45 / 255, blue: 38 / 255)
    static let elevatedSurface = Color(red: 49 / 255, green: 59 / 255, blue: 49 / 255)
    static let text = Color(red: 243 / 255, green: 238 / 255, blue: 221 / 255)
    static let secondaryText = Color(red: 184 / 255, green: 193 / 255, blue: 173 / 255)
    static let accent = Color(red: 196 / 255, green: 214 / 255, blue: 160 / 255)
    static let caution = Color(red: 230 / 255, green: 199 / 255, blue: 121 / 255)
    static let danger = Color(red: 218 / 255, green: 155 / 255, blue: 121 / 255)
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
            .overlay {
                RoundedRectangle(cornerRadius: SpokeStyle.cardRadius, style: .continuous)
                    .strokeBorder(SpokeStyle.text.opacity(0.05), lineWidth: 0.5)
            }
    }
}

struct SpokePrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(SpokeStyle.background)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 16)
            .background(
                configuration.role == .destructive ? SpokeStyle.danger : SpokeStyle.accent,
                in: Capsule()
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct SpokeToolbarButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(SpokeStyle.text)
            .frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SpokeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(configuration.role == .destructive ? SpokeStyle.danger : SpokeStyle.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16)
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
