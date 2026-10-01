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
            VStack(alignment: .leading, spacing: 0) {
                Text("Your rides")
                    .font(.largeTitle.bold())
                    .foregroundStyle(SpokeStyle.text)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("historyTitle")
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                Group {
                    if completedRides.isEmpty {
                        ContentUnavailableView(
                            "No Rides Yet",
                            systemImage: "figure.outdoor.cycle",
                            description: Text("Completed rides will appear here.")
                        )
                        .background(SpokeStyle.background)
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
                            .padding(.horizontal, SpokeStyle.pageInset)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                        .scrollIndicators(.hidden)
                        .background(SpokeStyle.background)
                    }
                }
            }
            .background(SpokeStyle.background)
            .toolbar(.hidden, for: .navigationBar)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                RideRouteThumbnail(points: ride.routePoints)
                    .frame(width: 76, height: 90)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ride.historyTitle)
                        .font(.headline)
                        .foregroundStyle(SpokeStyle.text)
                        .layoutPriority(1)

                    Text(
                        RideMetrics.ageDescription(
                            since: ride.endedAt ?? ride.startedAt,
                            relativeTo: currentDate
                        )
                    )
                        .font(.footnote)
                        .foregroundStyle(SpokeStyle.secondaryText)
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
                .foregroundStyle(SpokeStyle.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHighlighted ? SpokeStyle.elevatedSurface : SpokeStyle.surface,
            in: RoundedRectangle(cornerRadius: SpokeStyle.cardRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: SpokeStyle.cardRadius, style: .continuous))
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
                .foregroundStyle(SpokeStyle.secondaryText)
                .frame(width: 16)
                .accessibilityHidden(true)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpokeStyle.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(title), \(value)")
    }
}

private struct RideRouteThumbnail: View {
    let points: [RideRoutePoint]

