//
//  SpotifyNowPlaying.swift
//  Spoke
//

import Combine
import Foundation
import SwiftUI

struct SpotifyCredentials: Equatable, Hashable, Sendable {
    let clientID: String
    let clientSecret: String
    let refreshToken: String

    init?(settings: AppSettings) {
        let clientID = settings.spotifyClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = settings.spotifyClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = settings.spotifyRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !clientID.isEmpty, !clientSecret.isEmpty, !refreshToken.isEmpty else {
            return nil
        }

        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
    }
}

struct SpotifyTrack: Equatable, Sendable {
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

    private let client: SpotifyAPIClient
    private let refreshInterval = Duration.seconds(10)

    init(client: SpotifyAPIClient = SpotifyAPIClient()) {
        self.client = client
    }

    func reset() async {
        state = .idle
        await client.reset()
    }

    func monitor(
        credentials: SpotifyCredentials,
        onRefreshToken: @escaping @MainActor (String) -> Void,
        onTrackChecked: @escaping @MainActor (SpotifyTrack?) -> Void
    ) async {
        await client.reset()
        state = .loading

        while !Task.isCancelled {
            do {
                let result = try await client.nowPlaying(credentials: credentials)

                if let refreshedToken = result.refreshedToken,
                   refreshedToken != credentials.refreshToken {
                    onRefreshToken(refreshedToken)
                }

                onTrackChecked(result.track)
                state = result.track.map(State.playing) ?? .notPlaying
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
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ProgressView(value: progress, total: max(track.duration, 1))
                    .progressViewStyle(.linear)
                    .tint(.white)
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
                    Color.white.opacity(0.12)

                    Image(systemName: "music.note")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private func progressDescription(progress: TimeInterval) -> String {
        "\(Int(progress)) of \(Int(track.duration)) seconds"
    }
}

struct SpotifyPausedView: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Spotify Paused")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Nothing playing right now")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
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
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

actor SpotifyAPIClient {
    private struct AccessToken {
        let value: String
        let expiration: Date
    }

    struct NowPlayingResult: Sendable {
        let track: SpotifyTrack?
        let refreshedToken: String?
    }

    private var accessToken: AccessToken?

    func reset() {
        accessToken = nil
    }

    func nowPlaying(credentials: SpotifyCredentials) async throws -> NowPlayingResult {
        var tokenResponse: SpotifyTokenResponse?
        let token: String

        if let accessToken, accessToken.expiration > Date().addingTimeInterval(30) {
            token = accessToken.value
        } else {
            let refreshed = try await refreshAccessToken(credentials: credentials)
            tokenResponse = refreshed
            token = refreshed.accessToken
        }

        do {
            let track = try await fetchNowPlaying(accessToken: token)
            return NowPlayingResult(track: track, refreshedToken: tokenResponse?.refreshToken)
        } catch SpotifyAPIError.unauthorized {
            accessToken = nil
            let refreshed = try await refreshAccessToken(credentials: credentials)
            let track = try await fetchNowPlaying(accessToken: refreshed.accessToken)
            return NowPlayingResult(track: track, refreshedToken: refreshed.refreshToken)
        }
    }

    private func refreshAccessToken(
        credentials: SpotifyCredentials
    ) async throws -> SpotifyTokenResponse {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            throw SpotifyAPIError.invalidResponse
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credentials.refreshToken),
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )

        let basicCredentials = Data(
            "\(credentials.clientID):\(credentials.clientSecret)".utf8
        ).base64EncodedString()
        request.setValue("Basic \(basicCredentials)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try validatedHTTPResponse(response)

        guard httpResponse.statusCode == 200 else {
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }

        let tokenResponse = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        accessToken = AccessToken(
            value: tokenResponse.accessToken,
            expiration: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        )
        return tokenResponse
    }

    private func fetchNowPlaying(accessToken: String) async throws -> SpotifyTrack? {
        guard let url = URL(
            string: "https://api.spotify.com/v1/me/player/currently-playing"
        ) else {
            throw SpotifyAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try validatedHTTPResponse(response)

        switch httpResponse.statusCode {
        case 200:
            let response = try JSONDecoder().decode(SpotifyCurrentlyPlayingResponse.self, from: data)
            guard let item = response.item else { return nil }

            return SpotifyTrack(
                spotifyID: item.id,
                albumArtURL: item.album.images.first?.url,
                title: item.name,
                artist: item.artists.map(\.name).joined(separator: ", "),
                progress: TimeInterval(response.progressMS ?? 0) / 1_000,
                duration: TimeInterval(item.durationMS) / 1_000,
                isPlaying: response.isPlaying,
                receivedAt: Date()
            )
        case 204:
            return nil
        default:
            throw apiError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    private func validatedHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        return httpResponse
    }

    private func apiError(statusCode: Int, data: Data) -> SpotifyAPIError {
        if statusCode == 401 {
            return .unauthorized
        }

        if let response = try? JSONDecoder().decode(SpotifyTokenErrorResponse.self, from: data) {
            return .requestFailed(response.message)
        }

        if let response = try? JSONDecoder().decode(SpotifyWebErrorResponse.self, from: data) {
            return .requestFailed(response.error.message)
        }

        return .requestFailed("Spotify returned HTTP \(statusCode).")
    }
}

nonisolated private struct SpotifyTokenResponse: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

nonisolated private struct SpotifyCurrentlyPlayingResponse: Decodable, Sendable {
    let progressMS: Int?
    let isPlaying: Bool
    let item: SpotifyTrackResponse?

    enum CodingKeys: String, CodingKey {
        case progressMS = "progress_ms"
        case isPlaying = "is_playing"
        case item
    }
}

nonisolated private struct SpotifyTrackResponse: Decodable, Sendable {
    let id: String?
    let album: SpotifyAlbumResponse
    let artists: [SpotifyArtistResponse]
    let durationMS: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case album
        case artists
        case durationMS = "duration_ms"
        case name
    }
}

nonisolated private struct SpotifyAlbumResponse: Decodable, Sendable {
    let images: [SpotifyImageResponse]
}

nonisolated private struct SpotifyImageResponse: Decodable, Sendable {
    let url: URL
}

nonisolated private struct SpotifyArtistResponse: Decodable, Sendable {
    let name: String
}

nonisolated private struct SpotifyTokenErrorResponse: Decodable, Sendable {
    let error: String?
    let errorDescription: String?

    var message: String {
        errorDescription ?? error ?? "The Spotify request failed."
    }

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

nonisolated private struct SpotifyWebErrorResponse: Decodable, Sendable {
    let error: SpotifyWebError
}

nonisolated private struct SpotifyWebError: Decodable, Sendable {
    let message: String
}

private enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case requestFailed(String)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Spotify returned an invalid response."
        case .requestFailed(let message):
            message
        case .unauthorized:
            "Check the Spotify credentials in Settings."
        }
    }
}
