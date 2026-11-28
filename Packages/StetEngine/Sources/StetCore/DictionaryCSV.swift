import Foundation

public enum DictionaryImportFormat: Sendable, Equatable {
    case plainText
    case csv

    public static func inferred(from url: URL) -> DictionaryImportFormat {
        url.pathExtension.lowercased() == "csv" ? .csv : .plainText
    }
}

public enum DictionaryCSV {
    private static let termHeaderAliases: Set<String> = [
        "term", "terms", "word", "words", "phrase", "phrases",
        "entry", "entries", "text", "spelling", "hotword", "hotwords",
        "词条", "词语", "词汇", "术语",
    ]

    private static let sourceHeaderAliases: Set<String> = [
        "source", "origin", "provenance", "type", "来源",
    ]

    public static func exportCSV(records: [GlossaryEntry]) -> String {
        var lines: [String] = ["term,source"]
        lines.reserveCapacity(records.count + 1)
        for record in records {
            lines.append("\(escapeField(record.term)),\(escapeField(record.source.rawValue))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func exportCSVData(records: [GlossaryEntry]) -> Data {
        Data(exportCSV(records: records).utf8)
    }

    public static func parseRecords(from rawCSV: String) -> [GlossaryEntry] {
        let rows = parseRows(rawCSV).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let firstRow = rows.first else { return [] }

        if let header = detectHeader(in: firstRow) {
            let entries: [GlossaryEntry] = rows.dropFirst().compactMap { row in
                guard header.termColumn < row.count else { return nil }
                let term = row[header.termColumn]
                let source: GlossaryEntry.Source
                if let sourceColumn = header.sourceColumn, sourceColumn < row.count {
                    let rawSource = row[sourceColumn].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    source = GlossaryEntry.Source(rawValue: rawSource) ?? .manual
                } else {
                    source = .manual
                }
                return GlossaryEntry(term: term, source: source)
            }
            return GlossaryEntry.normalized(entries)
        }

        if isHeaderlessTermSourceTable(rows) {
            let entries = rows.compactMap { row -> GlossaryEntry? in
                guard let term = row.first else { return nil }
                let source: GlossaryEntry.Source
                if row.count > 1 {
                    let rawSource = row[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    source = GlossaryEntry.Source(rawValue: rawSource) ?? .manual
                } else {
                    source = .manual
                }
                return GlossaryEntry(term: term, source: source)
            }
            return GlossaryEntry.normalized(entries)
        }

        let entries = rows.flatMap { row in
            row.map { GlossaryEntry(term: $0, source: .manual) }
        }
        return GlossaryEntry.normalized(entries)
    }

    static func parseRows(_ input: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInQuotes = false
        let scalars = input.unicodeScalars
        var index = scalars.startIndex

        if index < scalars.endIndex, scalars[index] == "\u{FEFF}" {
            index = scalars.index(after: index)
        }

        while index < scalars.endIndex {
            let scalar = scalars[index]
            if isInQuotes {
                if scalar == "\"" {
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next] == "\"" {
                        currentField.unicodeScalars.append("\"")
                        index = scalars.index(after: next)
                        continue
                    }
                    isInQuotes = false
                    index = next
                    continue
                }
                currentField.unicodeScalars.append(scalar)
                index = scalars.index(after: index)
                continue
            }

            switch scalar {
            case "\"":
                if currentField.trimmingCharacters(in: .whitespaces).isEmpty {
                    currentField = ""
                    isInQuotes = true
                } else {
                    currentField.unicodeScalars.append(scalar)
                }
                index = scalars.index(after: index)
            case ",":
                currentRow.append(currentField)
                currentField = ""
                index = scalars.index(after: index)
            case "\r":
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "\n" {
                    index = scalars.index(after: next)
                } else {
                    index = next
                }
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
            case "\n":
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
                index = scalars.index(after: index)
            default:
                currentField.unicodeScalars.append(scalar)
                index = scalars.index(after: index)
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }

    private struct HeaderColumns {
        let termColumn: Int
        let sourceColumn: Int?
    }

    private static func detectHeader(in row: [String]) -> HeaderColumns? {
        let normalized = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let termColumn = normalized.firstIndex(where: { termHeaderAliases.contains($0) }) else {
            return nil
        }
        let sourceColumn = normalized.firstIndex(where: { sourceHeaderAliases.contains($0) })
        return HeaderColumns(termColumn: termColumn, sourceColumn: sourceColumn)
    }

    private static func isHeaderlessTermSourceTable(_ rows: [[String]]) -> Bool {
        let multiColumnRows = rows.filter { $0.count >= 2 }
        guard !multiColumnRows.isEmpty else { return false }
        return multiColumnRows.allSatisfy { row in
            guard row.count == 2 else { return false }
            let rawSource = row[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return GlossaryEntry.Source(rawValue: rawSource) != nil
        }
    }

    private static func escapeField(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
