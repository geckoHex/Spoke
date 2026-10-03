//
//  SpotifyNowPlaying.swift
//  Spoke
//

import Combine
import Foundation
import SwiftUI

nonisolated struct SpotifyTrack: Equatable, Sendable {
    let spotifyID: String?
    let albumArtURL: URL?
    let title: String
    let artist: String
    let progress: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let receivedAt: Date

    var identity: String {
        if let spotifyID, !spotifyID.isEmpty {
            return "spotify:\(spotifyID)"
        }

        return "metadata:\(title)\u{1F}\(artist)"
    }

    var playbackStartedAt: Date {
        receivedAt.addingTimeInterval(-min(max(progress, 0), duration))
    }

    func progress(at date: Date) -> TimeInterval {
        let elapsed = isPlaying ? max(date.timeIntervalSince(receivedAt), 0) : 0
        return min(progress + elapsed, duration)
    }
}

@MainActor
final class SpotifyNowPlayingStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case notPlaying
        case playing(SpotifyTrack)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let refreshInterval = Duration.seconds(10)

    func reset() {
        state = .idle
    }

    func monitor(
        authentication: SpotifyAuthenticationStore,
        onTrackChecked: @escaping @MainActor (SpotifyTrack?) -> Void
    ) async {
        state = .loading

        while !Task.isCancelled {
            do {
                let track = try await authentication.client.nowPlaying()
                try Task.checkCancellation()
                onTrackChecked(track)
                state = track.map(State.playing) ?? .notPlaying
            } catch SpotifyAPIError.authorizationExpired, SpotifyAPIError.unauthorized {
                guard !Task.isCancelled else { return }
                await authentication.requireSignIn()
                return
            } catch is CancellationError {
                return
            } catch {
                state = .failed(
                    "Spotify couldn’t load now playing. \(error.localizedDescription)"
                )
            }

            do {
                try await Task.sleep(for: refreshInterval)
            } catch {
                return
            }
        }
    }
}

struct SpotifyNowPlayingView: View {
    let track: SpotifyTrack

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = track.progress(at: context.date)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    albumArt

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(SpokeStyle.text)
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(SpokeStyle.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ProgressView(value: progress, total: max(track.duration, 1))
                    .progressViewStyle(.linear)
                    .tint(SpokeStyle.accent)
                    .accessibilityLabel("Song progress")
                    .accessibilityValue(progressDescription(progress: progress))
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var albumArt: some View {
        AsyncImage(url: track.albumArtURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    SpokeStyle.elevatedSurface

                    Image(systemName: "music.note")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(SpokeStyle.text)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private func progressDescription(progress: TimeInterval) -> String {
        "\(Int(progress)) of \(Int(track.duration)) seconds"
    }
}

struct SpotifyPausedView: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpokeStyle.elevatedSurface)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spotify Paused")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(SpokeStyle.text)

                Text("Nothing playing right now")
                    .font(.subheadline)
                    .foregroundStyle(SpokeStyle.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SpotifyStatusView: View {
    let symbol: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .foregroundStyle(SpokeStyle.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
