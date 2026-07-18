import Foundation
import FoundationModels

@Generable
struct RewriteResult {
    @Guide(description: "A brief explanation of why the rewrite was or was not performed")
    let reason: String
    @Guide(description: "The cleaned, properly punctuated transcript")
    let text: String
}

let transcript = CommandLine.arguments.dropFirst().joined(separator: " ")

guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    print("Usage: xcrun swift scripts/manual_apple_rewrite_english.swift \"raw transcript\"")
    exit(2)
}

switch SystemLanguageModel.default.availability {
case .available:
    break
case .unavailable(let reason):
    throw ManualError.unavailable(String(describing: reason))
}

let cleanupPolicy = """
    1. ENGLISH FILLER PURGE: Delete filler-only words and phrases such as "um", "uh", filler "like", "you know", "I mean", and discourse-only "so".
    2. ENGLISH SELF-CORRECTION RESOLUTION: Treat "no", "wait no", "sorry", "actually", and "or actually" as correction markers when they replace an earlier object, name, date, number, file, target, phrase, or clause. Remove the earlier corrected span entirely and keep the later replacement span.
    3. ENGLISH INTENT PRESERVATION: Keep the speaker's intent and sentence type. Do not turn "I want to..." into a command unless the transcript is clearly addressed as a direct command.
    4. ENGLISH GRAMMAR PRESERVATION: Preserve surrounding action words and prepositions when applying a correction. If a correction changes "into A" to "into B", output "into B", not "into A, B".
    5. ENGLISH CORRECTION SPAN RULE: Around a correction marker, compare the phrase immediately before the marker with the phrase immediately after it. If both phrases fill the same role, delete the earlier phrase and splice the later phrase into the sentence with one copy of the shared preposition or verb.
    """

let reminder = """
    You are a professional Transcript Purge Engine. Your mission is to transform colloquial, messy speech-to-text transcripts into clean, professional, and concise written text.

    CRITICAL RULES:
    \(cleanupPolicy)
    6. WRITTEN STYLE: The output must sound like it was written by a professional editor.
    7. ABSOLUTE LANGUAGE LOCK: Never translate any word, phrase, clause, sentence, or language span. Keep every span in the exact language the speaker used, in the same order. Chinese spans must remain Chinese, English spans must remain English, and mixed-language text must remain mixed-language text. Do not normalize mixed-language text into one language. Do not replace a word with its translation even if the translation sounds more natural.
    8. PROPER PUNCTUATION: The output must be properly punctuated. Add periods, commas, and question marks as appropriate to ensure the text reads like a professional document.
    The speaker's primary language is en.
    """

let examplesURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("StetMac/Resources/Prompts/Rewrite_en.txt")
let examples = try String(contentsOf: examplesURL, encoding: .utf8)

let instructions = """
    \(reminder)

    Instruction: You must output a JSON object with two fields in this EXACT order:
    1. "reason": A brief explanation of which fillers or errors you identified.
    2. "text": The final cleaned transcript.

    \(examples)

    ### Task:
    Now, process the following input and provide the JSON output.
    """

let prompt = """
    Instruction:
    Clean the following raw transcription according to your instructions.

    Text:
    \(transcript)
    """

let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
let session = LanguageModelSession(model: model, instructions: instructions)
let response = try await session.respond(to: Prompt(prompt), generating: RewriteResult.self)

print("INPUT: \(transcript)")
print("REASON: \(response.content.reason)")
print("TEXT: \(response.content.text)")

enum ManualError: Error {
    case unavailable(String)
}
