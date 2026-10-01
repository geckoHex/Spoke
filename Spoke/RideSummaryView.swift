//
//  RideSummaryView.swift
//  Spoke
//

import SwiftUI

struct RideSummaryView: View {
    let ride: TrackedRide
    let onDone: () -> Void
    let onDiscard: () -> Void

    @State private var isConfirmingDiscard = false

    var body: some View {
        SpokeSheet(title: "Ride Complete") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duration")
                        .font(.subheadline)
                        .foregroundStyle(SpokeStyle.secondaryText)

                    Text(RideMetrics.duration(ride.elapsedDuration()))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }

                HStack(alignment: .top, spacing: 24) {
                    summaryItem(
                        title: "Distance",
                        value: RideMetrics.distance(RideMetrics.distanceInMeters(for: ride))
                    )
                    summaryItem(
                        title: "Started",
                        value: ride.startedAt.formatted(date: .omitted, time: .shortened)
                    )
                }

                VStack(spacing: 8) {
                    Button("Done", action: onDone)
                        .buttonStyle(SpokePrimaryButtonStyle())

                    Button("Discard Ride", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                    .buttonStyle(SpokeSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.vertical, 12)
        }
        .sheet(isPresented: $isConfirmingDiscard) {
            SpokeConfirmationView(
                title: "Discard Ride?",
                message: "This ride will be permanently deleted.",
                actionTitle: "Discard",
                onConfirm: onDiscard
            )
        }
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(SpokeStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
