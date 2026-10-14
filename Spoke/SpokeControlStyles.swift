import SwiftUI

enum SpokeStyle {
    static let background = Color.black
    static let surface = Color(white: 20 / 255)
    static let elevatedSurface = Color(white: 40 / 255)
    static let text = Color.white
    static let secondaryText = Color(white: 184 / 255)
    static let primaryAction = Color.white
    static let onPrimaryAction = Color.black
    static let accent = Color.white
    static let caution = Color(red: 255 / 255, green: 200 / 255, blue: 87 / 255)
    static let danger = Color(red: 1, green: 85 / 255, blue: 74 / 255)
    static let separator = Color(white: 56 / 255)
    static let cardRadius: CGFloat = 4
    static let controlRadius: CGFloat = 4
    static let pageInset: CGFloat = 20
}

struct SpokePrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(SpokeStyle.onPrimaryAction)
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.horizontal, 16)
            .background(
                SpokeStyle.primaryAction,
                in: .rect(cornerRadius: SpokeStyle.controlRadius)
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
            .contentShape(.rect)
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
            .contentShape(.rect)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
