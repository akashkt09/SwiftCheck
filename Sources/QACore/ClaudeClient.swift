import Foundation

public struct ClaudeResponse {
    public let text: String
    public let usage: TokenUsage
    public let model: String
}

public enum ClaudeError: Error {
    case requestFailed(status: Int, message: String)
    case invalidResponse
}

public final class ClaudeClient {
    public let usage = UsageTracker()

    private let apiKey: String
    private let session: URLSession

    // Why: the key must come from the environment or the dedicated credentials file — never hardcoded or
    // committed. The environment variable always wins when set; the file is only a fallback for when it isn't.
    public init?(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialsPath: String = credentialsFilePath,
        session: URLSession = .shared
    ) {
        if let apiKey = environment["ANTHROPIC_API_KEY"], !apiKey.isEmpty {
            self.apiKey = apiKey
        } else if let apiKey = readAPIKeyFromCredentialsFile(at: credentialsPath) {
            self.apiKey = apiKey
        } else {
            return nil
        }
        self.session = session
    }

    // Why: `images`, when non-empty, are sent alongside the text as vision content blocks (one message can
    // hold several — e.g. a sequence of screenshots taken over time) — the only other shape this client
    // needs beyond plain text-in/text-out.
    public func send(
        system: String,
        userMessage: String,
        model: String,
        maxTokens: Int = 1024,
        images: [Data] = [],
        imageMediaType: String = "image/png"
    ) async throws -> ClaudeResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let content: Any
        if !images.isEmpty {
            var blocks: [[String: Any]] = images.map { data in
                ["type": "image", "source": ["type": "base64", "media_type": imageMediaType, "data": data.base64EncodedString()]]
            }
            blocks.append(["type": "text", "text": userMessage])
            content = blocks
        } else {
            content = userMessage
        }

        // Why: cache_control on the system block lets a stable system prompt be cached across calls.
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                ["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]
            ],
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw ClaudeError.requestFailed(status: (response as? HTTPURLResponse)?.statusCode ?? -1, message: message)
        }

        let result = try Self.parse(data: data, model: model)
        // Why: every call logs tokens + estimated cost, per CLAUDE.md — not opt-in by the caller.
        let cost = usage.record(result.usage, model: model)
        print(Self.logLine(for: result, cost: cost, tracker: usage))
        return result
    }

    private static func parse(data: Data, model: String) throws -> ClaudeResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeError.invalidResponse
        }

        let content = json["content"] as? [[String: Any]] ?? []
        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()

        let usageJSON = json["usage"] as? [String: Any] ?? [:]
        let tokenUsage = TokenUsage(
            inputTokens: usageJSON["input_tokens"] as? Int ?? 0,
            outputTokens: usageJSON["output_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: usageJSON["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadInputTokens: usageJSON["cache_read_input_tokens"] as? Int ?? 0
        )
        return ClaudeResponse(text: text, usage: tokenUsage, model: model)
    }

    private static func logLine(for response: ClaudeResponse, cost: Double, tracker: UsageTracker) -> String {
        String(
            format: "[%@] input=%d output=%d cost=$%.4f | total: input=%d output=%d cost=$%.4f",
            response.model,
            response.usage.inputTokens,
            response.usage.outputTokens,
            cost,
            tracker.totalInputTokens,
            tracker.totalOutputTokens,
            tracker.totalCost
        )
    }
}
