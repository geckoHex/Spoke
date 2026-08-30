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
    @State private var relativeTimeSnapshot = Date.now

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
                        LazyVStack(spacing: 12) {
                            ForEach(completedRides) { ride in
                                NavigationLink {
                                    RideHistoryDetailView(ride: ride)
                                } label: {
                                    RideHistoryRow(
                                        ride: ride,
                                        currentDate: relativeTimeSnapshot,
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
        .onAppear {
            relativeTimeSnapshot = .now
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
    let currentDate: Date
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ride.historyTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .layoutPriority(1)

                    Text(
                        RideMetrics.ageDescription(
                            since: ride.endedAt ?? ride.startedAt,
                            relativeTo: currentDate
                        )
                    )
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }

                HStack(spacing: 16) {
                    metric(
                        title: "Duration",
                        value: RideMetrics.unpaddedDuration(
                            ride.elapsedDuration()
                        ),
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
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
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
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct RideHistoryDetailView: View {
    let ride: TrackedRide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var rideName = ""
    @State private var isShowingNoteEditor = false
    @State private var isShowingRenamePrompt = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingSoundtrack = false
    @State private var isShowingReplay = false

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

    private var routeSegments: [RideRouteSegment] {
        RideRouteSpeed.segments(for: ride.routePoints)
    }

    private var routeStops: [RideRouteStop] {
        RideRouteSpeed.stops(for: ride.routePoints)
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
                            ForEach(Array(routeSegments.enumerated()), id: \.offset) {
                                _, segment in
                                MapPolyline(coordinates: segment.coordinates)
                                    .stroke(segment.motion.color, lineWidth: 5)
                            }

                            ForEach(routeStops) { stop in
                                Annotation(
                                    "Stopped (\(stop.durationDescription))",
                                    coordinate: stop.coordinate,
                                    anchor: .bottom
                                ) {
                                    RideStopBubble(
                                        durationDescription: stop.durationDescription
                                    )
                                }
                            }
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
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            isShowingReplay = true
                        } label: {
                            Label("Replay", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(.white, in: Capsule())
                                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    metric(
                        title: "Duration",
                        value: RideMetrics.duration(
                            ride.elapsedDuration(),
                            omittingZeroHours: true
                        ),
                        systemImage: "timer"
                    )

                    metric(
                        title: "Miles",
                        value: RideMetrics.miles(
                            RideMetrics.distanceInMeters(for: ride)
                        ),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )

                    metric(
                        title: "Start Time",
                        value: ride.startedAt.formatted(
                            .dateTime.hour().minute()
                        ),
                        systemImage: "clock"
                    )

                    metric(
                        title: "Date",
                        value: ride.startedAt.formatted(
                            .dateTime.month(.abbreviated).day()
                        ),
                        systemImage: "calendar"
                    )
                }

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
                    Section {
                        Button {
                            isShowingNoteEditor = true
                        } label: {
                            Label("Add Note", systemImage: "square.and.pencil")
                        }
                    }

                    Section {
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
        .sheet(isPresented: $isShowingNoteEditor) {
            RideNoteEditorView(ride: ride)
        }
        .sheet(isPresented: $isShowingReplay) {
            RideReplayView(routePoints: ride.routePoints)
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

    private func metric(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(spacing: 7) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(
            Color.white.opacity(0.075),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct RideStopBubble: View {
    let durationDescription: String

    private var label: String {
        "Stopped (\(durationDescription))"
    }

    var body: some View {
        Label {
            Text(label)
                .foregroundStyle(.white)
        } icon: {
            Image(systemName: "stop.fill")
                .foregroundStyle(.red)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background {
            RideStopBubbleShape()
                .fill(.black.opacity(0.88))
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

private struct RideStopBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pointerHeight: CGFloat = 6
        let bubbleRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - pointerHeight
        )
        var path = Path(
            roundedRect: bubbleRect,
            cornerRadius: 9,
            style: .continuous
        )
        path.move(to: CGPoint(x: rect.midX - 5, y: bubbleRect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + 5, y: bubbleRect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension RideRouteMotion {
    var color: Color {
        switch self {
        case .normalOrFaster:
            .green
        case .slower:
            .yellow
        case .stopped:
            .red
        }
    }
}

private extension TrackedRide {
    var historyTitle: String {
        customName ?? automaticName ?? startedAt.formatted(
            .dateTime
                .weekday(.wide)
                .month(.abbreviated)
                .day()
        )
    }

    var detailTitle: String {
        customName ?? automaticName
            ?? startedAt.formatted(date: .abbreviated, time: .omitted)
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
