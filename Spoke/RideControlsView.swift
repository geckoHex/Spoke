import SwiftUI

struct RideControlsView: View {
    let ride: TrackedRide
    let onPauseToggle: () -> Void
    let onEnd: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Button(action: onPauseToggle) {
                Label(ride.isPaused ? "Resume" : "Pause", systemImage: ride.isPaused ? "play.fill" : "pause.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(SpokePrimaryButtonStyle(minHeight: 64))
            .accessibilityLabel(ride.isPaused ? "Resume Ride" : "Pause Ride")

            Label(isHolding ? "Keep holding" : "Hold to end", systemImage: "stop.fill")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(SpokeStyle.clay)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, 12)
                .background {
                    GeometryReader { proxy in
                        SpokeStyle.clay.opacity(0.2)
                            .frame(width: proxy.size.width * holdProgress)
                    }
                }
                .background(SpokeStyle.surface)
                .clipShape(.rect(cornerRadius: SpokeStyle.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SpokeStyle.controlRadius)
                        .strokeBorder(SpokeStyle.clay, lineWidth: 1.5)
                }
                .contentShape(.rect)
                .onLongPressGesture(minimumDuration: 1, maximumDistance: 32) {
                    isHolding = false
                    holdProgress = 0
                    onEnd()
                } onPressingChanged: { pressing in
                    isHolding = pressing
                    withAnimation(reduceMotion ? nil : .linear(duration: pressing ? 1 : 0.15)) {
                        holdProgress = pressing ? 1 : 0
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("End Ride")
                .accessibilityHint("Hold for one second to finish. With VoiceOver, double-tap to finish.")
                .accessibilityAction { onEnd() }
        }
        .onDisappear {
            isHolding = false
            holdProgress = 0
        }
    }
}
