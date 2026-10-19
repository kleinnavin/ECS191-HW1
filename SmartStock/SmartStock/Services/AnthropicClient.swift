//
//  AnthropicClient.swift
//  SmartStock
//

import Foundation

enum AnthropicError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String?)
    case refused
    case truncated
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No Anthropic API key found. Add it to Config/Secrets.xcconfig and rebuild."
        case .http(let status, _) where status == 401:
            "Anthropic rejected the API key (401)."
        case .http(let status, _) where status == 429:
            "Anthropic rate limit reached. Try again in a minute."
        case .http(let status, _) where status == 529:
            "Claude is overloaded right now. Try again shortly."
        case .http(let status, let message):
            "Claude request failed (\(status))" + (message.map { ": \($0)" } ?? ".")
        case .refused:
            "Claude declined to analyze this portfolio."
        case .truncated:
            "Claude's response was cut off. Try again."
        case .badResponse:
            "Claude returned a response the app couldn't read."
        }
    }
}

/// Minimal client for the Claude Messages API. There is no official Swift
/// SDK, so this calls the REST endpoint directly with URLSession.
struct AnthropicClient {
    static let model = "claude-opus-5-5"

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String? = AnthropicClient.bundledAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// The key injected into Info.plist from Secrets.xcconfig at build time.
    static var bundledAPIKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "AnthropicAPIKey") as? String else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unset build setting expands to "", and the template ships a placeholder.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), trimmed != "your_anthropic_api_key_here" else { return nil }
        return trimmed
    }

    var hasAPIKey: Bool { apiKey != nil }

    /// Sends one user message and returns Claude's reply as JSON matching
    /// `schema` (structured outputs guarantee the text parses against it).
    func structuredResponse<T: Decodable>(
        _ type: T.Type,
        system: String,
        prompt: String,
        schema: [String: Any],
        effort: String = "medium"
    ) async throws -> T {
        guard let apiKey else { throw AnthropicError.missingAPIKey }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            // If a safety classifier declines the request, retry it server-side
            // on Anthropic's recommended fallback model instead of failing.
            "fallbacks": "default",
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Thinking can take a while; the default 60-second timeout is too short.
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
            throw AnthropicError.http(status: http.statusCode, message: message)
        }

        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        switch message.stopReason {
        case "refusal": throw AnthropicError.refused
        case "max_tokens": throw AnthropicError.truncated
        default: break
        }
        guard let text = message.content.first(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(T.self, from: json)
        else { throw AnthropicError.badResponse }
        return result
    }
}

private struct MessageResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    let content: [Block]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

private struct ErrorResponse: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}
