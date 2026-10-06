import Foundation

// Why: a dedicated file outside any project/git directory — ~/.qa-agent/credentials — with permissions
// restricted to the owner only (0600), the same convention as ~/.aws/credentials or ~/.netrc. This is only
// ever a fallback: the ANTHROPIC_API_KEY environment variable always wins when set, per CLAUDE.md.
public let credentialsFilePath = NSHomeDirectory() + "/.qa-agent/credentials"

// Why: simple KEY=VALUE parsing, one line — readable and editable by hand, and this process never writes
// the actual secret into the file itself; it only ever reads a value the user put there.
public func readAPIKeyFromCredentialsFile(at path: String = credentialsFilePath) -> String? {
    guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in contents.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), trimmed.hasPrefix("ANTHROPIC_API_KEY=") else { continue }
        let value = String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count)).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
    return nil
}
