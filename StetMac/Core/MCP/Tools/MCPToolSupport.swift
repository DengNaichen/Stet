import Foundation
import MCP

enum MCPToolSupport {
    nonisolated static func error(_ message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }

    static func result<Output: Codable>(
        text: String,
        output: Output
    ) throws -> CallTool.Result {
        try CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: output,
            isError: false
        )
    }

    nonisolated static func requiredString(_ key: String, in values: [String: Value]) throws -> String {
        guard let value = values[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            throw MCPToolInputError.invalid("\(key) is required.")
        }
        return value
    }

    nonisolated static func bool(_ key: String, in values: [String: Value], default defaultValue: Bool) throws -> Bool {
        guard let value = values[key] else { return defaultValue }
        guard let parsed = value.boolValue else {
            throw MCPToolInputError.invalid("\(key) must be a boolean.")
        }
        return parsed
    }

    nonisolated static func date(
        _ key: String,
        in values: [String: Value],
        required: Bool = true,
        timeZone: TimeZone = .current
    ) throws -> Date? {
        guard let raw = values[key]?.stringValue else {
            if required { throw MCPToolInputError.invalid("\(key) is required.") }
            return nil
        }
        if let parsed = ISO8601DateFormatter.withFractionalSeconds.date(from: raw)
            ?? ISO8601DateFormatter.internetDateTime.date(from: raw)
        {
            return parsed
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = raw.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm:ss"
        guard let parsed = formatter.date(from: raw) else {
            throw MCPToolInputError.invalid("\(key) must be an ISO 8601 date or date-time.")
        }
        return parsed
    }

    nonisolated static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter.internetDateTime.string(from: date)
    }
}

enum MCPToolInputError: LocalizedError, Sendable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

private extension ISO8601DateFormatter {
    nonisolated static var internetDateTime: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    nonisolated static var withFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
