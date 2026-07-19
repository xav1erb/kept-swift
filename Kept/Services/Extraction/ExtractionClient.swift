import Dependencies
import Foundation

// The ONLY caller of the proxy (C1/C5). The client sends the request, decodes the envelope
// strictly, and maps proxy errors to typed ExtractionError values. It never sees an API key,
// never assembles a prompt — both live server-side (C5).

nonisolated protocol ExtractionServicing: Sendable {
    func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope
}

/// Endpoint wiring. The Supabase URL + user JWT arrive with the M2 sign-in slice
/// (M1-CONTRACTS §8.2); until then only tests construct one.
nonisolated struct ExtractionEndpoint: Sendable {
    var baseURL: URL
    var accessToken: @Sendable () async throws -> String
}

nonisolated struct LiveExtractionClient: ExtractionServicing {
    let endpoint: ExtractionEndpoint
    var urlSession: URLSession = .shared

    /// The proxy's typed error body (M1-CONTRACTS §3): `{ "error": { "code": "...", ... } }`.
    private struct ProxyErrorBody: Decodable {
        struct ProxyError: Decodable {
            let code: String
            let message: String?
            let serverVersion: Int?
        }
        let error: ProxyError
    }

    func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
        var urlRequest = URLRequest(url: endpoint.baseURL.appending(path: "functions/v1/extract"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token: String
        do {
            token = try await endpoint.accessToken()
        } catch {
            throw ExtractionError.unauthorized
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
            throw ExtractionError.transport(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ExtractionError.transport(underlying: URLError(.badServerResponse))
        }

        if http.statusCode == 200 {
            // Strict decode (NN#7): a malformed envelope throws DecodingError loudly — the
            // caller logs the utteranceId for re-extraction, never applies a partial result.
            return try JSONDecoder().decode(ExtractionEnvelope.self, from: data)
        }

        let body = try? JSONDecoder().decode(ProxyErrorBody.self, from: data)
        switch (body?.error.code, http.statusCode) {
        case ("rate_limited", _), (_, 429):
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ExtractionError.rateLimited(retryAfter: retryAfter)
        case ("schema_mismatch", _):
            throw ExtractionError.schemaMismatch(serverVersion: body?.error.serverVersion ?? 0)
        case ("upstream_unavailable", _), (_, 502), (_, 503), (_, 529):
            throw ExtractionError.upstreamUnavailable
        case ("unauthorized", _), (_, 401), (_, 403):
            throw ExtractionError.unauthorized
        default:
            throw ExtractionError.transport(
                underlying: URLError(.badServerResponse, userInfo: ["statusCode": http.statusCode])
            )
        }
    }
}

/// Placeholder until M2 wires auth: fails loudly instead of pretending extraction works.
nonisolated struct UnconfiguredExtractionClient: ExtractionServicing {
    func extract(_ request: ExtractionRequest) async throws -> ExtractionEnvelope {
        struct NotConfigured: Error {}
        throw ExtractionError.transport(underlying: NotConfigured())
    }
}

private nonisolated enum ExtractionClientKey: DependencyKey {
    static var liveValue: any ExtractionServicing { UnconfiguredExtractionClient() }
    static var testValue: any ExtractionServicing { UnconfiguredExtractionClient() }
}

nonisolated extension DependencyValues {
    var extractionClient: any ExtractionServicing {
        get { self[ExtractionClientKey.self] }
        set { self[ExtractionClientKey.self] = newValue }
    }
}
