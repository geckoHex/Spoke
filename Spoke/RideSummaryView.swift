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

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(.white, in: Circle())

                        Text("Ride Complete")
                            .font(.title2.weight(.bold))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Duration")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            Text(RideMetrics.duration(ride.elapsedDuration()))
                                .font(.system(size: 50, weight: .semibold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.75)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)

                        Divider()
                            .overlay(.white.opacity(0.12))

                        HStack(spacing: 0) {
                            summaryItem(
                                title: "Distance",
                                value: RideMetrics.distance(
                                    RideMetrics.distanceInMeters(for: ride)
                                )
                            )

                            Divider()
                                .overlay(.white.opacity(0.12))

                            summaryItem(
                                title: "Started",
                                value: ride.startedAt.formatted(
                                    date: .omitted,
                                    time: .shortened
                                )
                            )
                        }
                        .frame(height: 88)
                    }
                    .background(
                        .black.opacity(0.28),
                        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                    )
                    .padding(.top, 24)

                    Spacer(minLength: 0)

                    Button("Done") {
                        onDone()
                    }
                    .buttonStyle(SpokePrimaryButtonStyle())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(Color(uiColor: .secondarySystemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func summaryItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }
}
