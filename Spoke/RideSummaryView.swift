//
//  RideSummaryView.swift
//  Spoke
//

import SwiftUI

struct RideSummaryView: View {
    let ride: TrackedRide

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
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

                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: .capsule)
                    .buttonStyle(.plain)
                }
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
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
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
