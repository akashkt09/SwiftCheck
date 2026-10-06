import Foundation

public struct UILaunchResult {
    public let succeeded: Bool
    public let screenshotPaths: [String]
    public let errorMessage: String?
}

// Why: pulls a single build-setting value out of `xcodebuild -showBuildSettings` text output — the only
// way to learn where xcodebuild will place the built .app without hardcoding a DerivedData path.
private func extractSetting(_ key: String, from output: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "^\\s*\(key) = (.+)$", options: [.anchorsMatchLines]) else {
        return nil
    }
    let range = NSRange(output.startIndex..<output.endIndex, in: output)
    guard let match = regex.firstMatch(in: output, range: range), let valueRange = Range(match.range(at: 1), in: output) else {
        return nil
    }
    return String(output[valueRange]).trimmingCharacters(in: .whitespaces)
}

private func projectArguments(for project: ProjectReference) -> [String] {
    switch project.kind {
    case .workspace: return ["-workspace", project.path]
    case .project: return ["-project", project.path]
    case .package: return []
    }
}

private struct LaunchFailure: Error {
    let message: String
}

// Why: shared by the watch loop below — builds, installs, and launches the real app, returning the
// simulator-side bundle ID once it's running. Kept as a single Result so every caller handles the same
// set of failure messages instead of duplicating the five-step pipeline.
private func buildInstallAndLaunch(
    project: ProjectReference,
    scheme: String,
    simulator: SimulatorDevice,
    onProcessStarted: ((Process) -> Void)?
) -> Result<Void, LaunchFailure> {
    let workingDirectory = project.kind == .package ? (project.path as NSString).deletingLastPathComponent : nil
    let destination = "platform=iOS Simulator,id=\(simulator.udid)"

    let settingsArgs = ["xcodebuild", "-showBuildSettings"] + projectArguments(for: project) + ["-scheme", scheme, "-destination", destination]
    let settingsResult = shell("xcrun", settingsArgs, workingDirectory: workingDirectory, onProcessStarted: onProcessStarted)
    guard settingsResult.exitCode == 0,
          let targetBuildDir = extractSetting("TARGET_BUILD_DIR", from: settingsResult.output),
          let fullProductName = extractSetting("FULL_PRODUCT_NAME", from: settingsResult.output) else {
        return .failure(LaunchFailure(message: "Could not read build settings for scheme \(scheme)."))
    }
    let appPath = "\(targetBuildDir)/\(fullProductName)"

    let buildArgs = ["xcodebuild", "build"] + projectArguments(for: project) + ["-scheme", scheme, "-destination", destination]
    let buildResult = shell("xcrun", buildArgs, workingDirectory: workingDirectory, onProcessStarted: onProcessStarted)
    guard buildResult.exitCode == 0, FileManager.default.fileExists(atPath: appPath) else {
        return .failure(LaunchFailure(message: "Build failed or app not found at \(appPath): \(buildResult.errorOutput)"))
    }

    let bundleIDResult = shell("plutil", ["-extract", "CFBundleIdentifier", "raw", "-o", "-", "\(appPath)/Info.plist"], onProcessStarted: onProcessStarted)
    let bundleID = bundleIDResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard bundleIDResult.exitCode == 0, !bundleID.isEmpty else {
        return .failure(LaunchFailure(message: "Could not read CFBundleIdentifier from \(appPath)/Info.plist."))
    }

    // Why: "already booted" is a normal, ignorable outcome here — boot is best-effort, not a precondition check.
    _ = shell("xcrun", ["simctl", "boot", simulator.udid], onProcessStarted: onProcessStarted)

    // Why: `simctl boot`/`launch` only start the simulator's runtime and the app process inside it — neither
    // opens the Simulator.app *window*. Screenshots still work either way (they read the framebuffer
    // directly), which is why that half of this kept passing verification, but a developer can't manually
    // navigate a window they can't see. `open -a Simulator` is the same thing Xcode does to surface it.
    _ = shell("open", ["-a", "Simulator"], onProcessStarted: onProcessStarted)

    let installResult = shell("xcrun", ["simctl", "install", simulator.udid, appPath], onProcessStarted: onProcessStarted)
    guard installResult.exitCode == 0 else {
        return .failure(LaunchFailure(message: "simctl install failed: \(installResult.errorOutput)"))
    }

    let launchResult = shell("xcrun", ["simctl", "launch", simulator.udid, bundleID], onProcessStarted: onProcessStarted)
    guard launchResult.exitCode == 0 else {
        return .failure(LaunchFailure(message: "simctl launch failed: \(launchResult.errorOutput)"))
    }

    return .success(())
}

