import Foundation
import OpenAI

extension OpenAIConfiguration {
    nonisolated func sdkConfiguration(
        additionalHeaders: [String: String] = [:],
        timeoutInterval: TimeInterval? = nil
    ) throws -> OpenAI.Configuration {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIError.missingAPIKey(provider: provider)
        }

        let normalizedBaseURL = baseURL.hasDirectoryPath
            ? baseURL
            : baseURL.appendingPathComponent("")

        guard let components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              let host = components.host else {
            throw OpenAIError.invalidBaseURL(provider: provider)
        }

        var customHeaders: [String: String] = [:]

        if let projectID = trimmedValue(projectID) {
            customHeaders["OpenAI-Project"] = projectID
        }

        for (header, value) in additionalHeaders {
            if let trimmedValue = trimmedValue(value) {
                customHeaders[header] = trimmedValue
            }
        }

        return OpenAI.Configuration(
            token: trimmedKey,
            organizationIdentifier: trimmedValue(organizationID),
            host: host,
            port: components.port ?? Self.defaultPort(for: scheme),
            scheme: scheme,
            basePath: components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath,
            timeoutInterval: timeoutInterval ?? 60,
            customHeaders: customHeaders,
            parsingOptions: Self.requiresRelaxedParsing(for: normalizedBaseURL) ? .relaxed : []
        )
    }

    nonisolated var provider: DictationProvider {
        Self.isGroqBaseURL(baseURL) ? .groq : .openAI
    }

    nonisolated private static func requiresRelaxedParsing(for baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return host != "api.openai.com" && !host.hasSuffix(".openai.com")
    }

    nonisolated private static func defaultPort(for scheme: String) -> Int {
        switch scheme.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return 443
        }
    }

    nonisolated private func trimmedValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}
