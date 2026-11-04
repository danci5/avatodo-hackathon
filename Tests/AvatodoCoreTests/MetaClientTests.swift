import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import AvatodoCore

private actor FixtureMetaTransport: MetaTransport {
    let status: Int
    let body: String
    var requests: [URLRequest] = []

    init(status: Int = 200, body: String) { self.status = status; self.body = body }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}

@Test func connectionCheckAuthenticatesWithoutSendingNotesOrInference() async throws {
    let transport = FixtureMetaTransport(body: #"{"data":[{"id":"muse-spark-1.3"},{"id":"muse-image-1.0"}]}"#)
    let check = try await MetaClient(transport: transport).checkAccess(key: "  fixture-key\n")
    #expect(check.languageModelAvailable && check.imageModelAvailable)
    let requests = await transport.requests
    #expect(requests.count == 1)
    let request = try #require(requests.first)
    #expect(request.url?.absoluteString == "https://api.meta.ai/v1/models")
    #expect(request.httpMethod == "GET")
    #expect(request.httpBody == nil)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
}

@Test func authenticationAndAccessErrorsKeepTheirStatusAndDiscardProviderContent() async throws {
    for status in [401, 403] {
        let providerOnlyText = "fixture-sensitive-provider-content"
        let transport = FixtureMetaTransport(status: status, body: #"{"error":{"message":""# + providerOnlyText + #""}}"#)
        do {
            _ = try await MetaClient(transport: transport).checkAccess(key: "fixture-key")
            Issue.record("An authorization failure must not report a successful connection")
        } catch let error as MetaError {
            #expect(error == .http(status))
            #expect(error.errorDescription?.contains("HTTP \(status)") == true)
            #expect(error.errorDescription?.contains(providerOnlyText) == false)
            #expect(error.errorDescription?.contains("fixture-key") == false)
        }
    }
    #expect(MetaError.http(401).errorDescription != MetaError.http(403).errorDescription)
}

@Test func invalidLocalKeysDoNotStartARequest() async throws {
    let transport = FixtureMetaTransport(body: #"{"data":[]}"#)
    for key in ["", "   ", "fixture\nbroken", "fixture\tbroken"] {
        await #expect(throws: MetaError.missingKey) {
            try await MetaClient(transport: transport).checkAccess(key: key)
        }
    }
    #expect(await transport.requests.isEmpty)
}

@Test func missingModelsAndMalformedCatalogAreNotReportedAsFullModelAccess() async throws {
    let empty = try await MetaClient(transport: FixtureMetaTransport(body: #"{"data":[]}"#)).checkAccess(key: "fixture-key")
    #expect(!empty.languageModelAvailable && !empty.imageModelAvailable)
    await #expect(throws: MetaError.invalidResponse) {
        try await MetaClient(transport: FixtureMetaTransport(body: #"{"data":[{"id":2}]}"#)).checkAccess(key: "fixture-key")
    }
}

@Test func inferenceStillUsesTheOriginalPostContract() async throws {
    let transport = FixtureMetaTransport(body: #"{"choices":[{"message":{"content":"Hello"}}]}"#)
    let messages: [JSONValue] = [.object(["role": .string("user"), "content": .string("Hello")])]
    _ = try await MetaClient(transport: transport).complete(messages: messages, tools: [], key: "fixture-key")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.absoluteString == "https://api.meta.ai/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    #expect(body["model"].string == MetaClient.languageModel)
    #expect(body["messages"].array == messages)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
}

@Test func reasoningSelectionIsAllowlistedAndDefaultsToSpark() async throws {
    #expect(MetaReasoningModel(savedValue: nil) == .spark)
    #expect(MetaReasoningModel(savedValue: "unknown-model") == .spark)
    #expect(MetaReasoningModel(savedValue: "muse-wonder-1.0") == .wonder)
    for choice in MetaReasoningModel.allCases {
        let transport = FixtureMetaTransport(body: #"{"choices":[{"message":{"content":"Hello"}}]}"#)
        _ = try await MetaClient(reasoningModel: choice, transport: transport)
            .complete(messages: [], tools: [], key: "fixture-key")
        let request = try #require(await transport.requests.first)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["model"].string == choice.rawValue)
        #expect(body["parallel_tool_calls"].bool == false)
    }
}

@Test func connectionCheckReportsTheSelectedReasoningModel() async throws {
    let catalog = #"{"data":[{"id":"muse-spark-1.3"},{"id":"muse-image-1.0"}]}"#
    let wonder = try await MetaClient(reasoningModel: .wonder, transport: FixtureMetaTransport(body: catalog))
        .checkAccess(key: "fixture-key")
    #expect(!wonder.languageModelAvailable && wonder.imageModelAvailable)
    let spark = try await MetaClient(reasoningModel: .spark, transport: FixtureMetaTransport(body: catalog))
        .checkAccess(key: "fixture-key")
    #expect(spark.languageModelAvailable && spark.imageModelAvailable)
}
