import Foundation

public struct TestRunResult {
    public let resultBundlePath: String
    public let succeeded: Bool
    public let rawLog: String
}

// Why: the "real progress" markers (suite/case starts, pass/fail, the final result banner) — exposed so a
// caller can filter the raw output stream down to just these, since xcodebuild's build-phase output (codesign,
// builtin-copy, one line per compiled file) dwarfs them in volume.
private let notableTestLineMarkers = ["Testing started", "Test Suite", "Test Case", "** TEST", "** BUILD FAILED", "** BUILD SUCCEEDED", "error:"]

public func isNotableTestLine(_ line: String) -> Bool {
    notableTestLineMarkers.contains { line.contains($0) }
}

// Why: -resultBundlePath refuses to write over an existing bundle, so always start from a clean path.
// `onProgress` gets every raw stdout line unfiltered — the caller decides how much of it to surface (see
// `BuildProgressFilter` for a throttled, human-readable policy). `onProcessStarted` is the only way to cancel
// a run already in progress, since this call blocks until xcodebuild exits.
public func runTests(
    project: ProjectReference,
    scheme: String,
    simulator: SimulatorDevice,
    resultBundlePath: String,
    onProgress: ((String) -> Void)? = nil,
    onProcessStarted: ((Process) -> Void)? = nil
) -> TestRunResult {
    try? FileManager.default.removeItem(atPath: resultBundlePath)

    var arguments = ["xcodebuild", "test"]
    switch project.kind {
    case .workspace:
        arguments += ["-workspace", project.path]
    case .project:
        arguments += ["-project", project.path]
    case .package:
        break
    }
    arguments += [
        "-scheme", scheme,
        "-destination", "platform=iOS Simulator,id=\(simulator.udid)",
        "-resultBundlePath", resultBundlePath
    ]

    let workingDirectory = project.kind == .package ? (project.path as NSString).deletingLastPathComponent : nil
    let result = shell(
        "xcrun", arguments,
        workingDirectory: workingDirectory,
        onOutputLine: onProgress,
        onProcessStarted: onProcessStarted
    )
    return TestRunResult(
        resultBundlePath: resultBundlePath,
        succeeded: result.exitCode == 0,
        rawLog: result.output + result.errorOutput
    )
}

// Why: xcodebuild emits one line per build step (hundreds for a Pods-heavy workspace) — surfacing every line
// floods the console, but surfacing nothing during the build phase (before "Testing started" ever appears)
// looks exactly like a stuck/frozen run. This throttles to one line per *target* change, which reads as
// genuine step-by-step progress ("Building Firebase...", "Building IndyCar...") without the flood, and always
// passes through the test-specific markers from `isNotableTestLine` unthrottled.
public final class BuildProgressFilter {
    private var lastTarget: String?
    private static let targetPattern = try! NSRegularExpression(pattern: #"\(in target '([^']+)'"#)

    public init() {}

    public func describe(_ line: String) -> String? {
        if isNotableTestLine(line) {
            return line
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = Self.targetPattern.firstMatch(in: line, range: range),
              let targetRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let target = String(line[targetRange])
        guard target != lastTarget else { return nil }
        lastTarget = target
        return "Building \(target)..."
    }
}

public struct Failure {
    public let file: String?
    public let line: Int?
    public let message: String
}

// Why: try the structured xcresult bundle first; only grep the raw log if it has nothing (e.g. a compile error that
// never produced test nodes).
public func diagnoseFailures(_ testRun: TestRunResult) -> [Failure] {
    guard !testRun.succeeded else { return [] }
    let testFailures = parseTestFailures(resultBundlePath: testRun.resultBundlePath)
    return testFailures.isEmpty ? parseBuildLogFailures(testRun.rawLog) : testFailures
}

// Why: `get test-results tests` returns a recursive tree (plan -> bundle -> suite -> case -> failure message); each
// failure message's `name` embeds "file:line: message" as plain text, which is the only place the location lives.
//
// Why retry: immediately after `xcodebuild test` exits, xcresulttool can briefly return an empty/unparseable
// result for a bundle that is otherwise complete on disk (observed directly: the same bundle parses correctly
// a few seconds later). Retrying a few times with a short delay avoids silently reporting zero failures.
private func parseTestFailures(resultBundlePath: String) -> [Failure] {
    for attempt in 0..<5 {
        if attempt > 0 {
            Thread.sleep(forTimeInterval: 0.5)
        }
        let result = shell("xcrun", ["xcresulttool", "get", "test-results", "tests", "--path", resultBundlePath, "--compact"])
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let testNodes = json["testNodes"] as? [[String: Any]] else {
            continue
        }

        var failures: [Failure] = []
        for node in testNodes {
            collectFailures(from: node, into: &failures)
        }
        if !failures.isEmpty {
            return failures
        }
    }
    return []
}

private func collectFailures(from node: [String: Any], into failures: inout [Failure]) {
    let children = node["children"] as? [[String: Any]] ?? []

    if node["nodeType"] as? String == "Test Case", node["result"] as? String == "Failed" {
        for child in children where child["nodeType"] as? String == "Failure Message" {
            guard let text = child["name"] as? String else { continue }
            failures.append(parseFailureLocation(text))
        }
        return
    }

    for child in children {
        collectFailures(from: child, into: &failures)
    }
}

private func parseFailureLocation(_ text: String) -> Failure {
    guard let regex = try? NSRegularExpression(pattern: #"^(.+?):(\d+):\s*(.+)$"#),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
          let fileRange = Range(match.range(at: 1), in: text),
          let lineRange = Range(match.range(at: 2), in: text),
          let line = Int(text[lineRange]) else {
        return Failure(file: nil, line: nil, message: text)
    }
    return Failure(file: String(text[fileRange]), line: line, message: text)
}

// Why: fallback for when xcresulttool has nothing to parse (e.g. a compile error before any test ran) — scrape the raw
// log for the standard "file:line: error: message" compiler diagnostic shape.
private func parseBuildLogFailures(_ log: String) -> [Failure] {
    guard let regex = try? NSRegularExpression(pattern: #"^(.+?):(\d+):(?:\d+:)?\s*error:\s*(.+)$"#, options: [.anchorsMatchLines]) else {
        return []
    }

    let range = NSRange(log.startIndex..<log.endIndex, in: log)
    var failures: [Failure] = []
    regex.enumerateMatches(in: log, range: range) { match, _, _ in
        guard let match, match.numberOfRanges == 4,
              let fileRange = Range(match.range(at: 1), in: log),
              let lineRange = Range(match.range(at: 2), in: log),
              let messageRange = Range(match.range(at: 3), in: log),
              let line = Int(log[lineRange]) else { return }
        failures.append(Failure(file: String(log[fileRange]), line: line, message: String(log[messageRange])))
    }
    return failures
}
