//
//  HomeView.swift
//  Spoke
//

import SwiftUI

struct HomeView: View {
    let settings: AppSettings?
    let rideSession: RideSessionController

    @State private var completedRide: TrackedRide?

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let currentDate = max(context.date, Date.now)

                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 20) {
                        Text(greeting(at: currentDate))
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)

                        Spacer()

                        if let ride = rideSession.activeRide {
                            ActiveRideControl(
                                ride: ride,
                                date: currentDate,
                                onPauseToggle: {
                                    rideSession.togglePause()
                                },
                                onEnd: endRide
                            )
                        } else {
                            Button("Start Ride") {
                                rideSession.startRide()
                            }
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white, in: .capsule)
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }
            }
        }
        .sheet(isPresented: isShowingSummary) {
            if let completedRide {
                RideSummaryView(
                    ride: completedRide,
                    onDone: {
                        self.completedRide = nil
                    }
                )
            }
        }
    }

    private var isShowingSummary: Binding<Bool> {
        Binding(
            get: { completedRide != nil },
            set: { isPresented in
                if !isPresented {
                    completedRide = nil
                }
            }
        )
    }

    private func endRide() {
        completedRide = rideSession.endRide()
    }

    private func greeting(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let salutation = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }

        let trimmedName = settings?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? "User"
        return "\(salutation), \(name)"
    }
}

private struct ActiveRideControl: View {
    let ride: TrackedRide
    let date: Date
    let onPauseToggle: () -> Void
    let onEnd: () -> Void

    @State private var isPressing = false
    @State private var holdProgress: CGFloat = 0
    @State private var holdTask: Task<Void, Never>?

    private let holdDuration = 1.5

    var body: some View {
        let elapsedSeconds = max(
            Int(ride.elapsedDuration(at: date).rounded(.down)),
            0
        )

        HStack(spacing: 12) {
            timer(elapsedSeconds: elapsedSeconds)

            Button {
                onPauseToggle()
            } label: {
                Image(systemName: ride.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 56, height: 56)
                    .background(.white, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ride.isPaused ? "Resume Ride" : "Pause Ride")
        }
        .onDisappear {
            holdTask?.cancel()
        }
    }

    private func timer(elapsedSeconds: Int) -> some View {
        ZStack {
            Capsule()
                .fill(.white)

            GeometryReader { proxy in
                Rectangle()
                    .fill(.black.opacity(0.18))
                    .frame(width: proxy.size.width * holdProgress)
                    .frame(maxHeight: .infinity)
            }
            .clipShape(Capsule())

            Text(RideMetrics.duration(TimeInterval(elapsedSeconds)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.black)
                .contentTransition(.numericText(value: Double(elapsedSeconds)))
                .animation(
                    ride.isPaused ? nil : .snappy(duration: 0.35),
                    value: elapsedSeconds
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    beginPressIfNeeded()
                }
                .onEnded { _ in
                    finishPress()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Ride timer")
        .accessibilityValue(
            "\(RideMetrics.duration(TimeInterval(elapsedSeconds))), "
                + (ride.isPaused ? "paused" : "running")
        )
        .accessibilityHint("Hold to end the ride.")
        .accessibilityAction(named: "End Ride") {
            onEnd()
        }
    }

    private func beginPressIfNeeded() {
        guard !isPressing else { return }

        holdTask?.cancel()
        isPressing = true
        holdProgress = 0

        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1
        }

        holdTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(holdDuration))
            } catch {
                return
            }

            guard isPressing else { return }
            isPressing = false
            onEnd()

            withAnimation(.easeOut(duration: 0.15)) {
                holdProgress = 0
            }
        }
    }

    private func finishPress() {
        guard isPressing else { return }

        isPressing = false
        holdTask?.cancel()
        holdTask = nil

        withAnimation(.easeOut(duration: 0.15)) {
            holdProgress = 0
        }
    }
}

#Preview {
    HomeView(
        settings: AppSettings(),
        rideSession: RideSessionController()
    )
        .preferredColorScheme(.dark)
}
