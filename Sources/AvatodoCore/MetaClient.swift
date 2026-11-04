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
        case .http(401), .http(403): "Check your Meta key and model access in Settings."
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

public struct MetaClient: LanguageModel, Sendable {
    public static let languageModel = "muse-spark-1.3"
    public static let imageModel = "muse-image-1.0"
    public init() {}

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

    private func request(path: String, payload: JSONValue, key: String, timeout: TimeInterval = 65) async throws -> JSONValue {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MetaError.missingKey }
        guard !trimmed.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 33 || $0 > 126 } != false })
        else { throw MetaError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.meta.ai/v1/" + path)!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer " + trimmed, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 10
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MetaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MetaError.http(http.statusCode) }
        // Do not include provider bodies or authorization headers in errors/logs.
        guard data.count <= 24_000_000 else { throw MetaError.invalidResponse }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw MetaError.invalidResponse }
    }
}
