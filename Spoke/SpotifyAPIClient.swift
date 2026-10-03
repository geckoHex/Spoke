import Foundation

actor SpotifyAPIClient {
    private var session: SpotifySession?
    private let urlSession: URLSession
    private let saveSession: @Sendable (SpotifySession?) throws -> Void

    init(
        session: SpotifySession? = nil,
        urlSession: URLSession = .shared,
        saveSession: @escaping @Sendable (SpotifySession?) throws -> Void = SpotifyKeychain.save
    ) {
        self.session = session
        self.urlSession = urlSession
        self.saveSession = saveSession
    }

    func authorize(request: SpotifyAuthorizationRequest, code: String) async throws -> UUID {
        let response = try await requestToken(fields: [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfiguration.redirectURI),
            URLQueryItem(name: "client_id", value: request.clientID),
            URLQueryItem(name: "code_verifier", value: request.verifier),
        ])
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw SpotifyAPIError.requestFailed("Spotify’s token response didn’t include a refresh token.")
        }
        try Task.checkCancellation()
        let session = SpotifySession(
            id: UUID(), clientID: request.clientID,
            accessToken: response.accessToken, refreshToken: refreshToken,
            expiration: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        try saveSession(session)
        self.session = session
        return session.id
    }

    func disconnect() throws {
        try saveSession(nil)
        session = nil
    }

    func nowPlaying() async throws -> SpotifyTrack? {
        let session = try await validSession()
        do {
            return try await fetchNowPlaying(session: session)
        } catch SpotifyAPIError.unauthorized {
            guard self.session?.id == session.id else { throw CancellationError() }
            self.session?.expiration = .distantPast
            let refreshed = try await validSession()
            return try await fetchNowPlaying(session: refreshed)
        }
    }

    private func validSession() async throws -> SpotifySession {
        guard var current = session else { throw SpotifyAPIError.authorizationExpired }
        if current.expiration > Date().addingTimeInterval(30) { return current }

        let response: SpotifyTokenResponse
        do {
            response = try await requestToken(fields: [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: current.refreshToken),
                URLQueryItem(name: "client_id", value: current.clientID),
            ])
        } catch {
            guard session?.id == current.id else { throw CancellationError() }
            throw error
        }
        try Task.checkCancellation()
        guard session?.id == current.id else { throw CancellationError() }
        current.accessToken = response.accessToken
        current.refreshToken = response.refreshToken ?? current.refreshToken
        current.expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        try saveSession(current)
        session = current
        return current
    }

    private func requestToken(fields: [URLQueryItem]) async throws -> SpotifyTokenResponse {
        var components = URLComponents()
        components.queryItems = fields
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await urlSession.data(for: request)
        let status = try httpStatus(response)
        guard status == 200 else { throw apiError(statusCode: status, data: data) }
        let token: SpotifyTokenResponse
        do {
            token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        } catch DecodingError.keyNotFound(let key, _) {
            throw SpotifyAPIError.requestFailed("Spotify’s token response is missing \(key.stringValue) (HTTP \(status)).")
        } catch {
            throw SpotifyAPIError.requestFailed("Spotify’s token response couldn’t be decoded (HTTP \(status)).")
        }
        guard !token.accessToken.isEmpty else {
            throw SpotifyAPIError.requestFailed("Spotify’s token response contained an empty access token.")
        }
        guard token.expiresIn > 0 else {
            throw SpotifyAPIError.requestFailed("Spotify’s token response contained an invalid expiration.")
        }
        guard token.refreshToken == nil || token.refreshToken?.isEmpty == false else {
            throw SpotifyAPIError.requestFailed("Spotify’s token response contained an empty refresh token.")
        }
        return token
    }

    private func fetchNowPlaying(session: SpotifySession) async throws -> SpotifyTrack? {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: request)
        try Task.checkCancellation()
        guard self.session?.id == session.id else { throw CancellationError() }

        switch try httpStatus(response) {
        case 200:
            let response = try JSONDecoder().decode(SpotifyCurrentlyPlayingResponse.self, from: data)
            guard let item = response.item else { return nil }
            return SpotifyTrack(
                spotifyID: item.id, albumArtURL: item.album.images.first?.url,
                title: item.name, artist: item.artists.map(\.name).joined(separator: ", "),
                progress: TimeInterval(response.progressMS ?? 0) / 1_000,
                duration: TimeInterval(item.durationMS) / 1_000,
                isPlaying: response.isPlaying, receivedAt: Date()
            )
        case 204:
            return nil
        case let status:
            throw apiError(statusCode: status, data: data)
        }
    }

    private func httpStatus(_ response: URLResponse) throws -> Int {
        guard let response = response as? HTTPURLResponse else { throw SpotifyAPIError.invalidResponse }
        return response.statusCode
    }

    private func apiError(statusCode: Int, data: Data) -> SpotifyAPIError {
        if statusCode == 401 { return .unauthorized }
        if let response = try? JSONDecoder().decode(SpotifyTokenErrorResponse.self, from: data) {
            if response.error == "invalid_grant" { return .authorizationExpired }
            return .requestFailed(response.errorDescription ?? response.error)
        }
        if statusCode == 403 {
            return .requestFailed("This Spotify account hasn’t been granted access to Spoke. Please contact the app developer.")
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
        case id, album, artists, name
        case durationMS = "duration_ms"
    }
}

nonisolated private struct SpotifyAlbumResponse: Decodable, Sendable {
    let images: [SpotifyImageResponse]
}
nonisolated private struct SpotifyImageResponse: Decodable, Sendable { let url: URL }
nonisolated private struct SpotifyArtistResponse: Decodable, Sendable { let name: String }
nonisolated private struct SpotifyTokenErrorResponse: Decodable, Sendable {
    let error: String
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
nonisolated private struct SpotifyWebErrorResponse: Decodable, Sendable { let error: SpotifyWebError }
nonisolated private struct SpotifyWebError: Decodable, Sendable { let message: String }

nonisolated enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case requestFailed(String)
    case unauthorized
    case authorizationExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Spotify returned an invalid response."
        case .requestFailed(let message): message
        case .unauthorized, .authorizationExpired: "Sign in to Spotify again in Settings."
        }
    }
}
