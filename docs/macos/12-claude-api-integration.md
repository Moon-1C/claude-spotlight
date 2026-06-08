# 12 — Claude API Integration (Swift)

How the app talks to Claude after the user is logged in (`05-oauth-auth.md`).

> There is **no official Anthropic Swift SDK** — call the REST Messages API
> directly with `URLSession`. The shapes below are verified against the current
> API. Model IDs and streaming behavior were confirmed via the `claude-api`
> reference.

## Auth header: OAuth uses `Authorization: Bearer`

This app authenticates with an **OAuth access token**, not an `x-api-key`. OAuth
bearer tokens **must** go on the `Authorization` header — sending an OAuth token
via `x-api-key` returns 401.

```
Authorization: Bearer <access_token>     ← our app (OAuth)
anthropic-version: 2023-06-01
content-type: application/json
```

(API-key callers use `x-api-key` instead; we do not.)

## Model

Default to **`claude-opus-4-8`** — the most capable current model. Let the user
pick in Settings; sensible options:

| Model               | ID                  | Use for                          |
| ------------------- | ------------------- | -------------------------------- |
| Claude Opus 4.8     | `claude-opus-4-8`   | default — best quality           |
| Claude Sonnet 4.6   | `claude-sonnet-4-6` | faster / cheaper                 |
| Claude Haiku 4.5    | `claude-haiku-4-5`  | quickest, simple queries         |

> Do **not** append date suffixes to these IDs — the strings above are complete.

## Endpoint

`POST https://api.anthropic.com/v1/messages`

For a snappy Spotlight feel, **stream** the response (Server-Sent Events). The API
streams when `"stream": true`.

## Request body

```json
{
  "model": "claude-opus-4-8",
  "max_tokens": 4096,
  "stream": true,
  "thinking": { "type": "adaptive" },
  "messages": [
    { "role": "user", "content": "your prompt here" }
  ]
}
```

Notes:
- `max_tokens` is required. ~4096 is fine for a launcher; raise for longer answers.
- `thinking: {"type": "adaptive"}` lets Opus 4.x decide how much to think. Omit it
  (or `{"type": "disabled"}`) if you want fastest, no-thinking replies.
- **Do not** send `temperature` / `top_p` / `top_k` or `budget_tokens` to Opus
  4.7/4.8 — they return 400. Adaptive thinking replaces `budget_tokens`.
- Conversation is stateless: resend the full `messages` history each turn.

## Swift client sketch (streaming)

```swift
struct ChatService {
    func stream(prompt: String, accessToken: String,
                model: String = "claude-opus-4-8") -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 4096,
                        "stream": true,
                        "thinking": ["type": "adaptive"],
                        "messages": [["role": "user", "content": prompt]],
                    ])

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw ChatError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
                    }

                    for try await line in bytes.lines {
                        // SSE: lines look like `data: {json}`; ignore `event:` lines & blanks
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if json == "[DONE]" { break }
                        if let text = Self.textDelta(fromSSE: json) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
```

## SSE event shapes to handle

The stream is a sequence of typed events; the ones that carry text:

```
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
```

Other events you'll see (and can mostly ignore for v1):
`message_start`, `content_block_start`, `content_block_stop`,
`message_delta` (carries final `stop_reason` + usage), `message_stop`.

```swift
static func textDelta(fromSSE json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          obj["type"] as? String == "content_block_delta",
          let delta = obj["delta"] as? [String: Any],
          delta["type"] as? String == "text_delta"
    else { return nil }
    return delta["text"] as? String
}
```

> When `thinking` is adaptive, you may also receive `thinking_delta` events. For
> v1 we render only `text_delta`; ignore thinking deltas (or show a "thinking…"
> indicator).

## Errors & token refresh

- Before each call, ensure the access token is valid; refresh if near expiry
  (`05-oauth-auth.md`). On 401, refresh once and retry; if it still fails, sign out.
- Handle 429 (rate limit — honor `retry-after`) and 5xx (retry with backoff).
- Surface refusals: `message_delta` may carry `stop_reason: "refusal"`.

## Cost awareness

Opus 4.8 is $5 / $25 per 1M input/output tokens. A launcher makes many small
calls — consider defaulting heavier/longer tasks to Sonnet 4.6 in Settings.

## Related

`05-oauth-auth.md` · `04-spotlight-panel.md` · `11-testing.md`
