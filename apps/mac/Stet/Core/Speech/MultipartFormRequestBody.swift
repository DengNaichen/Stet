import Foundation

struct MultipartFormField: Sendable {
    let name: String
    let value: String
}

struct MultipartFormFile: Sendable {
    let name: String
    let fileName: String
    let contentType: String
    let data: Data
}

enum MultipartFormRequestBody {
    static func make(
        boundary: String = "StetBoundary-\(UUID().uuidString)",
        fields: [MultipartFormField],
        file: MultipartFormFile
    ) -> (boundary: String, body: Data) {
        var body = Data()

        appendMultipartFile(file, boundary: boundary, to: &body)

        for field in fields {
            appendMultipartField(field, boundary: boundary, to: &body)
        }

        appendString("--\(boundary)--\r\n", to: &body)
        return (boundary, body)
    }

    private static func appendMultipartField(
        _ field: MultipartFormField,
        boundary: String,
        to body: inout Data
    ) {
        appendString("--\(boundary)\r\n", to: &body)
        appendString("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n", to: &body)
        appendString(field.value, to: &body)
        appendString("\r\n", to: &body)
    }

    private static func appendMultipartFile(
        _ file: MultipartFormFile,
        boundary: String,
        to body: inout Data
    ) {
        appendString("--\(boundary)\r\n", to: &body)
        appendString(
            "Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.fileName)\"\r\n",
            to: &body
        )
        appendString("Content-Type: \(file.contentType)\r\n\r\n", to: &body)
        body.append(file.data)
        appendString("\r\n", to: &body)
    }

    private static func appendString(_ string: String, to body: inout Data) {
        body.append(Data(string.utf8))
    }
}
