import Foundation

public struct MarkdownArticleBlock: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case paragraph
        case heading(Int)
        case unordered
        case ordered(String)
        case quote
        case code
        case divider
        case spacer
    }

    public let id: Int
    public let kind: Kind
    public let text: String

    public static func parse(_ source: String) -> [MarkdownArticleBlock] {
        var result: [MarkdownArticleBlock] = []
        var codeLines: [String] = []
        var isCode = false

        func append(_ kind: Kind, _ text: String = "") {
            result.append(MarkdownArticleBlock(id: result.count, kind: kind, text: text))
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if isCode {
                    append(.code, codeLines.joined(separator: "\n"))
                    codeLines.removeAll(keepingCapacity: true)
                }
                isCode.toggle()
                continue
            }
            if isCode {
                codeLines.append(rawLine)
                continue
            }
            if trimmed.isEmpty {
                append(.spacer)
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                append(.divider)
                continue
            }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                append(.heading(hashes), String(trimmed.dropFirst(hashes + 1)))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                append(.unordered, String(trimmed.dropFirst(2)))
                continue
            }
            if trimmed.hasPrefix("> ") {
                append(.quote, String(trimmed.dropFirst(2)))
                continue
            }
            if let dot = trimmed.firstIndex(of: "."),
               Int(trimmed[..<dot]) != nil,
               trimmed.index(after: dot) < trimmed.endIndex,
               trimmed[trimmed.index(after: dot)] == " " {
                append(
                    .ordered(String(trimmed[..<dot])),
                    String(trimmed[trimmed.index(dot, offsetBy: 2)...])
                )
                continue
            }
            append(.paragraph, rawLine)
        }
        if isCode || !codeLines.isEmpty {
            append(.code, codeLines.joined(separator: "\n"))
        }
        return result
    }
}
