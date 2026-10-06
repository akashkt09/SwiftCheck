import Foundation
import QACore

let arguments = CommandLine.arguments
let targetDirectory = arguments.count > 1 ? arguments[1] : FileManager.default.currentDirectoryPath

let versionResult = shell("xcrun", ["xcodebuild", "-version"])
print(versionResult.output, terminator: "")

guard let project = discoverProject(in: targetDirectory) else {
    print("No .xcworkspace, .xcodeproj, or Package.swift found in \(targetDirectory)")
    exit(1)
}

print("Found \(project.kind.rawValue) at \(project.path)")

let schemes = listSchemes(for: project)
if schemes.isEmpty {
    print("No schemes found")
} else {
    print("Schemes:")
    for scheme in schemes {
        print("  - \(scheme)")
    }
}

let simulators = listAvailableSimulators()
guard let simulator = selectSimulator(from: simulators) else {
    print("No available iOS simulator found")
    exit(1)
}
print("Selected simulator: \(simulator.name) (\(simulator.udid))\(simulator.isBooted ? " [booted]" : "")")

// Why: a full test run can take minutes on a large workspace, so it only runs when explicitly requested.
if let testFlagIndex = arguments.firstIndex(of: "--test"), arguments.indices.contains(testFlagIndex + 1) {
    let scheme = arguments[testFlagIndex + 1]
    print("\nRunning tests for scheme \(scheme)...")
    let testRun = runTests(project: project, scheme: scheme, simulator: simulator, resultBundlePath: "/tmp/swiftcheck-result.xcresult")

    if testRun.succeeded {
        print("Tests passed.")
    } else {
        let failures = diagnoseFailures(testRun)
        print("Tests failed (\(failures.count) failure\(failures.count == 1 ? "" : "s")):")
        for failure in failures {
            if let file = failure.file, let line = failure.line {
                print("  \(file):\(line): \(failure.message)")
            } else {
                print("  \(failure.message)")
            }
        }
    }
}

// Why: the patch loop needs an API key and developer approval per diff, so it only runs when explicitly requested.
if let fixFlagIndex = arguments.firstIndex(of: "--fix"), arguments.indices.contains(fixFlagIndex + 1) {
    let scheme = arguments[fixFlagIndex + 1]
    guard let client = ClaudeClient() else {
        print("\nANTHROPIC_API_KEY is not set — cannot run the patch loop.")
        exit(1)
    }

    print("\nRunning patch loop for scheme \(scheme)...")
    let projectRoot = (project.path as NSString).deletingLastPathComponent
    let result = try await runPatchLoop(
        project: project,
        scheme: scheme,
        simulator: simulator,
        client: client,
        resultBundlePath: "/tmp/swiftcheck-fix-result.xcresult",
        projectRoot: projectRoot,
        confirm: { prompt in
            print(prompt, terminator: "")
            return readLine()?.lowercased().hasPrefix("y") ?? false
        },
        log: { print($0) }
    )
    print(result.succeeded ? "Fixed after \(result.attempts) attempt(s)." : "Did not reach a passing state after \(result.attempts) attempt(s).")
}
