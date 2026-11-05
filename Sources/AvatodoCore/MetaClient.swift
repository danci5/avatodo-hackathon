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

public enum MetaReasoningModel: String, CaseIterable, Codable, Sendable {
    case spark = "muse-spark-1.3"
    case wonder = "muse-wonder-1.0"

    public var title: String { self == .spark ? "Muse Spark" : "Muse Wonder" }
    public init(savedValue: String?) { self = savedValue.flatMap(Self.init(rawValue:)) ?? .spark }
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
    public static let languageModel = MetaReasoningModel.spark.rawValue
    public static let imageModel = "muse-image-1.0"
    public let reasoningModel: MetaReasoningModel
    private let transport: any MetaTransport

    public init(reasoningModel: MetaReasoningModel = .spark) {
        self.reasoningModel = reasoningModel; transport = EphemeralMetaTransport()
    }
    public init(reasoningModel: MetaReasoningModel = .spark, transport: any MetaTransport) {
        self.reasoningModel = reasoningModel; self.transport = transport
    }

    /// Verifies catalog authentication and listed models, without inference or note context.
    /// A listed model is not a guarantee that a later inference request will be permitted.
    public func checkAccess(key: String) async throws -> MetaAccessCheck {
        let response = try await request(path: "models", payload: nil, key: key, timeout: 30)
        guard let entries = response["data"].array,
              entries.allSatisfy({ $0["id"].string != nil }) else { throw MetaError.invalidResponse }
        let models = Set(entries.compactMap { $0["id"].string })
        return MetaAccessCheck(languageModelAvailable: models.contains(reasoningModel.rawValue),
                               imageModelAvailable: models.contains(Self.imageModel))
    }

    public func complete(messages: [JSONValue], tools: [JSONValue], key: String) async throws -> JSONValue {
        try await request(path: "chat/completions", payload: .object([
            "model": .string(reasoningModel.rawValue), "messages": .array(messages),
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

    public func generateCharacterAnimations(reference: Data, key: String) async throws -> Data {
        guard reference.count <= 4_000_000 else { throw MetaError.invalidResponse }
        let prompt = """
        Create a production animation sprite sheet of EXACTLY the SAME original 3D companion in
        this reference. Preserve its identity, colors, materials, accessories and proportions.
        Landscape canvas, EXACTLY FIVE COLUMNS AND FOUR ROWS: TWENTY equal cells. No grid
        lines, labels, numbers, text or borders. Pure white background. One full-body character per
        cell, same front-facing camera, lighting, body scale and horizontal center. Keep five percent
        white margin on every side of every cell. Feet share a ground line; head scale stays fixed.
        Preserve the reference anatomy and accessories. Neighboring frames differ only a little.
        Adapt gestures to this character's existing anatomy. If it has no ears, listening means an
        attentive head/body tilt. If it has no arms/legs, dancing is a clear whole-body wiggle;
        do not invent limbs. If it has no visible mouth, use subtle existing face/head expressions
        for speaking. Never add human anatomy, a mouth, ears or accessories absent in the reference.
        Row 1 (FIVE cells): neutral seated friendly smile; attentive listening with a slight head
        tilt and ONLY ONE hand/paw cupped beside its ear, the OTHER paw DOWN; thoughtful hand/paw
        at chin; neutral seated blink; relaxed happy smile. In listening, do NOT touch, lift or adjust
        glasses, hats or accessories. Keep paws away from glasses. If ears cannot be reached without
        covering an accessory, use a gentle attentive head tilt with BOTH paws DOWN instead.
        Row 2 (FIVE cells): mouth-only speaking sequence. COPY the SAME neutral seated body,
        paws DOWN and head placement in ALL FIVE cells. Change ONLY mouth: closed, barely open,
        moderately open, barely open, closed smile. NO paw near chin, NO paw movement in this row.
        Row 3 (FIVE cells): ONE clearly recognizable standing dance loop, arms/paws raised and
        feet doing alternating small steps. First: lean left with left foot forward. Second: pass
        through center with knees slightly bent. Third: lean right with right foot forward. Fourth:
        pass through center with arms/paws raised. Fifth: return close to the first left-step pose.
        Keep head scale consistent; do not replace dancing with seated waving. No camera movement.
        Row 4 (FIVE cells): gentle giggle sequence. Identical seated body with paws down throughout:
        small smile, beginning a giggle, warm open-mouth laugh, easing to a giggle, relaxed smile.
        Count TWENTY characters: FOUR separate rows with FIVE characters in EACH row. Not 4x4.
        One consistent premium 3D character. No devices, UI, scenery, extra props or extra characters.
        """
        let response = try await request(path: "images/edits", payload: .object([
            "model": .string(Self.imageModel), "prompt": .string(prompt), "size": .string("1280x1024"),
            "images": .array([.object(["image_url": .string("data:image/png;base64," + reference.base64EncodedString())])]),
            "n": .number(1), "output_format": .string("png"), "response_format": .string("b64_json")
        ]), key: key, timeout: 180)
        guard let value = response["data"].array?.first?["b64_json"].string,
              let data = Data(base64Encoded: value), data.count <= 16_000_000 else { throw MetaError.invalidResponse }
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
