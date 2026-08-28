//
//  RideSummaryView.swift
//  Spoke
//

import SwiftUI

struct RideSummaryView: View {
    let ride: TrackedRide
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("Ride Complete")
                            .font(.title2.weight(.semibold))

                        Text(RideMetrics.duration(ride.elapsedDuration()))
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }

                    HStack(spacing: 12) {
                        summaryItem(
                            title: "Distance",
                            value: RideMetrics.distance(
                                RideMetrics.distanceInMeters(for: ride)
                            )
                        )

                        summaryItem(
                            title: "Started",
                            value: ride.startedAt.formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        )
                    }

                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.black, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.black)
                .padding(24)
            }
        }
        .preferredColorScheme(.light)
        .presentationBackground(.white)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.black.opacity(0.06), in: .rect(cornerRadius: 20))
    }
}
