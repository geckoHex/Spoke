import Foundation
import AVFoundation
import SwiftUI
import UIKit

struct RideEmergencyCheckInState {
    private(set) var stoppedAt: Date?
    var isPresented = false

    mutating func observe(speedInMilesPerHour: Int, at date: Date) {
        if speedInMilesPerHour > 0 {
            stoppedAt = nil
        } else if stoppedAt == nil {
            stoppedAt = date
        }
    }

    mutating func evaluate(at date: Date, timeoutMinutes: Int) {
        guard !isPresented, let stoppedAt else { return }
        if date.timeIntervalSince(stoppedAt) > Double(min(max(timeoutMinutes, 1), 10) * 60) {
            isPresented = true
        }
    }

    mutating func dismiss(at date: Date) {
        isPresented = false
        if stoppedAt != nil { stoppedAt = date }
    }
}

struct DeveloperCheckInGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    let onTrigger: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let gesture = UILongPressGestureRecognizer()
        gesture.numberOfTouchesRequired = 3
        gesture.minimumPressDuration = 1
        gesture.cancelsTouchesInView = false
        gesture.delegate = context.coordinator
        gesture.isEnabled = isEnabled
        return gesture
    }

    func updateUIGestureRecognizer(_ gesture: UILongPressGestureRecognizer, context: Context) {
        gesture.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ gesture: UILongPressGestureRecognizer, context: Context) {
        if isEnabled && gesture.state == .began { onTrigger() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

struct RideEmergencyCheckInView: View {
    let onOkay: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var alerts = RideEmergencyAlerts()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 28) {
                Spacer(minLength: 0)

                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: min(140, geometry.size.height * 0.28), weight: .bold))
                    .accessibilityHidden(true)

                Text("Are you okay")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 16) {
                    Button("I'm Okay") {
                        alerts.stop()
                        onOkay()
                    }
                    Button("HELP") {
                        // Intentionally a no-op: never contact anyone or initiate an emergency.
                    }
                }
                .font(.title3.bold())
                .buttonStyle(CheckInButtonStyle())
                .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.9, green: 0, blue: 0).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .statusBarHidden()
        .task(id: scenePhase) {
            guard scenePhase == .active else { alerts.stop(); return }
            await alerts.runAudio()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await alerts.runPhysicalAlerts()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            Task { await alerts.restoreSpeaker() }
        }
        .onDisappear { alerts.stop() }
    }
}

private struct CheckInButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(.white, in: RoundedRectangle(cornerRadius: SpokeStyle.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
