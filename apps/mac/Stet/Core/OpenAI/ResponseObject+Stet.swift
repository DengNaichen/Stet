import Foundation
import OpenAI

extension ResponseObject {
    var stetOutputText: String? {
        for item in output {
            guard case .outputMessage(let message) = item else {
                continue
            }

            for content in message.content {
                guard case .OutputTextContent(let outputText) = content else {
                    continue
                }

                let text = outputText.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }
}
