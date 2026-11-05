import Foundation

/// Talks to the stateless Dear Home auth server (see DearHomeAuthServer/). The server holds the
/// Apple private key and signs the client_secret; the app only ever sends the authorization code
/// or the refresh token, never any secret.
enum AppleAuthClient {
    /// Set via the `DEARHOME_AUTH_BASE_URL` Info.plist key, e.g. `https://dearhome-auth.example.com`.
    /// Empty/unset means the server is not configured yet; account still works fully on-device,
    /// but server-side token revocation is skipped.
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "DEARHOME_AUTH_BASE_URL") as? String,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    /// Exchanges the one-time authorization code for a refresh token. Returns nil when the server
    /// is not configured (caller treats this as "revocation unavailable", not an error).
    static func exchange(authorizationCode: String) async throws -> String? {
        guard let base = baseURL else { return nil }
        let url = base.appendingPathComponent("api/apple/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": authorizationCode])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return object?["refreshToken"] as? String
    }

    /// Revokes a refresh token. Best-effort: the caller ignores failures so local deletion always
    /// completes even if the server is unreachable.
    static func revoke(refreshToken: String) async throws {
        guard let base = baseURL else { return }
        let url = base.appendingPathComponent("api/apple/revoke")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": refreshToken])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppleAuthClientError.serverFailed
        }
    }
}

enum AppleAuthClientError: LocalizedError {
    case serverFailed

    var errorDescription: String? {
        "The Apple auth server call failed."
    }
}
