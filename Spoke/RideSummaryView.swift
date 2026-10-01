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
        NavigationStack {
            ZStack {
                SpokeStyle.surface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 14) {
                            Image(systemName: "flag.pattern.checkered.2.crossed")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(SpokeStyle.text)
                                .frame(width: 48, height: 48)
                                .background(
                                    .white.opacity(0.1),
                                    in: Circle()
                                )
                                .accessibilityHidden(true)

                            Text("Ride Complete")
                                .font(.title2.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Duration")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SpokeStyle.secondaryText)

                                Text(RideMetrics.duration(ride.elapsedDuration()))
                                    .font(.system(size: 48, weight: .bold))
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.75)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)

                            Divider()
                                .overlay(SpokeStyle.separator)

                            HStack(spacing: 0) {
                                summaryItem(
                                    title: "Distance",
                                    value: RideMetrics.distance(
                                        RideMetrics.distanceInMeters(for: ride)
                                    )
                                )

                                Divider()
                                    .overlay(SpokeStyle.separator)

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
                            SpokeStyle.elevatedSurface,
                            in: RoundedRectangle(cornerRadius: SpokeStyle.cardRadius, style: .continuous)
                        )
                        .padding(.top, 24)

                        VStack(spacing: 12) {
                            Button("Done", action: onDone)
                                .buttonStyle(SpokePrimaryButtonStyle())

                            Button(role: .destructive) {
                                isConfirmingDiscard = true
                            } label: {
                                Label("Discard", systemImage: "trash")
                            }
                            .buttonStyle(SpokeSecondaryButtonStyle())
                        }
                        .padding(.top, 24)
                    }
                    .foregroundStyle(SpokeStyle.text)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(SpokeStyle.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
    }
}