    var body: some View {
        let coordinates = points.sorted { $0.recordedAt < $1.recordedAt }.map {
            MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }

        ZStack {
            SpokeStyle.background
            if coordinates.count > 1 {
                Canvas { context, size in
                    let minX = coordinates.map(\.x).min() ?? 0
                    let minY = coordinates.map(\.y).min() ?? 0
                    let width = (coordinates.map(\.x).max() ?? minX) - minX
                    let height = (coordinates.map(\.y).max() ?? minY) - minY
                    let scale = min((size.width - 20) / max(width, 1), (size.height - 20) / max(height, 1))
                    var path = Path()
                    for (index, point) in coordinates.enumerated() {
                        let position = CGPoint(
                            x: (point.x - minX - width / 2) * scale + size.width / 2,
                            y: (point.y - minY - height / 2) * scale + size.height / 2
                        )
                        if index == 0 { path.move(to: position) }
                        else { path.addLine(to: position) }
                    }
                    context.stroke(path, with: .color(SpokeStyle.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                Image(systemName: "bicycle")
                    .font(.title2)
                    .foregroundStyle(SpokeStyle.secondaryText)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct RideHistoryDetailView: View {
    let ride: TrackedRide

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var rideName = ""
    @State private var actionSheet: RideActionSheet?
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

    private var movingMetrics: RideMovingMetrics {
        RideRouteSpeed.movingMetrics(for: ride.routePoints)
    }

    private var rideDateAndTime: String {
        let time = ride.startedAt.formatted(.dateTime.hour().minute())
        let date = ride.startedAt.formatted(
            .dateTime.month(.abbreviated).day()
        )
        return "\(date)        \(time)"
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
            SpokeStyle.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                if coordinates.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.system(size: 34, weight: .medium))

                        Text("No route recorded")
                            .font(.headline)
                    }
                    .foregroundStyle(SpokeStyle.secondaryText)
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
                                    .fill(SpokeStyle.text)
                                    .frame(width: 12, height: 12)
                                    .overlay {
                                        Circle()
                                            .stroke(SpokeStyle.background, lineWidth: 2)
                                    }
                            }
                        }
                    }
                    .mapStyle(
                        .standard(
                            elevation: .flat,
                            emphasis: .muted,
                            pointsOfInterest: .excludingAll,
                            showsTraffic: false
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            isShowingReplay = true
                        } label: {
                            Label("Replay", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SpokeStyle.background)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(SpokeStyle.accent, in: RoundedRectangle(cornerRadius: SpokeStyle.controlRadius, style: .continuous))
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
                        )
                    )

                    metric(
                        title: "Miles",
                        value: RideMetrics.miles(
                            RideMetrics.distanceInMeters(for: ride)
                        )
                    )

                    metric(
                        title: "Time Moving",
                        value: RideMetrics.duration(
                            movingMetrics.duration,
                            omittingZeroHours: true
                        )
                    )

                    metric(
                        title: "Moving Avg.",
                        value: RideMetrics.speedInMilesPerHour(
                            movingMetrics.averageSpeedInMilesPerHour
                        )
                    )
                }
                .padding(.vertical, 12)
                .background(SpokeStyle.surface, in: .rect(cornerRadius: SpokeStyle.cardRadius))

                Button("Ride soundtrack") {
                    isShowingSoundtrack = true
                }
                .buttonStyle(SpokePrimaryButtonStyle())
            }
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.bottom, 16)
        }
        .navigationTitle(ride.detailTitle)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbarBackground(SpokeStyle.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background {
            SpokeBackSwipeSupport()
                .frame(width: 0, height: 0)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(SpokeToolbarButtonStyle())
                .accessibilityLabel("Back")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(ride.detailTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Text(rideDateAndTime)
                        .font(.caption)
                        .foregroundStyle(SpokeStyle.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    actionSheet = .actions
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(SpokeToolbarButtonStyle())
                .accessibilityLabel("Ride actions")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $isShowingSoundtrack) {
            RideSoundtrackView(ride: ride)
        }
        .sheet(isPresented: $isShowingReplay) {
            RideReplayView(routePoints: ride.routePoints)
        }
        .sheet(item: $actionSheet) { sheet in
            switch sheet {
            case .actions:
                rideActions
            case .note:
                RideNoteEditorView(ride: ride)
            case .rename:
                RideRenameView(name: $rideName, onSave: renameRide)
            case .delete:
                SpokeConfirmationView(
                    title: "Delete Ride?",
                    message: "This ride and its soundtrack will be permanently deleted.",
                    actionTitle: "Delete",
                    onConfirm: deleteRide
                )
            }
        }
    }

    private var rideActions: some View {
        SpokeSheet(title: "Ride Actions") {
            VStack(spacing: 0) {
                Button {
                    actionSheet = .note
                } label: {
                    Label("Add Note", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }

                Divider().overlay(SpokeStyle.separator)

                Button {
                    rideName = ride.customName ?? ride.detailTitle
                    actionSheet = .rename
                } label: {
                    Label("Rename Ride", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }

                Divider().overlay(SpokeStyle.separator)

                Button(role: .destructive) {
                    actionSheet = .delete
                } label: {
                    Label("Delete Ride", systemImage: "trash")
                        .foregroundStyle(SpokeStyle.danger)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
            }
            .foregroundStyle(SpokeStyle.text)
            .buttonStyle(.plain)
            .padding(.horizontal, SpokeStyle.pageInset)
            .padding(.vertical, 8)
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
        value: String
    ) -> some View {
        VStack(spacing: 7) {
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(SpokeStyle.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .accessibilityElement(children: .combine)
    }
}

private enum RideActionSheet: String, Identifiable {
    case actions, note, rename, delete

    var id: String { rawValue }
}

private struct RideStopBubble: View {
    let durationDescription: String

    private var label: String {
        "\(durationDescription)"
    }

    var body: some View {
        Label {
            Text(label)
                .foregroundStyle(SpokeStyle.text)
        } icon: {
            Image(systemName: "octagon.fill")
                .foregroundStyle(SpokeStyle.danger)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background {
            RideStopBubbleShape()
                .fill(SpokeStyle.background.opacity(0.88))
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
            SpokeStyle.accent
        case .slower:
            SpokeStyle.caution
        case .stopped:
            SpokeStyle.danger
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
        SpokeSheet(title: "Ride Soundtrack") {
            Group {
                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No Songs Recorded", systemImage: "music.note.list")
                            .font(.headline)

                        Text("Songs played during this ride will appear here.")
                            .foregroundStyle(SpokeStyle.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            RideSoundtrackRow(entry: entry)
                            Divider().overlay(SpokeStyle.separator)
                        }
                    }
                    .padding(.horizontal, SpokeStyle.pageInset)
                    .padding(.vertical, 8)
                }
            }
        }
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
                    .foregroundStyle(SpokeStyle.text)
                    .lineLimit(2)

                Text(entry.artist)
                    .font(.subheadline)
                    .foregroundStyle(SpokeStyle.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedStartTime)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(SpokeStyle.secondaryText)
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
            SpokeStyle.elevatedSurface

            Image(systemName: "music.note")
                .font(.title3.weight(.medium))
                .foregroundStyle(SpokeStyle.text)
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
