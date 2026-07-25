import Dependencies
import Foundation

// The ONLY caller of /chat (C5). Mirrors LiveExtractionClient: sends the request, decodes the
// envelope strictly, maps proxy errors to typed ChatError values. No key, no prompt text — both
// live server-side.

nonisolated protocol ChatServicing: Sendable {
    func send(_ request: ChatRequest) async throws -> ChatEnvelope
}

nonisolated struct ChatEndpoint: Sendable {
    var baseURL: URL
    var accessToken: @Sendable () async throws -> String
}

nonisolated struct LiveChatClient: ChatServicing {
    let endpoint: ChatEndpoint
    var urlSession: URLSession = .shared

    private struct ProxyErrorBody: Decodable {
        struct ProxyError: Decodable {
            let code: String
            let message: String?
            let serverVersion: Int?
        }
        let error: ProxyError
    }

    func send(_ request: ChatRequest) async throws -> ChatEnvelope {
        var urlRequest = URLRequest(url: endpoint.baseURL.appending(path: "functions/v1/chat"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token: String
        do {
            token = try await endpoint.accessToken()
        } catch {
            throw ChatError.unauthorized
        }
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw ChatError.transport(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.transport(underlying: URLError(.badServerResponse))
        }

        if http.statusCode == 200 {
            // Strict decode + request validation (NN#7): a malformed or mis-echoed envelope
            // throws loudly — the reply bubble shows the retry affordance, nothing is applied.
            let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
            return try envelope.validated(for: request)
        }

        let body = try? JSONDecoder().decode(ProxyErrorBody.self, from: data)
        switch (body?.error.code, http.statusCode) {
        case ("rate_limited", _), (_, 429):
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ChatError.rateLimited(retryAfter: retryAfter)
        case ("schema_mismatch", _):
            throw ChatError.schemaMismatch(serverVersion: body?.error.serverVersion ?? 0)
        case ("upstream_unavailable", _), (_, 502), (_, 503), (_, 529):
            throw ChatError.upstreamUnavailable
        case ("unauthorized", _), (_, 401), (_, 403):
            throw ChatError.unauthorized
        default:
            throw ChatError.transport(
                underlying: URLError(.badServerResponse, userInfo: ["statusCode": http.statusCode])
            )
        }
    }
}

/// Fails loudly instead of pretending chat works — the UI shows the honest offline line and the
/// composer still files to the utterance queue (words are never lost).
nonisolated struct UnconfiguredChatClient: ChatServicing {
    func send(_ request: ChatRequest) async throws -> ChatEnvelope {
        struct NotConfigured: Error {}
        throw ChatError.transport(underlying: NotConfigured())
    }
}

private nonisolated enum ChatClientKey: DependencyKey {
    static var liveValue: any ChatServicing { UnconfiguredChatClient() }
    static var testValue: any ChatServicing { UnconfiguredChatClient() }
}

nonisolated extension DependencyValues {
    var chatClient: any ChatServicing {
        get { self[ChatClientKey.self] }
        set { self[ChatClientKey.self] = newValue }
    }
}
