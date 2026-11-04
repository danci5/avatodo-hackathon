import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MetaError: Error, Equatable, Sendable, LocalizedError {
    case missingKey, invalidResponse, http(Int), emptyReply, toolLimit
    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Meta API key in Settings."
        case .invalidResponse: "The model returned an unreadable response. Try again."
        case .http(401): "Meta rejected the API key (HTTP 401). Replace it in Settings with the complete key value."
        case .http(403): "Meta denied this request (HTTP 403). Check your account’s model permissions, or try a different network."
        case .http(429): "Meta is busy or your usage limit was reached. Try again shortly."
        case let .http(code): "The model request failed (HTTP \(code))."
        case .emptyReply: "The model did not return a reply. Try again."
        case .toolLimit: "That request needed too many steps. Try a smaller change."
        }
    }
}

public protocol LanguageModel: Sendable {
    func complete(messages: [JSONValue], tools: [JSONValue], key: String) async throws -> JSONValue
}

public struct MetaAccessCheck: Equatable, Sendable {
    public let languageModelAvailable: Bool
    public let imageModelAvailable: Bool
}

/// Allows HTTP behavior to be checked without sending credentials over a network.
public protocol MetaTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

private struct EphemeralMetaTransport: MetaTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = request.timeoutInterval
        config.timeoutIntervalForResource = request.timeoutInterval + 10
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}

public struct MetaClient: LanguageModel, Sendable {
    public static let languageModel = "muse-spark-1.3"
    public static let imageModel = "muse-image-1.0"
    private let transport: any MetaTransport

    public init() { transport = EphemeralMetaTransport() }
    public init(transport: any MetaTransport) { self.transport = transport }

    /// Verifies catalog authentication and listed models, without inference or note context.
    /// A listed model is not a guarantee that a later inference request will be permitted.
    public func checkAccess(key: String) async throws -> MetaAccessCheck {
        let response = try await request(path: "models", payload: nil, key: key, timeout: 30)
        guard let entries = response["data"].array,
              entries.allSatisfy({ $0["id"].string != nil }) else { throw MetaError.invalidResponse }
        let models = Set(entries.compactMap { $0["id"].string })
        return MetaAccessCheck(languageModelAvailable: models.contains(Self.languageModel),
                               imageModelAvailable: models.contains(Self.imageModel))
    }

    public func complete(messages: [JSONValue], tools: [JSONValue], key: String) async throws -> JSONValue {
        try await request(path: "chat/completions", payload: .object([
            "model": .string(Self.languageModel), "messages": .array(messages),
            "tools": .array(tools), "parallel_tool_calls": .bool(false),
            "reasoning_effort": .string("low"), "max_completion_tokens": .number(1600)
        ]), key: key)
    }

    public func generateCharacter(description: String, key: String) async throws -> Data {
        let prompt = """
        Create an original premium stylized 3D virtual companion: \(description).
        Cute and charming with balanced rounded proportions, soft tactile materials,
        a clear readable silhouette and warm personality. Full body, front-facing,
        centered with generous margins on a pure solid white background. No words,
        no watermark, no extra props beyond those requested. Keep background plain
        for local app preparation. One character only, no panels or sprite sheet.
        """
        let response = try await request(path: "images/generations", payload: .object([
            "model": .string(Self.imageModel), "prompt": .string(prompt), "n": .number(1),
            "output_format": .string("png"), "response_format": .string("b64_json")
        ]), key: key, timeout: 180)
        guard let item = response["data"].array?.first,
              let b64 = item["b64_json"].string, let data = Data(base64Encoded: b64),
              data.count <= 16_000_000 else { throw MetaError.invalidResponse }
        return data
    }

    private func request(path: String, payload: JSONValue?, key: String, timeout: TimeInterval = 65) async throws -> JSONValue {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MetaError.missingKey }
        guard !trimmed.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 33 || $0 > 126 } != false })
        else { throw MetaError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.meta.ai/v1/" + path)!)
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer " + trimmed, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
        }
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MetaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MetaError.http(http.statusCode) }
        // Do not include provider bodies or authorization headers in errors/logs.
        guard data.count <= 24_000_000 else { throw MetaError.invalidResponse }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw MetaError.invalidResponse }
    }
}
