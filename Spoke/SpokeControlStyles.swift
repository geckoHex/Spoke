import SwiftUI

struct SpokeToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .frame(width: 44, height: 44)
            .background(.white, in: Circle())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SpokeToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                    .foregroundStyle(.white)
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Color.blue : Color(white: 0.25))
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 27, height: 27)
                            .padding(2)
                    }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
            .toggleStyle(.switch)
        }
    }
}
