# 06 — Keychain Secure Storage

OAuth tokens (access + refresh) are secrets. Store them in the macOS **Keychain**,
never in `UserDefaults`, plist, or logs.

## What to store

| Key                | Value                          |
| ------------------ | ------------------------------ |
| `access_token`     | string                         |
| `refresh_token`    | string                         |
| `expires_at`       | epoch seconds (can be in Defaults — not secret, but convenient to keep together) |

Recommend storing a single JSON blob under one keychain item to keep it atomic.

## Generic Keychain helper

```swift
import Security

enum Keychain {
    static let service = "com.yourorg.claudespotlight.tokens"

    static func set(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)            // upsert
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func get(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return out as? Data
    }

    static func delete(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}

enum KeychainError: Error { case status(OSStatus) }
```

## Accessibility level

Use `kSecAttrAccessibleAfterFirstUnlock` so token refresh works after the user has
unlocked the Mac once (e.g. for a background refresh). Use
`...AfterFirstUnlockThisDeviceOnly` if you want to prevent the item from migrating
to other devices via backups — recommended for tokens.

## Sandbox / entitlement note

- With **App Sandbox** on, a plain generic-password keychain item works without a
  keychain-access-group entitlement, as long as you don't share across apps.
- If you later share between an app + helper, add a Keychain Sharing entitlement
  with a shared access group. See `07-entitlements-sandbox.md`.

## Do / Don't

- ✅ Read tokens on demand, keep in memory only as long as needed.
- ✅ `Keychain.delete` on sign-out.
- ❌ Never `print`/`os_log` token values.
- ❌ Never write tokens to a cache file or `UserDefaults`.

## Related

`05-oauth-auth.md` · `07-entitlements-sandbox.md`
