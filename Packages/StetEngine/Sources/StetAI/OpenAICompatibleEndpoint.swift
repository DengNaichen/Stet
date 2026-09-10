import Foundation
import StetCore

public enum OpenAICompatibleBaseURL {
    public static func normalize(_ raw: String, provider: DictationProvider = .custom) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenAIError.invalidBaseURL(provider: provider)
        }

        let withScheme: String
        if let schemeRange = trimmed.range(of: "://"), schemeRange.lowerBound > trimmed.startIndex {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty
        else {
            throw OpenAIError.invalidBaseURL(provider: provider)
        }

        components.scheme = scheme
        if components.path.isEmpty || components.path == "/" {
            components.path = "/v1"
        }

        guard let url = components.url else {
            throw OpenAIError.invalidBaseURL(provider: provider)
        }
        return url
    }
}

public enum OpenAICompatibleModelCatalog {
    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String?
        }

        let data: [Model]?
    }

    public static func modelIDs(from data: Data) -> [String] {
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }

        var seen = Set<String>()
        var ids: [String] = []
        for model in response.data ?? [] {
            let id = model.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            ids.append(id)
        }
        return ids.sorted()
    }
}

public protocol OpenAICompatibleModelProbing: Sendable {
    func listModels(baseURL: URL, apiKey: String) async throws -> [String]
}

public struct OpenAICompatibleModelProbe: OpenAICompatibleModelProbing {
    private struct ProviderAPIErrorEnvelope: Decodable {
        let error: ProviderAPIErrorBody
    }

    private struct ProviderAPIErrorBody: Decodable {
        let message: String?
    }

    private let session: URLSession
    private let timeoutInterval: TimeInterval
    private let provider: DictationProvider

    public init(
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 15,
        provider: DictationProvider = .custom
    ) {
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.provider = provider
    }

    public func listModels(baseURL: URL, apiKey: String) async throws -> [String] {
        let modelsURL = normalizedBaseURL(baseURL).appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse(provider: provider)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message =
                parseErrorMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIError.api(
                provider: provider,
                statusCode: httpResponse.statusCode,
                message: message
            )
        }

        return OpenAICompatibleModelCatalog.modelIDs(from: data)
    }

    private func normalizedBaseURL(_ baseURL: URL) -> URL {
        baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
    }

    private func parseErrorMessage(from data: Data) -> String? {
        let envelope = try? JSONDecoder().decode(ProviderAPIErrorEnvelope.self, from: data)
        let message = envelope?.error.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : nil
    }
}
