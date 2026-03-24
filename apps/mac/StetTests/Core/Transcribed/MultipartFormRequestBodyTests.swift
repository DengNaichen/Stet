import Foundation
import Testing

@testable import Stet

@Suite("Multipart Form Request Body")
struct MultipartFormRequestBodyTests {
    @Test func makeBuildsMultipartBodyWithFileFieldsAndClosingBoundary() throws {
        let result = MultipartFormRequestBody.make(
            boundary: "Boundary-123",
            fields: [
                MultipartFormField(name: "model", value: "gpt-4o-mini-transcribe"),
                MultipartFormField(name: "language", value: "en"),
            ],
            file: MultipartFormFile(
                name: "file",
                fileName: "speech.wav",
                contentType: "audio/wav",
                data: Data("audio-bytes".utf8)
            )
        )

        let body = try #require(String(data: result.body, encoding: .utf8))

        #expect(result.boundary == "Boundary-123")
        #expect(body.hasPrefix("--Boundary-123\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n"))
        #expect(body.contains("Content-Type: audio/wav\r\n\r\naudio-bytes\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-mini-transcribe\r\n"))
        #expect(body.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\nen\r\n"))
        #expect(body.hasSuffix("--Boundary-123--\r\n"))
    }

    @Test func makePlacesFilePartBeforeTextFields() throws {
        let result = MultipartFormRequestBody.make(
            boundary: "Boundary-ordered",
            fields: [
                MultipartFormField(name: "model", value: "first-field"),
                MultipartFormField(name: "prompt", value: "second-field"),
            ],
            file: MultipartFormFile(
                name: "file",
                fileName: "speech.mp3",
                contentType: "audio/mp3",
                data: Data("binary".utf8)
            )
        )

        let body = try #require(String(data: result.body, encoding: .utf8))
        let fileRange = try #require(body.range(of: "name=\"file\""))
        let modelRange = try #require(body.range(of: "name=\"model\""))
        let promptRange = try #require(body.range(of: "name=\"prompt\""))

        #expect(fileRange.lowerBound < modelRange.lowerBound)
        #expect(modelRange.lowerBound < promptRange.lowerBound)
    }

    @Test func makeWithoutFieldsStillProducesAValidMultipartPayload() throws {
        let result = MultipartFormRequestBody.make(
            boundary: "Boundary-file-only",
            fields: [],
            file: MultipartFormFile(
                name: "upload",
                fileName: "clip.webm",
                contentType: "audio/webm",
                data: Data([0x00, 0x01, 0x02])
            )
        )

        let body = result.body
        let bodyString = try #require(String(data: body, encoding: .utf8))

        #expect(bodyString.contains("name=\"upload\"; filename=\"clip.webm\""))
        #expect(bodyString.contains("Content-Type: audio/webm"))
        #expect(bodyString.hasSuffix("--Boundary-file-only--\r\n"))
    }
}
