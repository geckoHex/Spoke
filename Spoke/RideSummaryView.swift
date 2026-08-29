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
                Color.white
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.black)
                            .accessibilityHidden(true)

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
                        .padding(20)

                        Divider()
                            .overlay(.black.opacity(0.08))

                        HStack(spacing: 0) {
                            summaryItem(
                                title: "Distance",
                                value: RideMetrics.distance(
                                    RideMetrics.distanceInMeters(for: ride)
                                )
                            )

                            Divider()
                                .overlay(.black.opacity(0.08))

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
                        Color(uiColor: .systemGray6),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .padding(.top, 20)

                    Spacer(minLength: 0)

                    Button(action: onDone) {
                        Text("Done")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .background(
                                .black,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.light)
        .presentationBackground(.white)
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
