import AppKit
import Foundation
import QACore

struct FileNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [FileNode]?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var projectRoot: String?
    @Published var project: ProjectReference?
    @Published var schemes: [String] = []
    @Published var selectedScheme: String?
    @Published var simulator: SimulatorDevice?
    @Published var fileTree: [FileNode] = []
    @Published var selectedFilePath: String?
    @Published var selectedFileContents: String?
    @Published var failures: [Failure] = []
    @Published var selectedFailure: Failure?
    @Published var consoleLines: [String] = []
    @Published var proposedTestCode: String?
    @Published var testTargetFile: String?
    @Published var developerNotes: String = ""
    @Published var proposedImprovementDiff: String?
    @Published var improvementStatus: String?
    @Published var uiScreenshotPaths: [String] = []
    @Published var selectedUIScreenshotIndex: Int = 0
    @Published var approvedUIScreenshots: Set<String> = []
    @Published var isReviewingUIScreenshots = false
    @Published var uiCheckResult: String?
    @Published var uiWatchActive = false
    @Published var showingUICheck = false
    @Published var isBusy = false
    @Published var totalInputTokens = 0
    @Published var totalOutputTokens = 0
    @Published var totalCost = 0.0

    private let client = ClaudeClient()
    private var bookmarkedURL: URL?
    private var runningProcess: Process?
    private var uiWatchCancellationToken: CancellationToken?

    // Why: skip build/dependency noise so the tree stays usable on real projects with Pods/DerivedData.
    private let skippedDirectories: Set<String> = [".git", ".build", "Pods", "DerivedData", "node_modules"]

    var hasClaudeClient: Bool { client != nil }

    init() {
        // Why: opt-in launch hook for driving the app without clicking through the folder picker / Run Tests
        // button — useful when verifying from outside an interactive session (no Accessibility/computer-use
        // access to do it via the GUI). Off by default; normal launches still restore the last folder.
        if let path = ProcessInfo.processInfo.environment["SWIFTCHECK_OPEN_PATH"] {
            loadProject(at: URL(fileURLWithPath: path))
            if let scheme = ProcessInfo.processInfo.environment["SWIFTCHECK_SCHEME"], schemes.contains(scheme) {
                selectedScheme = scheme
            }
            if ProcessInfo.processInfo.environment["SWIFTCHECK_AUTO_RUN_TESTS"] == "1" {
                Task { await runTests() }
            }
        } else {
            restoreLastFolder()
        }
    }

    func appendConsole(_ line: String) {
        consoleLines.append(line)
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        storeBookmark(for: url)
        loadProject(at: url)
    }

    private func loadProject(at url: URL) {
        bookmarkedURL = url
        let path = url.path
        projectRoot = path
        fileTree = buildFileTree(at: path)
        selectedFilePath = nil
        selectedFileContents = nil
        failures = []
        selectedFailure = nil

        guard let discovered = discoverProject(in: path) else {
            project = nil
            schemes = []
            appendConsole("No .xcworkspace, .xcodeproj, or Package.swift found in \(path)")
            return
        }
        project = discovered
        appendConsole("Found \(discovered.kind.rawValue) at \(discovered.path)")
        schemes = listSchemes(for: discovered)
        selectedScheme = schemes.first
        simulator = selectSimulator(from: listAvailableSimulators())
        if let simulator {
            appendConsole("Selected simulator: \(simulator.name)\(simulator.isBooted ? " [booted]" : "")")
        }
    }

    func selectFile(_ node: FileNode) {
        guard !node.isDirectory else { return }
        selectedFilePath = node.path
        selectedFileContents = try? String(contentsOfFile: node.path, encoding: .utf8)
        // Why: notes/suggestions describe one specific module — carrying them over to the next selected
        // file would silently apply the wrong module's intent, or show a stale diff for the wrong file.
        developerNotes = ""
        proposedTestCode = nil
        proposedImprovementDiff = nil
        improvementStatus = nil
    }

    // Why: `xcodebuild test` can block for minutes. Task.detached still draws from Swift's small cooperative
    // thread pool, and parking one of those threads for that long can stall MainActor continuations too —
    // the toolbar spinner and the rest of the UI appear stuck even though nothing is actually looping.
    // Dispatching onto a plain GCD global queue uses libdispatch's own large thread pool instead, which is
    // built for exactly this kind of long blocking call.
    private func runBlocking<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    // Why: a fresh filter per run — it's stateful (tracks the last build target seen) and shouldn't carry
    // state across separate test runs. Lines fire from shell()'s background readability-handler queue, so
    // hop back to MainActor before touching @Published state.
    private func progressHandler() -> (String) -> Void {
        let filter = BuildProgressFilter()
        return { [weak self] line in
            guard let description = filter.describe(line) else { return }
            Task { @MainActor in self?.appendConsole("  " + description) }
        }
    }

    // Why: the only way to stop a run already in progress — shell() blocks the calling thread until xcodebuild
    // exits, so cancellation has to come from outside via the live Process reference captured at launch.
    // During a UI watch session this doubles as "I'm done navigating" — the watch loop treats a cancellation
    // as a normal, graceful end (keeping whatever screens were captured), not an error.
    func cancelCurrentRun() {
        uiWatchCancellationToken?.cancel()
        guard let runningProcess else { return }
        appendConsole("Cancelling...")
        runningProcess.terminate()
    }

    func runTests() async {
        guard let project, let scheme = selectedScheme, let simulator else { return }
        isBusy = true
        appendConsole("Running tests for scheme \(scheme)...")

        let bundlePath = NSTemporaryDirectory() + "swiftcheck-app-result.xcresult"
        let onProgress = progressHandler()
        let result = await runBlocking {
            QACore.runTests(
                project: project, scheme: scheme, simulator: simulator, resultBundlePath: bundlePath,
                onProgress: onProgress,
                onProcessStarted: { [weak self] process in Task { @MainActor in self?.runningProcess = process } }
            )
        }
        runningProcess = nil

        if result.succeeded {
            failures = []
            appendConsole("Tests passed.")
        } else {
            failures = await runBlocking { QACore.diagnoseFailures(result) }
            appendConsole("Tests failed (\(failures.count) failure\(failures.count == 1 ? "" : "s")).")
        }
        selectedFailure = failures.first
        isBusy = false
    }

    // Why: screenshot-based, not live UI-tap automation — this environment has no Accessibility permission
    // to drive the Simulator window directly. Rather than trying to inject taps for screens that need a
    // real action (impossible without that permission, or a lot of generated XCUITest code), the developer
    // drives the simulator by hand after this launches the app; this just watches and captures a new
    // screenshot whenever the screen actually changes, until Stop is clicked (or a safety cap is hit). The
    // result sheet opens immediately and the thumbnail strip grows live as each new screen is found.
    // Why it stops here instead of auto-sending: nothing goes to Claude until the developer explicitly
    // approves which captured screens are worth reviewing — a session can easily capture 20+ screens, and
    // sending all of them with no curation step is both wasteful and takes away the developer's say over
    // what gets shared for review.
    func startVisualUIWatch() async {
        guard client != nil else {
            appendConsole("ANTHROPIC_API_KEY is not set — cannot run a visual UI check.")
            return
        }
        guard let project, let scheme = selectedScheme, let simulator else { return }

        isBusy = true
        uiScreenshotPaths = []
        selectedUIScreenshotIndex = 0
        approvedUIScreenshots = []
        isReviewingUIScreenshots = false
        uiCheckResult = nil
        uiWatchActive = true
        showingUICheck = true
        appendConsole("Building and launching \(scheme) — navigate the app in the simulator; click Stop when done.")

        let token = CancellationToken()
        uiWatchCancellationToken = token
        let screenshotDirectory = NSTemporaryDirectory() + "swiftcheck-ui-watch-\(UUID().uuidString)"
        let watchResult = await runBlocking {
            watchAndCaptureDistinctScreens(
                project: project, scheme: scheme, simulator: simulator, screenshotDirectory: screenshotDirectory,
                cancellationToken: token,
                onNewScreenCaptured: { [weak self] path in
                    Task { @MainActor in
                        guard let self else { return }
                        self.uiScreenshotPaths.append(path)
                        self.selectedUIScreenshotIndex = self.uiScreenshotPaths.count - 1
                        self.appendConsole("  New screen captured (\(self.uiScreenshotPaths.count) so far).")
                    }
                },
                onProcessStarted: { [weak self] process in Task { @MainActor in self?.runningProcess = process } }
            )
        }
        runningProcess = nil
        uiWatchCancellationToken = nil
        uiWatchActive = false
        isBusy = false

        guard watchResult.succeeded, !watchResult.screenshotPaths.isEmpty else {
            appendConsole("UI check ended with no screens captured: \(watchResult.errorMessage ?? "unknown error")")
            return
        }

        // Why: the watch loop runs in the background regardless of whether the result window is still open —
        // if the developer closed it early, re-show it now rather than silently leaving the review step
        // (and the only way to trigger it — the Send for Review button) stuck in a window nobody can see.
        isReviewingUIScreenshots = true
        showingUICheck = true
        appendConsole("Captured \(watchResult.screenshotPaths.count) distinct screen(s). Select which to send for review, then click \"Send for Review.\"")
    }

    func toggleUIScreenshotApproval(_ path: String) {
        if approvedUIScreenshots.contains(path) {
            approvedUIScreenshots.remove(path)
        } else {
            approvedUIScreenshots.insert(path)
        }
    }

    func selectAllUIScreenshots() {
        approvedUIScreenshots = Set(uiScreenshotPaths)
    }

    func deselectAllUIScreenshots() {
        approvedUIScreenshots.removeAll()
    }

    // Why: only the screens the developer explicitly approved are ever sent — everything captured but left
    // unapproved stays local and is never shared with Claude.
    func sendApprovedScreenshotsForReview() async {
        guard let client else {
            appendConsole("ANTHROPIC_API_KEY is not set — cannot run a visual UI check.")
            return
        }
        // Why: preserve capture order rather than Set's arbitrary iteration order, so "Screenshot N" labels
        // in the response correspond to the order the developer actually saw them in the thumbnail strip.
        let approvedPaths = uiScreenshotPaths.filter { approvedUIScreenshots.contains($0) }
        guard !approvedPaths.isEmpty else {
            appendConsole("No screens selected for review.")
            return
        }

        isBusy = true
        appendConsole("Sending \(approvedPaths.count) approved screen(s) to Claude for review...")

        do {
            let images = try approvedPaths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
            let (system, userMessage) = buildVisualQAPrompt(screenshotCount: images.count)
            let response = try await client.send(system: system, userMessage: userMessage, model: model(for: .visualQACheck), images: images)
            totalInputTokens = client.usage.totalInputTokens
            totalOutputTokens = client.usage.totalOutputTokens
            totalCost = client.usage.totalCost
            uiCheckResult = response.text
            isReviewingUIScreenshots = false
            showingUICheck = true
            appendConsole("Visual UI check complete.")
        } catch {
            appendConsole("Claude request failed: \(error)")
        }
        isBusy = false
    }

    func generateTests(for filePath: String) async {
        guard let client, let projectRoot else {
            appendConsole("ANTHROPIC_API_KEY is not set — cannot generate tests.")
            return
        }
        guard let sourceContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
        guard let testFile = findExistingTestFile(forSourceAt: filePath, projectRoot: projectRoot) else {
            let sourceName = (filePath as NSString).lastPathComponent
            appendConsole("No test file matches \(sourceName) — add one (e.g. \(sourceName.replacingOccurrences(of: ".swift", with: "Tests.swift"))) in Xcode first, since new files can't be added to the project automatically.")
            return
        }

        isBusy = true
        testTargetFile = testFile
        appendConsole("Generating tests for \(filePath)...")

        let (system, userMessage) = buildTestGenerationPrompt(sourcePath: filePath, sourceContents: sourceContents, developerNotes: developerNotes)
        do {
            let response = try await client.send(system: system, userMessage: userMessage, model: model(for: .generateTest))
            totalInputTokens = client.usage.totalInputTokens
            totalOutputTokens = client.usage.totalOutputTokens
            totalCost = client.usage.totalCost
            let code = extractDiff(from: response.text)

            // Why: a response that isn't recognizably a test never reaches the Approve button — nothing
            // non-test ever gets a chance to be appended to a test file.
            if let violation = validateGeneratedTest(code) {
                appendConsole(violation.reason)
            } else {
                proposedTestCode = code
                appendConsole("Proposed new tests for \((testFile as NSString).lastPathComponent).")
            }
        } catch {
            appendConsole("Claude request failed: \(error)")
        }
        isBusy = false
    }

    func approveGeneratedTests() async {
        guard let code = proposedTestCode, let testFile = testTargetFile,
              let project, let scheme = selectedScheme, let simulator else { return }
        isBusy = true
        appendConsole("Appending generated tests to \((testFile as NSString).lastPathComponent)...")

        guard let originalContents = await runBlocking({ QACore.appendGeneratedTest(code, toFile: testFile) }) else {
            appendConsole("Failed to write to \(testFile).")
            isBusy = false
            return
        }
        proposedTestCode = nil

        appendConsole("Rebuilding and running tests to verify...")
        let bundlePath = NSTemporaryDirectory() + "swiftcheck-app-result.xcresult"
        let onProgress = progressHandler()
        var result = await runBlocking {
            QACore.runTests(
                project: project, scheme: scheme, simulator: simulator, resultBundlePath: bundlePath,
                onProgress: onProgress,
                onProcessStarted: { [weak self] process in Task { @MainActor in self?.runningProcess = process } }
            )
        }
        runningProcess = nil

        // Why: "keep only tests that compile and pass" (CLAUDE.md) — a bad generation gets fully reverted
        // and the suite re-run once more so the UI reflects the project's real, unmodified state.
        if !result.succeeded {
            appendConsole("Generated tests failed to compile or pass — discarding.")
            await runBlocking { QACore.restoreFile(originalContents, at: testFile) }
            result = await runBlocking {
                QACore.runTests(project: project, scheme: scheme, simulator: simulator, resultBundlePath: bundlePath)
            }
        } else {
            appendConsole("Generated tests compile and pass — kept.")
        }

        if result.succeeded {
            failures = []
        } else {
            failures = await runBlocking { QACore.diagnoseFailures(result) }
        }
        selectedFailure = failures.first
        isBusy = false
    }

    func rejectGeneratedTests() {
        proposedTestCode = nil
        appendConsole("Generated tests rejected.")
    }

    // Why: a general code-quality review of the currently selected file — not tied to a failing test.
    // Still routes through the same validateDiff guardrail as every other diff-producing call, so an
    // out-of-scope response never reaches the Approve button here either.
    func proposeImprovement(for filePath: String) async {
        guard let client else {
            appendConsole("ANTHROPIC_API_KEY is not set — cannot suggest improvements.")
            return
        }
        guard let sourceContents = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        isBusy = true
        improvementStatus = nil
        appendConsole("Reviewing \((filePath as NSString).lastPathComponent) for improvements...")

        let (system, userMessage) = buildImprovementPrompt(sourcePath: filePath, sourceContents: sourceContents)
        do {
            let response = try await client.send(system: system, userMessage: userMessage, model: model(for: .suggestImprovement))
            totalInputTokens = client.usage.totalInputTokens
            totalOutputTokens = client.usage.totalOutputTokens
            totalCost = client.usage.totalCost
            let trimmedText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedText == noImprovementsFoundMarker {
                improvementStatus = noImprovementsFoundMarker
                appendConsole(noImprovementsFoundMarker)
            } else {
                let diff = extractDiff(from: response.text)
                let expectedFile = (filePath as NSString).lastPathComponent
                if let violation = validateDiff(diff, expectedFile: expectedFile) {
                    improvementStatus = violation.reason
                    appendConsole(violation.reason)
                } else {
                    proposedImprovementDiff = diff
                    appendConsole("Proposed an improvement (\(response.usage.outputTokens) output tokens).")
                }
            }
        } catch {
            appendConsole("Claude request failed: \(error)")
        }
        isBusy = false
    }

    // Why: re-runs the full verify loop after applying, same as CLAUDE.md's "propose -> approve -> apply ->
    // rebuild -> re-test" — and auto-reverts if the improvement breaks the suite, so an approved change can
    // never leave the project in a worse state than before.
    func approveImprovement() async {
        guard let diff = proposedImprovementDiff, let filePath = selectedFilePath, let projectRoot,
              let project, let scheme = selectedScheme, let simulator else { return }
        isBusy = true
        appendConsole("Applying improvement...")

        let originalContents = try? String(contentsOfFile: filePath, encoding: .utf8)
        let applyResult = await runBlocking { QACore.applyPatch(diff: diff, projectRoot: projectRoot) }
        guard applyResult.exitCode == 0 else {
            appendConsole("git apply failed: \(applyResult.errorOutput)")
            isBusy = false
            return
        }

        proposedImprovementDiff = nil
        appendConsole("Improvement applied — re-running tests to verify...")
        let bundlePath = NSTemporaryDirectory() + "swiftcheck-app-result.xcresult"
        let onProgress = progressHandler()
        var result = await runBlocking {
            QACore.runTests(
                project: project, scheme: scheme, simulator: simulator, resultBundlePath: bundlePath,
                onProgress: onProgress,
                onProcessStarted: { [weak self] process in Task { @MainActor in self?.runningProcess = process } }
            )
        }
        runningProcess = nil

        if !result.succeeded, let originalContents {
            appendConsole("Tests failed after the improvement — reverting \((filePath as NSString).lastPathComponent).")
            await runBlocking { QACore.restoreFile(originalContents, at: filePath) }
            result = await runBlocking {
                QACore.runTests(project: project, scheme: scheme, simulator: simulator, resultBundlePath: bundlePath)
            }
            improvementStatus = "Reverted — the improvement broke the test suite."
        } else if result.succeeded {
            improvementStatus = "Applied and verified — tests still pass."
            appendConsole("Tests passed — improvement kept.")
        }

        if result.succeeded {
            failures = []
        } else {
            failures = await runBlocking { QACore.diagnoseFailures(result) }
        }
        selectedFailure = failures.first
        isBusy = false
    }

    func rejectImprovement() {
        proposedImprovementDiff = nil
        improvementStatus = nil
        appendConsole("Improvement rejected.")
    }

    private func buildFileTree(at path: String, depth: Int = 0) -> [FileNode] {
        guard depth < 6, let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return entries
            .filter { !skippedDirectories.contains($0) && !$0.hasPrefix(".") }
            .sorted()
            .map { name in
                let fullPath = path + "/" + name
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory)
                let children = isDirectory.boolValue ? buildFileTree(at: fullPath, depth: depth + 1) : nil
                return FileNode(id: fullPath, name: name, path: fullPath, isDirectory: isDirectory.boolValue, children: children)
            }
    }

    // Why: per CLAUDE.md — persist the opened folder across launches via a security-scoped bookmark.
    private func storeBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: "lastProjectBookmark")
    }

    private func restoreLastFolder() {
        guard let data = UserDefaults.standard.data(forKey: "lastProjectBookmark") else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        loadProject(at: url)
    }
}
