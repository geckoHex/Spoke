import SwiftUI

enum RideStartButton: Hashable {
    case home, ride, pause
}

struct RideStartButtonPreference: PreferenceKey {
    static var defaultValue: [RideStartButton: Anchor<CGRect>] { [:] }

    static func reduce(
        value: inout [RideStartButton: Anchor<CGRect>],
        nextValue: () -> [RideStartButton: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct RideStartTransition: View {
    let destinationFrame: CGRect?
    let onCovered: () -> Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var sourceFrame: CGRect
    @State private var phase = Phase.button

    private enum Phase { case button, covered, pause }

    init(
        sourceFrame: CGRect,
        destinationFrame: CGRect?,
        onCovered: @escaping () -> Bool,
        onFinished: @escaping () -> Void
    ) {
        _sourceFrame = State(initialValue: sourceFrame)
        self.destinationFrame = destinationFrame
        self.onCovered = onCovered
        self.onFinished = onFinished
    }

    private var reduceMotion: Bool {
        systemReduceMotion || (ProcessInfo.processInfo.arguments.contains("--ui-testing")
            && ProcessInfo.processInfo.arguments.contains("--reduce-motion"))
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = CGRect(origin: .zero, size: proxy.size)
            let diameter = hypot(screen.width, screen.height) + 2
            let cover = CGRect(
                x: screen.midX - diameter / 2, y: screen.midY - diameter / 2,
                width: diameter, height: diameter
            )
            let button = phase == .pause ? (destinationFrame ?? sourceFrame) : sourceFrame
            let frame = reduceMotion ? screen : (phase == .covered ? cover : button)

            RoundedRectangle(cornerRadius: reduceMotion ? 0 : min(frame.width, frame.height) / 2)
                .fill(SpokeStyle.primaryAction)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .opacity(reduceMotion && phase != .covered ? 0 : 1)
        }
        .clipped()
        .accessibilityHidden(true)
        .task {
            do {
                await Task.yield()
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3)) {
                    phase = .covered
                }
                try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.3))
                guard onCovered() else {
                    onFinished()
                    return
                }
                try await Task.sleep(for: .seconds(0.15))
                withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.35)) {
                    phase = .pause
                }
                try await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 0.35))
                onFinished()
            } catch {
                // Removing the overlay cancels the sequence when the app backgrounds.
            }
        }
    }
}
