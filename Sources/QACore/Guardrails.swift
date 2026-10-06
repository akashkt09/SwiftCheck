import Foundation

// Why: Claude never has tool/execution access anywhere in this app — it only ever returns text, which this
// code then either shows as a proposed diff or test for a human to approve, or discards. These checks run
// BEFORE a response ever reaches the approval screen, so an off-task or malformed response is caught early
// rather than silently reaching a human who might rubber-stamp it.
public enum GuardrailViolation {
    case wrongFile(expected: String, actual: String)
    case multipleFiles([String])
    case noFileHeader
    case notATest

    public var reason: String {
        switch self {
        case .wrongFile(let expected, let actual):
            return "Discarded: the proposed diff touches \(actual), not \(expected) — the file whose failure was actually diagnosed."
        case .multipleFiles(let files):
            return "Discarded: the proposed diff touches multiple files (\(files.joined(separator: ", "))) — only the diagnosed file's failure should need a fix."
        case .noFileHeader:
            return "Discarded: the response has no recognizable diff file header — it isn't a usable patch."
        case .notATest:
            return "Discarded: the response doesn't look like a test (no XCTestCase or @Test found)."
        }
    }
}

// Why: scoped to exactly the failure being diagnosed — a diff that touches a different file than the one
// whose failure was diagnosed is out of scope for this task, regardless of how plausible it looks.
public func validateDiff(_ diff: String, expectedFile: String?) -> GuardrailViolation? {
    let headerPattern = try! NSRegularExpression(pattern: #"^(?:---|\+\+\+) [ab]/(.+)$"#, options: [.anchorsMatchLines])
    let range = NSRange(diff.startIndex..<diff.endIndex, in: diff)
    let matches = headerPattern.matches(in: diff, range: range)
    guard !matches.isEmpty else { return .noFileHeader }

    let touchedFiles = Set(matches.compactMap { match -> String? in
        guard let r = Range(match.range(at: 1), in: diff) else { return nil }
        return (String(diff[r]) as NSString).lastPathComponent
    })

    guard touchedFiles.count == 1, let touchedFile = touchedFiles.first else {
        return .multipleFiles(Array(touchedFiles).sorted())
    }

    if let expectedFile, touchedFile != expectedFile {
        return .wrongFile(expected: expectedFile, actual: touchedFile)
    }
    return nil
}

// Why: a response that isn't recognizably a test (no XCTestCase, no Swift Testing @Test) is off-task by
// definition for this feature — reject it rather than append whatever it actually is into a test file.
public func validateGeneratedTest(_ code: String) -> GuardrailViolation? {
    let looksLikeTest = code.contains("XCTestCase") || code.contains("@Test")
    return looksLikeTest ? nil : .notATest
}
