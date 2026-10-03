import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

nonisolated enum SpotifyConfiguration {
    static let redirectURI = "com.beckorion.spoke.spotify://callback"
    static let callbackScheme = "com.beckorion.spoke.spotify"
    static var clientID: String {
        Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
    }
}

nonisolated struct SpotifyAuthorizationRequest {
    let clientID: String
    let verifier: String
    let state: String

    init(clientID: String) throws {
        guard !clientID.isEmpty else { throw SpotifyAPIError.requestFailed("Spotify sign-in isn’t configured yet.") }
        self.clientID = clientID
        verifier = try Self.randomString()
        state = try Self.randomString()
    }

    var url: URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfiguration.redirectURI),
            URLQueryItem(name: "scope", value: "user-read-currently-playing"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
        ]
        return components.url!
    }

    func authorizationCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SpotifyAPIError.requestFailed("Spotify callback couldn’t be parsed.")
        }
        guard components.scheme == SpotifyConfiguration.callbackScheme,
              components.host == "callback",
              components.user == nil, components.password == nil, components.port == nil else {
            throw SpotifyAPIError.requestFailed("Spotify callback didn’t match Spoke’s registered redirect URI.")
        }
        guard components.path.isEmpty || components.path == "/" else {
            throw SpotifyAPIError.requestFailed("Spotify callback returned an unexpected path.")
        }
        // A trailing '#' is an empty fragment marker, with no additional OAuth data.
        guard components.fragment?.isEmpty != false else {
            throw SpotifyAPIError.requestFailed("Spotify callback returned an unexpected nonempty URL fragment.")
        }

        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states.first?.value == state else {
            throw SpotifyAPIError.requestFailed("Spotify sign-in couldn’t be verified. Please try again.")
        }
        if items.contains(where: { $0.name == "error" }) {
            throw SpotifyAPIError.requestFailed("Spotify permission wasn’t granted. Please try signing in again.")
        }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes.first?.value, !code.isEmpty else {
            throw SpotifyAPIError.requestFailed("Spotify callback didn’t include exactly one nonempty authorization code.")
        }
        return code
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SpotifyAPIError.requestFailed("Couldn’t start secure Spotify sign-in. Please try again.")
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

nonisolated struct SpotifySession: Codable, Sendable {
    let id: UUID
    let clientID: String
    var accessToken: String
    var refreshToken: String
    var expiration: Date
}

nonisolated enum SpotifyKeychain {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.beckorion.Spoke.spotify",
            kSecAttrAccount as String: "session",
        ]
    }

    static func load() throws -> SpotifySession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SpotifyAPIError.requestFailed("Couldn’t read your Spotify sign-in from Keychain.")
        }
        return try JSONDecoder().decode(SpotifySession.self, from: data)
    }

    static func save(_ session: SpotifySession?) throws {
        guard let session else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SpotifyAPIError.requestFailed("Couldn’t remove your Spotify sign-in from Keychain.")
            }
            return
        }
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(session),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw SpotifyAPIError.requestFailed("Couldn’t save your Spotify sign-in to Keychain.")
        }
    }
}

@MainActor
final class SpotifyAuthenticationStore: ObservableObject {
    @Published private(set) var sessionID: UUID?
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?
    let client: SpotifyAPIClient
    private var webSession: ASWebAuthenticationSession?
    private var presentationContext: SpotifyPresentationContext?

    init() {
        let isTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let session = isTesting ? nil : try? SpotifyKeychain.load()
        sessionID = session?.id
        client = SpotifyAPIClient(session: session)
    }

    func signIn() async {
        guard !isConnecting else { return }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        var stage = "Spotify browser sign-in"

        do {
            let request = try SpotifyAuthorizationRequest(clientID: SpotifyConfiguration.clientID)
            let callback = try await authenticate(url: request.url)
            stage = "Spotify callback validation"
            let code = try request.authorizationCode(from: callback)
            stage = "Spotify token exchange"
            sessionID = try await client.authorize(request: request, code: code)
        } catch {
            let error = error as NSError
            if error.domain == ASWebAuthenticationSessionErrorDomain,
               error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue { return }
            errorMessage = "\(stage): \(error.localizedDescription)"
        }
    }

    func signOut() async {
        do {
            try await client.disconnect()
            sessionID = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requireSignIn() async {
        await signOut()
        errorMessage = "Your Spotify sign-in expired. Please sign in again."
    }

    private func authenticate(url: URL) async throws -> URL {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) else {
            throw SpotifyAPIError.requestFailed("Open Spoke to sign in to Spotify.")
        }
        let context = SpotifyPresentationContext(window: window)
        presentationContext = context
        defer {
            webSession = nil
            presentationContext = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(SpotifyConfiguration.callbackScheme)
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAPIError.requestFailed("The sign-in browser closed without a callback URL or system error."))
                }
            }
            session.presentationContextProvider = context
            webSession = session
            guard session.start() else {
                continuation.resume(throwing: SpotifyAPIError.requestFailed("Couldn’t open Spotify sign-in. Please try again."))
                return
            }
        }
    }
}

@MainActor
private final class SpotifyPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