// Why: cancellable in small steps (not just once per poll interval) — sleeping in 0.2s chunks and checking
// the token between each keeps Stop responsive even with a multi-second poll interval.
private func sleepCancellable(_ duration: Double, checking token: CancellationToken) {
    let chunk = 0.2
    var remaining = duration
    while remaining > 0, !token.isCancelled {
        Thread.sleep(forTimeInterval: min(chunk, remaining))
        remaining -= chunk
    }
}

// Why: this is the actual answer to "there will be screens where actions are needed" — rather than trying
// to inject taps (which needs Accessibility permission this environment doesn't have, or generated XCUITest
// code), the developer drives the simulator by hand and this just watches, capturing a new screenshot only
// when the screen actually changes, for as long as the caller lets it run (bounded by `cancellationToken`,
// `maxScreenshots`, and `maxDurationSeconds` as a safety net against a session left running unattended).
// `onNewScreenCaptured`, when provided, fires immediately as each new distinct screen is found, so a caller
// can show live progress instead of only learning the full set once the watch ends.
public func watchAndCaptureDistinctScreens(
    project: ProjectReference,
    scheme: String,
    simulator: SimulatorDevice,
    screenshotDirectory: String,
    cancellationToken: CancellationToken,
    pollIntervalSeconds: Double = 1.5,
    maxScreenshots: Int = 40,
    maxDurationSeconds: Double = 900,
    onNewScreenCaptured: ((String) -> Void)? = nil,
    onProcessStarted: ((Process) -> Void)? = nil
) -> UILaunchResult {
    switch buildInstallAndLaunch(project: project, scheme: scheme, simulator: simulator, onProcessStarted: onProcessStarted) {
    case .failure(let error):
        return UILaunchResult(succeeded: false, screenshotPaths: [], errorMessage: error.message)
    case .success:
        break
    }

    try? FileManager.default.createDirectory(atPath: screenshotDirectory, withIntermediateDirectories: true)

    var keptPaths: [String] = []
    var lastKeptData: Data?
    let startTime = Date()
    var index = 0

    while !cancellationToken.isCancelled,
          keptPaths.count < maxScreenshots,
          Date().timeIntervalSince(startTime) < maxDurationSeconds {
        sleepCancellable(pollIntervalSeconds, checking: cancellationToken)
        if cancellationToken.isCancelled { break }

        let candidatePath = screenshotDirectory + "/screen-\(index).png"
        index += 1
        let screenshotResult = shell("xcrun", ["simctl", "io", simulator.udid, "screenshot", candidatePath], onProcessStarted: onProcessStarted)
        guard screenshotResult.exitCode == 0, let data = try? Data(contentsOf: URL(fileURLWithPath: candidatePath)) else {
            try? FileManager.default.removeItem(atPath: candidatePath)
            continue
        }

        // Why: an unchanged screen produces a byte-identical PNG — comparing the full file data is cheap
        // enough here and avoids keeping dozens of duplicate frames while the developer reads one screen.
        if let lastKeptData, lastKeptData == data {
            try? FileManager.default.removeItem(atPath: candidatePath)
            continue
        }

        lastKeptData = data
        keptPaths.append(candidatePath)
        onNewScreenCaptured?(candidatePath)
    }

    guard !keptPaths.isEmpty else {
        return UILaunchResult(succeeded: false, screenshotPaths: [], errorMessage: "No distinct screens were captured.")
    }
    return UILaunchResult(succeeded: true, screenshotPaths: keptPaths, errorMessage: nil)
}

// Why: scoped narrowly to layout/rendering/transition problems only — not a general "review this app"
// prompt, so it can't be steered into commenting on or suggesting changes to the app's actual functionality.
public func buildVisualQAPrompt(screenshotCount: Int) -> (system: String, user: String) {
    let system = """
    You are a senior iOS QA engineer doing a visual review of a sequence of \(screenshotCount) screenshots, \
    each one taken when the screen changed while a developer navigated the app in the simulator by hand. For \
    each screenshot, in order, report any clear problems: overlapping or clipped text, misaligned or \
    overlapping elements, unreadable contrast, broken or missing images, obviously wrong layout. Respond with \
    one short section per screenshot, labeled "Screenshot N:", each followed by a plain-text list of issues \
    prefixed with "- ", or "No visible UI issues." if there are none. Do not describe the app's purpose, \
    content, or functionality, and do not suggest feature changes — only report layout/rendering problems.
    """
    return (system, "Review this sequence of \(screenshotCount) screenshots, each capturing one distinct screen in the order they were visited.")
}
