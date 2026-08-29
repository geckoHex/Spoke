//
//  HistoryView.swift
//  Spoke
//

import MapKit
import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Query(sort: \TrackedRide.startedAt, order: .reverse)
    private var rides: [TrackedRide]
    @Binding private var highlightedRideID: PersistentIdentifier?

    init(
        highlightedRideID: Binding<PersistentIdentifier?> = .constant(nil)
    ) {
        _highlightedRideID = highlightedRideID
    }

    private var completedRides: [TrackedRide] {
        rides.filter { $0.endedAt != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if completedRides.isEmpty {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "figure.outdoor.cycle",
                        description: Text("Completed rides will appear here.")
                    )
                    .background(Color.black)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(completedRides) { ride in
                                NavigationLink {
                                    RideHistoryDetailView(ride: ride)
                                } label: {
                                    RideHistoryRow(
                                        ride: ride,
                                        isHighlighted:
                                            ride.persistentModelID == highlightedRideID
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .background(Color.black)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
        .task(id: highlightedRideID) {
            guard highlightedRideID != nil else { return }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            withAnimation(.easeOut(duration: 0.45)) {
                highlightedRideID = nil
            }
        }
    }
}

private struct RideHistoryRow: View {
    let ride: TrackedRide
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ride.historyTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                    Text(ride.startedAt, format: .dateTime.hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 20) {
                metric(
                    title: "Duration",
                    value: RideMetrics.duration(ride.elapsedDuration()),
                    systemImage: "timer"
                )

                metric(
                    title: "Distance",
                    value: RideMetrics.distance(
                        RideMetrics.distanceInMeters(for: ride)
                    ),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white.opacity(isHighlighted ? 0.14 : 0.075),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func metric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RideHistoryDetailView: View {
    let ride: TrackedRide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var rideName = ""
    @State private var isShowingRenamePrompt = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingSoundtrack = false

    private var trimmedRideName: String {
        rideName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        ride.routePoints
            .sorted { $0.recordedAt < $1.recordedAt }
            .map {
                CLLocationCoordinate2D(
                    latitude: $0.latitude,
                    longitude: $0.longitude
                )
            }
    }

    private var cameraPosition: MapCameraPosition {
        guard !coordinates.isEmpty else { return .automatic }

        let rect = coordinates.reduce(MKMapRect.null) { partialResult, coordinate in
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            return partialResult.union(pointRect)
        }
        let horizontalPadding = max(rect.size.width * 0.18, 500)
        let verticalPadding = max(rect.size.height * 0.18, 500)
        return .rect(
            rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        )
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if coordinates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.system(size: 34, weight: .medium))

                        Text("No route recorded")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Map(initialPosition: cameraPosition) {
                        if coordinates.count > 1 {
                            MapPolyline(coordinates: coordinates)
                                .stroke(.white, lineWidth: 5)
                        } else if let coordinate = coordinates.first {
                            Annotation("Ride location", coordinate: coordinate) {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 12, height: 12)
                                    .overlay {
                                        Circle()
                                            .stroke(.black, lineWidth: 2)
                                    }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                HStack(spacing: 12) {
                    metric(
                        title: "Duration",
                        value: RideMetrics.duration(ride.elapsedDuration())
                    )

                    metric(
                        title: "Distance",
                        value: RideMetrics.distance(
                            RideMetrics.distanceInMeters(for: ride)
                        )
                    )
                }
                .frame(height: 72)

                Button("Ride soundtrack") {
                    isShowingSoundtrack = true
                }
                .buttonStyle(SpokePrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .navigationTitle(ride.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        rideName = ride.customName ?? ride.detailTitle
                        isShowingRenamePrompt = true
                    } label: {
                        Label("Rename Ride", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("Delete Ride", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Ride actions")
            }
        }
        .sheet(isPresented: $isShowingSoundtrack) {
            RideSoundtrackView(ride: ride)
        }
        .alert("Rename Ride", isPresented: $isShowingRenamePrompt) {
            TextField("", text: $rideName)
                .accessibilityLabel("Ride name")
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit {
                    guard !trimmedRideName.isEmpty else { return }
                    renameRide()
                    isShowingRenamePrompt = false
                }

            Button("Cancel", role: .cancel) {}
            Button("Save") {
                renameRide()
            }
            .disabled(trimmedRideName.isEmpty)
        } message: {
            Text("Ride name")
        }
        .alert("Delete Ride?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteRide()
            }
        } message: {
            Text("This ride and its soundtrack will be permanently deleted.")
        }
    }

    private func renameRide() {
        ride.rename(to: trimmedRideName)
        try? modelContext.save()
    }

    private func deleteRide() {
        modelContext.delete(ride)
        try? modelContext.save()
        dismiss()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.headline)
                .monospacedDigit()

            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension TrackedRide {
    var historyTitle: String {
        customName ?? startedAt.formatted(
            .dateTime
                .weekday(.wide)
                .month(.abbreviated)
                .day()
        )
    }

    var detailTitle: String {
        customName ?? startedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct RideSoundtrackView: View {
    let ride: TrackedRide

    private var entries: [RideSoundtrackEntry] {
        ride.soundtrackEntries.sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Songs Recorded",
                        systemImage: "music.note.list",
                        description: Text("Songs played during this ride will appear here.")
                    )
                    .background(Color.black)
                } else {
                    List(entries) { entry in
                        RideSoundtrackRow(entry: entry)
                            .listRowBackground(Color.black)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
            .navigationTitle("Ride soundtrack")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .presentationDragIndicator(.visible)
    }
}

private struct RideSoundtrackRow: View {
    let entry: RideSoundtrackEntry

    var body: some View {
        HStack(spacing: 12) {
            albumArt

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedStartTime)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var albumArt: some View {
        Group {
            if let albumArtData = entry.albumArtData,
               let image = UIImage(data: albumArtData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: entry.albumArtURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        albumArtPlaceholder
                    }
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var albumArtPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.12)

            Image(systemName: "music.note")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        }
    }

    private var formattedStartTime: String {
        Self.timeFormatter.string(from: entry.startedAt).lowercased()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

#Preview {
    HistoryView()
        .modelContainer(
            for: [TrackedRide.self, RideRoutePoint.self, RideSoundtrackEntry.self],
            inMemory: true
        )
        .preferredColorScheme(.dark)
}
