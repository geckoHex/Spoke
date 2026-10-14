import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            RideActivityLockScreenView(context: context)
                .activityBackgroundTint(RideActivityStyle.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Spoke", systemImage: "bicycle")
                        .font(.headline)
                        .foregroundStyle(RideActivityStyle.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPaused ? "Paused" : "Riding")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(RideActivityStyle.secondaryText)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 12) {
                        RideActivityStats(state: context.state, isStale: context.isStale)
                        RideActivityPauseButton(context: context)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "bicycle")
                    .foregroundStyle(RideActivityStyle.accent)
                    .accessibilityLabel(context.state.isPaused ? "Ride paused" : "Ride in progress")
            } compactTrailing: {
                RideActivityTimer(state: context.state)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "bicycle")
                    .foregroundStyle(RideActivityStyle.accent)
                    .accessibilityLabel(context.state.isPaused ? "Ride paused" : "Ride in progress")
            }
            .keylineTint(RideActivityStyle.accent)
        }
    }
}

private struct RideActivityLockScreenView: View {
    let context: ActivityViewContext<RideActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Spoke", systemImage: "bicycle")
                        .font(.headline)
                    Text(context.state.isPaused ? "Ride paused" : "Ride in progress")
                        .font(.caption)
                        .foregroundStyle(RideActivityStyle.secondaryText)
                }
                Spacer(minLength: 0)
                RideActivityPauseButton(context: context)
            }
            RideActivityStats(state: context.state, isStale: context.isStale)
        }
        .padding(16)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct RideActivityStats: View {
    let state: RideActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            metric("Time") {
                RideActivityTimer(state: state)
            }
            metric("Distance · mi") {
                Text(state.distanceInMiles, format: .number.precision(.fractionLength(1)))
            }
            metric("Speed · mph") {
                if let speed = state.speedInMilesPerHour, !isStale || state.isPaused {
                    Text(speed, format: .number)
                } else {
                    Text("—")
                        .accessibilityLabel("Speed unavailable")
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func metric<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(RideActivityStyle.secondaryText)
            value()
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RideActivityTimer: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Text(Duration.seconds(state.elapsedDuration.rounded(.down)), format: .time(pattern: .hourMinuteSecond))
            } else {
                Text(
                    timerInterval: state.timerStartDate...Date.distantFuture,
                    countsDown: false,
                    showsHours: true
                )
                .multilineTextAlignment(.leading)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }
}

private struct RideActivityPauseButton: View {
    let context: ActivityViewContext<RideActivityAttributes>

    var body: some View {
        Button(intent: SetRidePausedIntent(
            rideID: context.attributes.rideID,
            isPaused: !context.state.isPaused
        )) {
            Label(
                context.state.isPaused ? "Resume" : "Pause",
                systemImage: context.state.isPaused ? "play.fill" : "pause.fill"
            )
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .foregroundStyle(.black)
            .background(RideActivityStyle.primaryAction, in: .rect(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(context.state.isPaused ? "Resume ride" : "Pause ride")
    }
}

private enum RideActivityStyle {
    static let background = Color.black
    static let secondaryText = Color(white: 184 / 255)
    static let primaryAction = Color.white
    static let accent = Color.white
}

#Preview("Riding", as: .content, using: RideActivityAttributes(rideID: "preview")) {
    RideLiveActivity()
} contentStates: {
    RideActivityAttributes.ContentState(
        timerStartDate: .now.addingTimeInterval(-1_245),
        elapsedDuration: 1_245,
        distanceInMiles: 4.8,
        speedInMilesPerHour: 16,
        isPaused: false
    )
    RideActivityAttributes.ContentState(
        timerStartDate: .now.addingTimeInterval(-1_245),
        elapsedDuration: 1_245,
        distanceInMiles: 4.8,
        speedInMilesPerHour: 0,
        isPaused: true
    )
}
