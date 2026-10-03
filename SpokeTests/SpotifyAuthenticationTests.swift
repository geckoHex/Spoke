import Foundation
import Synchronization
import Testing
@testable import Spoke

@Suite(.serialized)
struct SpotifyAuthenticationTests {
    @Test func pkceAndCallbackValidation() throws {
        // RFC 7636 test vector verifies the encoding independently of this implementation.
        #expect(SpotifyAuthorizationRequest.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let request = try SpotifyAuthorizationRequest(clientID: "public-client")
        #expect(request.verifier.count == 43)
        #expect(request.state != request.verifier)
        let parameters = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(parameters.first { $0.name == "scope" }?.value == "user-read-currently-playing")
        #expect(parameters.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(parameters.first { $0.name == "redirect_uri" }?.value == SpotifyConfiguration.redirectURI)

        let prefix = SpotifyConfiguration.redirectURI
        let callback = URL(string: "\(prefix)?state=\(request.state)&code=accepted")!
        #expect(try request.authorizationCode(from: callback) == "accepted")
        let callbackWithEmptyFragment = URL(string: "\(prefix)?state=\(request.state)&code=accepted#")!
        #expect(try request.authorizationCode(from: callbackWithEmptyFragment) == "accepted")
        let callbackWithRootSlash = URL(string: "\(prefix)/?state=\(request.state)&code=accepted")!
        #expect(try request.authorizationCode(from: callbackWithRootSlash) == "accepted")
        let callbackWithSlashAndEmptyFragment = URL(string: "\(prefix)/?state=\(request.state)&code=accepted#")!
        #expect(try request.authorizationCode(from: callbackWithSlashAndEmptyFragment) == "accepted")
        for invalid in [
            "\(prefix)?state=wrong&code=accepted",
            "\(prefix)/?state=wrong&code=accepted#",
            "\(prefix)?code=accepted",
            "\(prefix)?state=\(request.state)&state=\(request.state)&code=accepted",
            "\(prefix)?state=\(request.state)&code=one&code=two",
            "\(prefix)?state=\(request.state)&code=",
            "\(prefix)?state=\(request.state)&error=access_denied",
            "com.beckorion.spoke.spotify://other?state=\(request.state)&code=accepted",
            "com.beckorion.spoke.spotify://callback/extra?state=\(request.state)&code=accepted",
            "https://callback?state=\(request.state)&code=accepted",
            "\(prefix)?state=\(request.state)&code=accepted#unexpected",
            "\(prefix)#access_token=private-token&state=\(request.state)",
        ] {
            #expect(throws: (any Error).self) {
                try request.authorizationCode(from: URL(string: invalid)!)
            }
        }
    }

    @Test func signInRefreshRotationAndDisconnect() async throws {
        SpotifyHTTPStub.configure([
            (200, #"{"access_token":"first","expires_in":1,"refresh_token":"refresh+one"}"#),
            (200, #"{"access_token":"second","expires_in":1,"refresh_token":"refresh+two"}"#),
            (200, #"{"item":{"id":"track","name":"Song","duration_ms":200000,"album":{"images":[]},"artists":[{"name":"Artist"}]},"progress_ms":1000,"is_playing":true}"#),
            (200, #"{"access_token":"third","expires_in":3600}"#),
            (204, ""),
        ])
        let saved = Mutex<[SpotifySession?]>([])
        let client = SpotifyAPIClient(urlSession: makeURLSession()) { session in
            saved.withLock { $0.append(session) }
        }
        let request = try SpotifyAuthorizationRequest(clientID: "public-client")
        let id = try await client.authorize(request: request, code: "code+value")
        let track = try await client.nowPlaying()
        #expect(track?.title == "Song")
        #expect(track?.artist == "Artist")
        #expect(track?.progress == 1)
        #expect(try await client.nowPlaying() == nil)

        let requests = SpotifyHTTPStub.requests
        let signInBody = try formBody(requests[0])
        #expect(signInBody.contains("code=code%2Bvalue"))
        #expect(signInBody.contains("code_verifier=\(request.verifier)"))
        #expect(signInBody.contains("client_id=public-client"))
        #expect(!signInBody.contains("client_secret"))
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(try formBody(requests[1]).contains("refresh_token=refresh%2Bone"))
        #expect(try formBody(requests[3]).contains("refresh_token=refresh%2Btwo"))
        #expect(requests[2].value(forHTTPHeaderField: "Authorization") == "Bearer second")
        let persisted = saved.withLock { $0.compactMap { $0 } }
        #expect(persisted.allSatisfy { $0.id == id })
        #expect(persisted.last?.refreshToken == "refresh+two")

        try await client.disconnect()
        #expect(saved.withLock { $0.last! == nil })
        await #expect(throws: SpotifyAPIError.self) { try await client.nowPlaying() }
        #expect(SpotifyHTTPStub.requests.count == 5)
    }

    @Test func unauthorizedPlaybackRefreshesOnceAndRevokedAuthorizationNeedsSignIn() async throws {
        let session = SpotifySession(
            id: UUID(), clientID: "public-client", accessToken: "old", refreshToken: "refresh",
            expiration: Date().addingTimeInterval(3600)
        )
        SpotifyHTTPStub.configure([
            (401, ""),
            (200, #"{"access_token":"renewed","expires_in":3600}"#),
            (204, ""),
        ])
        let client = SpotifyAPIClient(session: session, urlSession: makeURLSession(), saveSession: { _ in })
        #expect(try await client.nowPlaying() == nil)
        #expect(SpotifyHTTPStub.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")

        var expired = session
        expired.expiration = .distantPast
        SpotifyHTTPStub.configure([(400, #"{"error":"invalid_grant"}"#)])
        let revoked = SpotifyAPIClient(session: expired, urlSession: makeURLSession(), saveSession: { _ in })
        do {
            _ = try await revoked.nowPlaying()
            Issue.record("Revoked authorization must require sign-in")
        } catch SpotifyAPIError.authorizationExpired {
            #expect(SpotifyHTTPStub.requests.count == 1)
        }
    }

    @Test func malformedTokenResponsesHaveUsefulDiagnosticsWithoutExposingTokens() async throws {
        let cases = [
            (#"{"access_token":"private-access","expires_in":3600}"#, "refresh token"),
            (#"{"refresh_token":"private-refresh","expires_in":3600}"#, "access_token (HTTP 200)"),
            (#"{"access_token":"","refresh_token":"private-refresh","expires_in":3600}"#, "empty access token"),
            (#"{"access_token":"private-access","refresh_token":"private-refresh","expires_in":0}"#, "invalid expiration"),
            ("not-json-private-access", "couldn’t be decoded (HTTP 200)"),
        ]
        for (body, expected) in cases {
            SpotifyHTTPStub.configure([(200, body)])
            let client = SpotifyAPIClient(urlSession: makeURLSession(), saveSession: { _ in
                Issue.record("An invalid token response must not be persisted")
            })
            let request = try SpotifyAuthorizationRequest(clientID: "public-client")
            do {
                _ = try await client.authorize(request: request, code: "private-code")
                Issue.record("An invalid token response must fail")
            } catch {
                let message = error.localizedDescription
                #expect(message.contains(expected))
                #expect(!message.contains("private-access"))
                #expect(!message.contains("private-refresh"))
                #expect(!message.contains("private-code"))
            }
        }
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpotifyHTTPStub.self]
        return URLSession(configuration: configuration)
    }

    private func formBody(_ request: URLRequest) throws -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        let stream = try #require(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class SpotifyHTTPStub: URLProtocol, @unchecked Sendable {
    private struct Script {
        var responses: [(Int, String)] = []
        var requests: [URLRequest] = []
    }
    private static let script = Mutex(Script())
    static func configure(_ responses: [(Int, String)]) {
        script.withLock { $0 = Script(responses: responses) }
    }
    static var requests: [URLRequest] { script.withLock { $0.requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.script.withLock { script in
            script.requests.append(request)
            return script.responses.isEmpty ? (500, "Unexpected request") : script.responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
