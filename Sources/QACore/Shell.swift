import Foundation

public struct ShellResult {
    public let output: String
    public let errorOutput: String
    public let exitCode: Int32
}

// Why: every tool (xcodebuild, simctl, lldb, sourcekit-lsp) runs through xcrun, so this is the one place that launches a process.
// `onOutputLine`, when provided, is called once per complete stdout line as the process runs — e.g. so a caller can
// show live progress on a long-running command instead of silence until it exits. `onProcessStarted`, when provided,
// hands the caller the live `Process` right after launch — the only way to cancel a run already in progress, since
// this function blocks the calling thread until the process exits.
@discardableResult
public func shell(
    _ command: String,
    _ arguments: [String] = [],
    workingDirectory: String? = nil,
    onOutputLine: ((String) -> Void)? = nil,
    onProcessStarted: ((Process) -> Void)? = nil
) -> ShellResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments
    // Why: a SwiftPM package has no -workspace/-project flag; xcodebuild reads Package.swift from the working directory instead.
    if let workingDirectory {
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
    }

    // Why: kept separate from stdout — xcodebuild writes warnings to stderr that would otherwise corrupt -json output.
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        return ShellResult(output: "", errorOutput: "Failed to launch \(command): \(error)", exitCode: -1)
    }
    onProcessStarted?(process)

    // Why: readabilityHandler drains both pipes concurrently and incrementally (not readDataToEndOfFile, which
    // blocks until EOF) — this is what makes line-by-line streaming to onOutputLine possible. Each pipe's handler
    // fires on its own serial queue, and the two pipes don't share mutable state, so no additional locking is needed.
    var outputData = Data()
    var errorData = Data()
    var pendingLine = Data()
    let newline = Data([0x0A])
    let group = DispatchGroup()

    group.enter()
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else {
            if !pendingLine.isEmpty, let line = String(data: pendingLine, encoding: .utf8) {
                onOutputLine?(line)
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            group.leave()
            return
        }
        outputData.append(chunk)
        guard onOutputLine != nil else { return }
        pendingLine.append(chunk)
        while let range = pendingLine.range(of: newline) {
            let lineData = pendingLine.subdata(in: pendingLine.startIndex..<range.lowerBound)
            pendingLine.removeSubrange(pendingLine.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                onOutputLine?(line)
            }
        }
    }

    group.enter()
    errorPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            group.leave()
            return
        }
        errorData.append(chunk)
    }

    group.wait()
    process.waitUntilExit()

    let output = String(data: outputData, encoding: .utf8) ?? ""
    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
    return ShellResult(output: output, errorOutput: errorOutput, exitCode: process.terminationStatus)
}
