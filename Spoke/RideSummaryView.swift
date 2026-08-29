//
//  RideSummaryView.swift
//  Spoke
//

import SwiftUI
import UIKit

struct RideSummaryView: View {
    let ride: TrackedRide
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Ride Complete")
                            .font(.title2.weight(.semibold))

                        Text(RideMetrics.duration(ride.elapsedDuration()))
                            .font(.largeTitle.weight(.semibold))
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

                    Spacer(minLength: 0)

                    Button("Done") {
                        onDone()
                    }
                    .buttonStyle(SpokePrimaryButtonStyle())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(Color(uiColor: .secondarySystemBackground))
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
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
