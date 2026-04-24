import Foundation

protocol ProviderCredentialValidating: Sendable {
    func validateCredential(apiKey: String, provider: DictationProvider) async throws
}

struct ProviderCredentialValidationService: ProviderCredentialValidating, Sendable {
    private struct ProviderAPIErrorEnvelope: Decodable {
        let error: ProviderAPIErrorBody
    }

    private struct ProviderAPIErrorBody: Decodable {
        let message: String?
    }

    private let session: URLSession
    private let timeoutInterval: TimeInterval

    init(
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 15
    ) {
        self.session = session
        self.timeoutInterval = timeoutInterval
    }

    func validateCredential(apiKey: String, provider: DictationProvider) async throws {
        let endpoint = OpenAICompatibleProviderEndpointConfiguration(
            provider: provider,
            apiKey: apiKey
        )

        switch provider {
        case .openAI:
            try await validateOpenAICredential(endpoint: endpoint)
        case .groq:
            try await validateGroqCredential(endpoint: endpoint)
        case .appleIntelligence:
            return
        }
    }

    private func validateOpenAICredential(
        endpoint: OpenAICompatibleProviderEndpointConfiguration
    ) async throws {
        let request = try makeOpenAIModelsRequest(endpoint: endpoint)
        try await performValidationRequest(request, provider: .openAI)
    }

    private func validateGroqCredential(
        endpoint: OpenAICompatibleProviderEndpointConfiguration
    ) async throws {
        let request = try makeGroqModelsRequest(endpoint: endpoint)
        try await performValidationRequest(request, provider: .groq)
    }

    private func performValidationRequest(
        _ request: URLRequest,
        provider: DictationProvider
    ) async throws {
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
    }

    private func makeOpenAIModelsRequest(
        endpoint: OpenAICompatibleProviderEndpointConfiguration
    ) throws -> URLRequest {
        var request = try makeBaseModelsRequest(endpoint: endpoint)
        if let organizationID = trim(endpoint.organizationID) {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let projectID = trim(endpoint.projectID) {
            request.setValue(projectID, forHTTPHeaderField: "OpenAI-Project")
        }
        return request
    }

    private func makeGroqModelsRequest(
        endpoint: OpenAICompatibleProviderEndpointConfiguration
    ) throws -> URLRequest {
        try makeBaseModelsRequest(endpoint: endpoint)
    }

    private func makeBaseModelsRequest(
        endpoint: OpenAICompatibleProviderEndpointConfiguration
    ) throws -> URLRequest {
        let trimmedKey = endpoint.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIError.missingAPIKey(provider: endpoint.provider)
        }

        let modelsURL = normalizedBaseURL(endpoint.baseURL).appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func normalizedBaseURL(_ baseURL: URL) -> URL {
        baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
    }

    private func trim(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }

        return value
    }

    private func parseErrorMessage(from data: Data) -> String? {
        let envelope = try? JSONDecoder().decode(ProviderAPIErrorEnvelope.self, from: data)
        let message = envelope?.error.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : nil
    }
}
