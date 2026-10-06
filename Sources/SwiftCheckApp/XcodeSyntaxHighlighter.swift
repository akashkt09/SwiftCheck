import SwiftUI

// Why: exact RGB values read from the user's own ~/Library/Developer/Xcode/UserData/FontAndColorThemes/
// Default (Dark).xccolortheme — not approximated from memory — so code displayed in this app matches
// what Xcode itself shows, not a close guess.
enum XcodeTheme {
    static let background = Color(red: 0.120543, green: 0.122844, blue: 0.141312)
    static let plain = Color.white.opacity(0.85)
    static let keyword = Color(red: 0.988394, green: 0.37355, blue: 0.638329)
    static let string = Color(red: 0.989117, green: 0.41558, blue: 0.365684)
    static let comment = Color(red: 0.423943, green: 0.474618, blue: 0.525183)
    static let number = Color(red: 0.814983, green: 0.749393, blue: 0.412334)
    static let type = Color(red: 0.362946, green: 0.846428, blue: 0.998966)
    static let attribute = Color(red: 0.74902, green: 0.521569, blue: 0.333333)
}

private let swiftKeywords: Set<String> = [
    "func", "struct", "class", "enum", "protocol", "extension", "import", "let", "var",
    "if", "else", "guard", "return", "switch", "case", "default", "for", "while", "in",
    "repeat", "do", "catch", "throw", "throws", "try", "async", "await", "public", "private",
    "fileprivate", "internal", "static", "final", "override", "init", "deinit", "self", "Self",
    "nil", "true", "false", "as", "is", "some", "any", "where", "break", "continue", "defer",
    "inout", "lazy", "mutating", "operator", "rethrows", "subscript", "typealias",
    "associatedtype", "willSet", "didSet", "get", "set", "convenience", "required", "weak",
    "unowned", "indirect"
]

private let highlightRegex = try! NSRegularExpression(
    pattern: #"(?<comment>//.*|/\*[\s\S]*?\*/)|(?<string>"(?:[^"\\]|\\.)*")|(?<attribute>@[A-Za-z_][A-Za-z0-9_]*)|(?<number>\b\d+\.?\d*\b)|(?<word>\b[A-Za-z_][A-Za-z0-9_]*\b)"#,
    options: []
)

// Why: a lightweight regex-based highlighter, not a full lexer — scanning is non-overlapping and
// left-to-right, so once a comment or string match consumes a range, nothing inside it (e.g. the word
// "func" inside a string literal) gets a second look from a later alternative.
func highlightSwiftCode(_ code: String) -> AttributedString {
    var result = AttributedString()
    var lastEnd = code.startIndex
    let nsRange = NSRange(code.startIndex..<code.endIndex, in: code)

    func appendPlain(_ range: Range<String.Index>) {
        guard !range.isEmpty else { return }
        var piece = AttributedString(String(code[range]))
        piece.foregroundColor = XcodeTheme.plain
        result += piece
    }

    func appendColored(_ range: Range<String.Index>, color: Color) {
        var piece = AttributedString(String(code[range]))
        piece.foregroundColor = color
        result += piece
    }

    highlightRegex.enumerateMatches(in: code, range: nsRange) { match, _, _ in
        guard let match, let fullRange = Range(match.range, in: code) else { return }
        appendPlain(lastEnd..<fullRange.lowerBound)

        if let range = Range(match.range(withName: "comment"), in: code) {
            appendColored(range, color: XcodeTheme.comment)
        } else if let range = Range(match.range(withName: "string"), in: code) {
            appendColored(range, color: XcodeTheme.string)
        } else if let range = Range(match.range(withName: "attribute"), in: code) {
            appendColored(range, color: XcodeTheme.attribute)
        } else if let range = Range(match.range(withName: "number"), in: code) {
            appendColored(range, color: XcodeTheme.number)
        } else if let range = Range(match.range(withName: "word"), in: code) {
            let word = String(code[range])
            if swiftKeywords.contains(word) {
                appendColored(range, color: XcodeTheme.keyword)
            } else if let first = word.first, first.isUppercase {
                appendColored(range, color: XcodeTheme.type)
            } else {
                appendColored(range, color: XcodeTheme.plain)
            }
        }
        lastEnd = fullRange.upperBound
    }
    appendPlain(lastEnd..<code.endIndex)
    return result
}
