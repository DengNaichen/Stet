import Foundation

actor OpenAIClient {
    struct MultipartFile: Sendable {
        var fieldName: String
        var fileURL: URL
        var fileName: String
        var mimeType: String

        init(
            fieldName: String = "file",
            fileURL: URL,
            fileName: String? = nil,
            mimeType: String? = nil
        ) {
            self.fieldName = fieldName
            self.fileURL = fileURL
            self.fileName = fileName ?? fileURL.lastPathComponent
            self.mimeType = mimeType ?? Self.defaultMimeType(for: fileURL)
        }

        private static func defaultMimeType(for fileURL: URL) -> String {
            switch fileURL.pathExtension.lowercased() {
            case "m4a":
                return "audio/m4a"
            case "mp3":
                return "audio/mpeg"
            case "mp4":
                return "audio/mp4"
            case "ogg":
                return "audio/ogg"
            case "wav":
                return "audio/wav"
            case "webm":
                return "audio/webm"
            case "caf":
                return "audio/x-caf"
            default:
                return "application/octet-stream"
            }
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct APIErrorBody: Decodable {
            let message: String?
        }

        let error: APIErrorBody?
        let message: String?
    }

    private let configuration: OpenAIConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: OpenAIConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func sendJSONRequest<Response: Decodable, Body: Encodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(
            path: path,
            contentType: "application/json"
        )
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)

        return try await execute(request, decoding: Response.self)
    }

    func sendMultipartRequest<Response: Decodable>(
        path: String,
        fields: [String: String],
        file: MultipartFile,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Response {
        guard FileManager.default.fileExists(atPath: file.fileURL.path) else {
            throw OpenAIError.fileNotFound(file.fileURL)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(
            path: path,
            contentType: "multipart/form-data; boundary=\(boundary)",
            additionalHeaders: additionalHeaders
        )
        request.httpMethod = "POST"
        request.httpBody = try makeMultipartBody(
            fields: fields,
            file: file,
            boundary: boundary
        )

        return try await execute(request, decoding: Response.self)
    }

    private func makeRequest(
        path: String,
        contentType: String,
        additionalHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        let trimmedKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }

        let sanitizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let baseURL = configuration.baseURL.hasDirectoryPath
            ? configuration.baseURL
            : configuration.baseURL.appendingPathComponent("")

        guard let url = URL(string: sanitizedPath, relativeTo: baseURL)?.absoluteURL else {
            throw OpenAIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60

        if let organizationID = configuration.organizationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !organizationID.isEmpty {
            request.setValue(organizationID, forHTTPHeaderField: "OpenAI-Organization")
        }

        if let projectID = configuration.projectID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !projectID.isEmpty {
            request.setValue(projectID, forHTTPHeaderField: "OpenAI-Project")
        }

        for (header, value) in additionalHeaders {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { continue }
            request.setValue(trimmedValue, forHTTPHeaderField: header)
        }

        return request
    }

    private func execute<Response: Decodable>(
        _ request: URLRequest,
        decoding type: Response.Type
    ) async throws -> Response {
        AppLogger.info(
            "OpenAI request started. method=\(request.httpMethod ?? "GET"), url=\(request.url?.absoluteString ?? "nil")",
            category: .openAI
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }

        AppLogger.info(
            "OpenAI response received. status=\(httpResponse.statusCode), url=\(request.url?.absoluteString ?? "nil")",
            category: .openAI
        )

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = parseAPIErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw OpenAIError.api(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw OpenAIError.invalidResponse
        }
    }

    private func parseAPIErrorMessage(from data: Data) -> String? {
        if let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) {
            return envelope.error?.message ?? envelope.message
        }

        let rawMessage = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let rawMessage, !rawMessage.isEmpty {
            return rawMessage
        }

        return nil
    }

    private func makeMultipartBody(
        fields: [String: String],
        file: MultipartFile,
        boundary: String
    ) throws -> Data {
        let fileData = try Data(contentsOf: file.fileURL)
        var body = Data()

        for (name, value) in fields where !value.isEmpty {
            body.append(contentsOf: "--\(boundary)\r\n".utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8)
            body.append(contentsOf: "\(value)\r\n".utf8)
        }

        body.append(contentsOf: "--\(boundary)\r\n".utf8)
        body.append(
            contentsOf: "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n".utf8
        )
        body.append(contentsOf: "Content-Type: \(file.mimeType)\r\n\r\n".utf8)
        body.append(fileData)
        body.append(contentsOf: "\r\n".utf8)
        body.append(contentsOf: "--\(boundary)--\r\n".utf8)

        return body
    }
}
