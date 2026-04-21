import Foundation

struct RelayTextRewriteService: TextRewriteService {
    private struct TimingBreakdown {
        var totalMs: Double?
        var budgetMs: Double?
        var rewriteMs: Double?
        var upstreamMs: Double?
    }

    private struct RequestBody: Encodable {
        let text: String
        let audience: AppAudience?
        let preferredSpellings: [String]
        let additionalContext: String?
    }

    private struct SuccessResponse: Decodable {
        let text: String
    }

    private struct ErrorResponse: Decodable {
        let code: String?
        let message: String
        let request_id: String?
    }

    private enum RequestPolicy {
        static let timeoutInterval: TimeInterval = 60
    }

    private let authentication: RelayAuthenticationContext
    private let session: URLSession

    nonisolated init(
        authentication: RelayAuthenticationContext,
        session: URLSession = .shared
    ) {
        self.authentication = authentication
        self.session = session
    }

    func rewrite(_ request: TextRewriteRequest) async throws -> String {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientRequestID = UUID().uuidString
        let urlRequest = try Self.makeRequest(
            authentication: authentication,
            payload: RequestBody(
                text: trimmedText,
                audience: request.audience,
                preferredSpellings: request.preferredSpellings,
                additionalContext: Self.normalizedText(request.additionalContext)
            ),
            clientRequestID: clientRequestID
        )
        let startedAt = ProcessInfo.processInfo.systemUptime

        AppLogger.info(
            "Relay rewrite request started requestID=\(clientRequestID) url=\(urlRequest.url?.absoluteString ?? "unknown") textChars=\(trimmedText.count) audience=\(request.audience?.rawValue ?? "none") preferredSpellingsCount=\(request.preferredSpellings.count) additionalContextChars=\(request.additionalContext?.count ?? 0)",
            category: .perfTrace
        )

        do {
            let (responseData, response) = try await session.data(for: urlRequest)
            let clientRoundTripMs = Self.elapsedMilliseconds(since: startedAt)

            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.error(
                    "Relay rewrite returned a non-HTTP response requestID=\(clientRequestID) clientRoundTripMs=\(Self.formatMilliseconds(clientRoundTripMs))",
                    category: .perfTrace
                )
                throw AIExecutionError.relayInvocationFailed(
                    statusCode: nil,
                    message: "The relay returned an invalid response.",
                    requestID: nil
                )
            }

            let serverTimingHeader = httpResponse.value(forHTTPHeaderField: "x-stet-timing")
            let timingBreakdown = Self.parseTimingBreakdown(from: serverTimingHeader)

            AppLogger.info(
                "Relay rewrite response received requestID=\(clientRequestID) status=\(httpResponse.statusCode) responseBytes=\(responseData.count) clientRoundTripMs=\(Self.formatMilliseconds(clientRoundTripMs)) serverRequestID=\(httpResponse.value(forHTTPHeaderField: "x-request-id") ?? "missing") serverTotalMs=\(Self.formatOptionalMilliseconds(timingBreakdown.totalMs)) serverBudgetMs=\(Self.formatOptionalMilliseconds(timingBreakdown.budgetMs)) serverRewriteMs=\(Self.formatOptionalMilliseconds(timingBreakdown.rewriteMs)) serverUpstreamMs=\(Self.formatOptionalMilliseconds(timingBreakdown.upstreamMs)) serverTiming=\(serverTimingHeader ?? "unavailable")",
                category: .perfTrace
            )

            guard (200...299).contains(httpResponse.statusCode) else {
                AppLogger.error(
                    "Relay rewrite returned an error response requestID=\(clientRequestID) status=\(httpResponse.statusCode) clientRoundTripMs=\(Self.formatMilliseconds(clientRoundTripMs)) serverTiming=\(serverTimingHeader ?? "unavailable") responsePreview=\(Self.responsePreview(from: responseData))",
                    category: .perfTrace
                )
                throw Self.mapRelayError(
                    statusCode: httpResponse.statusCode,
                    responseData: responseData,
                    fallbackRequestID: httpResponse.value(forHTTPHeaderField: "x-request-id")
                )
            }

            let payload = try JSONDecoder().decode(SuccessResponse.self, from: responseData)
            let rewrittenText = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rewrittenText.isEmpty else {
                throw AIExecutionError.relayInvocationFailed(
                    statusCode: httpResponse.statusCode,
                    message: "The relay response did not contain any text.",
                    requestID: httpResponse.value(forHTTPHeaderField: "x-request-id")
                )
            }

            AppLogger.info(
                "Relay rewrite completed requestID=\(clientRequestID) textChars=\(rewrittenText.count) clientRoundTripMs=\(Self.formatMilliseconds(clientRoundTripMs)) serverTotalMs=\(Self.formatOptionalMilliseconds(timingBreakdown.totalMs)) serverRewriteMs=\(Self.formatOptionalMilliseconds(timingBreakdown.rewriteMs)) serverUpstreamMs=\(Self.formatOptionalMilliseconds(timingBreakdown.upstreamMs))",
                category: .perfTrace
            )

            return rewrittenText
        } catch let error as AIExecutionError {
            AppLogger.error(
                "Relay rewrite failed with managed relay error requestID=\(clientRequestID) error=\(error.localizedDescription)",
                category: .perfTrace
            )
            throw error
        } catch let error as URLError {
            AppLogger.error(
                "Relay rewrite failed with URL error requestID=\(clientRequestID) code=\(error.code.rawValue) description=\(error.localizedDescription)",
                category: .perfTrace
            )
            throw AIExecutionError.relayInvocationFailed(
                statusCode: nil,
                message: error.localizedDescription,
                requestID: nil
            )
        } catch {
            AppLogger.error(
                "Relay rewrite failed with unexpected client error requestID=\(clientRequestID) type=\(String(describing: type(of: error))) description=\(error.localizedDescription)",
                category: .perfTrace
            )
            throw AIExecutionError.relayInvocationFailed(
                statusCode: nil,
                message: error.localizedDescription,
                requestID: nil
            )
        }
    }

    private static func parseTimingBreakdown(from headerValue: String?) -> TimingBreakdown {
        guard let headerValue else { return TimingBreakdown() }

        var breakdown = TimingBreakdown()

        for component in headerValue.split(separator: ",") {
            let pair = component.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2, let value = Double(pair[1]) else { continue }

            switch pair[0] {
            case "total":
                breakdown.totalMs = value
            case "budget":
                breakdown.budgetMs = value
            case "rewrite":
                breakdown.rewriteMs = value
            case "upstream":
                breakdown.upstreamMs = value
            default:
                break
            }
        }

        return breakdown
    }

    private static func elapsedMilliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private static func formatMilliseconds(_ duration: Double) -> String {
        String(format: "%.1f", duration)
    }

    private static func formatOptionalMilliseconds(_ duration: Double?) -> String {
        guard let duration else { return "unknown" }
        return formatMilliseconds(duration)
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return nil
        }

        return text
    }

    private static func makeRequest(
        authentication: RelayAuthenticationContext,
        payload: RequestBody,
        clientRequestID: String
    ) throws -> URLRequest {
        let url = authentication.relayBaseURL.appendingPathComponent("text/rewrites")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = RequestPolicy.timeoutInterval
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authentication.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(authentication.publishableKey, forHTTPHeaderField: "Apikey")
        request.setValue(clientRequestID, forHTTPHeaderField: "x-request-id")
        return request
    }

    private static func mapRelayError(
        statusCode: Int,
        responseData: Data,
        fallbackRequestID: String?
    ) -> AIExecutionError {
        if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: responseData) {
            let message: String
            if let code = payload.code, !code.isEmpty {
                message = "[\(code)] \(payload.message)"
            } else {
                message = payload.message
            }

            return .relayInvocationFailed(
                statusCode: statusCode,
                message: message,
                requestID: payload.request_id ?? fallbackRequestID
            )
        }

        return .relayInvocationFailed(
            statusCode: statusCode,
            message: responsePreview(from: responseData),
            requestID: fallbackRequestID
        )
    }

    private static func responsePreview(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return "The relay returned an empty error response."
        }

        return text
    }
}
