# 05 — OAuth 2.0 + PKCE Login

The app runs **its own** login flow (not Claude Code's credentials). It uses the
**Authorization Code flow with PKCE**, which is the correct pattern for a native
public client (no client secret).

> ⚠️ `TODO(verify)` — the exact Anthropic OAuth **authorization endpoint, token
> endpoint, client_id, and scopes** must be confirmed against the official source
> before this works. The values below are placeholders showing the shape. Do not
> ship guessed endpoints. Confirm via Anthropic's developer console / OAuth docs.

## Flow

```
App ──(1) open authorize URL w/ code_challenge──▶ Browser → Anthropic login
Anthropic ──(2) redirect to claudespotlight://callback?code=…&state=… ──▶ App
App ──(3) POST /token  code + code_verifier ──▶ Anthropic
Anthropic ──(4) { access_token, refresh_token, expires_in } ──▶ App
App ──(5) store tokens in Keychain (06-) ; use Bearer token for API calls
```

## PKCE generation

```swift
import CryptoKit

enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()           // S256
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

## Config

```swift
enum OAuthConfig {
    static let clientID    = "TODO(verify)-public-client-id"
    static let authorizeURL = URL(string: "https://TODO.anthropic.com/oauth/authorize")!
    static let tokenURL     = URL(string: "https://TODO.anthropic.com/oauth/token")!
    static let redirectURI  = "claudespotlight://callback"   // custom URL scheme
    static let scopes       = ["TODO(verify)"]
}
```

## Recommended: `ASWebAuthenticationSession`

Apple's `AuthenticationServices` gives a secure, system-managed browser sheet and
handles the redirect back via your custom scheme — preferred over hand-managing a
`WKWebView` or the system browser.

```swift
import AuthenticationServices

final class AuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    func login() async throws {
        let verifier  = PKCE.verifier()
        let challenge = PKCE.challenge(for: verifier)
        let state     = UUID().uuidString

        var comps = URLComponents(url: OAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: OAuthConfig.clientID),
            .init(name: "redirect_uri", value: OAuthConfig.redirectURI),
            .init(name: "scope", value: OAuthConfig.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callback = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: comps.url!, callbackURLScheme: "claudespotlight"
            ) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? AuthError.cancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebSession = false
            session.start()
        }

        let code = try extractCode(from: callback, expectedState: state)
        try await exchange(code: code, verifier: verifier)
    }
    // presentationAnchor(for:) returns the panel/window or NSApp.keyWindow
}
```

## Token exchange

```swift
func exchange(code: String, verifier: String) async throws {
    var req = URLRequest(url: OAuthConfig.tokenURL)
    req.httpMethod = "POST"
    req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let body = [
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": OAuthConfig.redirectURI,
        "client_id": OAuthConfig.clientID,
        "code_verifier": verifier,
    ].map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
     .joined(separator: "&")
    req.httpBody = Data(body.utf8)

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.exchangeFailed }
    let token = try JSONDecoder().decode(TokenResponse.self, from: data)
    try TokenStore.save(token)          // → Keychain (06-)
}
```

## Refresh & expiry

- Store `expires_in` as an absolute `expiresAt` date.
- Before each API call, if `expiresAt` is within ~60s, refresh using the
  `refresh_token` (`grant_type=refresh_token`).
- On refresh failure (revoked), clear Keychain and prompt re-login.

## Custom URL scheme registration

In `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLName</key><string>com.yourorg.claudespotlight</string>
  <key>CFBundleURLSchemes</key><array><string>claudespotlight</string></array>
</dict></array>
```

## Sign-out

`TokenStore.clear()` (remove Keychain items) + reset in-memory auth state.

## Related

`06-keychain-storage.md` · `07-entitlements-sandbox.md` · `12-claude-api-integration.md`
