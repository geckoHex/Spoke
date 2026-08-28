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
                    List(completedRides) { ride in
                        NavigationLink {
                            RideHistoryDetailView(ride: ride)
                        } label: {
                            RideHistoryRow(ride: ride)
                        }
                        .listRowBackground(Color.black)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct RideHistoryRow: View {
    let ride: TrackedRide

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ride.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                Label(
                    RideMetrics.duration(ride.elapsedDuration()),
                    systemImage: "timer"
                )

                Label(
                    RideMetrics.distance(RideMetrics.distanceInMeters(for: ride)),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 8)
    }
}

private struct RideHistoryDetailView: View {
    let ride: TrackedRide

    @State private var isShowingSoundtrack = false

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
        .navigationTitle(
            ride.startedAt.formatted(date: .abbreviated, time: .omitted)
        )
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingSoundtrack) {
            RideSoundtrackView(ride: ride)
        }
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
