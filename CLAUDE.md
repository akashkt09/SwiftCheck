# SwiftCheck for iOS: Build Plan

SwiftCheck is a QA agent that plugs into any Xcode project. It inspects Swift, SwiftUI, Objective-C and XIB files, debugs test failures and crashes, suggests improvements, and writes unit tests. It has a macOS UI, and every code change is gated on developer approval.

Deadline: demo for the team and leadership in 3 days.

## Architecture

```
SwiftCheck (Swift package)
 ├── QACore        library: all logic. No UI code here.
 ├── swiftcheck    CLI executable: thin wrapper over QACore
 └── SwiftCheckApp macOS SwiftUI app: thin view layer over QACore
```

- The engine lives outside the target project and treats it as input. It never adds code or dependencies to the target project.
- Deterministic tools run first and the LLM runs second. Claude only receives narrowed evidence (failure lines, a function, a diff), never whole files or logs.
- Every patch goes through propose → developer approves → apply → rebuild → re-test. A fix only counts as successful when the tests pass.
- Never edit `project.pbxproj` automatically. If there is no test target, tell the user.

## Code conventions (strict)

- Minimal, direct Swift. Use plain functions and structs. No protocols, no enum-based abstractions, no dependency injection layers, no boilerplate.
- Mark something `public` only where the CLI or the app needs it.
- Every non-obvious decision gets a one-line `// Why:` comment.
- Run all tools through `xcrun` using a single `shell()` helper. Read the pipe before calling `waitUntilExit()`.
- Read the API key from the `ANTHROPIC_API_KEY` environment variable. Never hardcode it or commit it.
- The app is distributed outside the Mac App Store (Developer ID): it must spawn `xcodebuild`, `simctl`, `lldb` and `sourcekit-lsp`.

## LLM routing

- Haiku (`claude-haiku-4-5-20251001`) by default: summarizing logs, classifying findings, explaining lint issues, generating quizzes.
- Escalate to Sonnet only for patch proposals, fixes that failed verification, and issues that span more than one file.
- Use prompt caching for the system prompt and tool definitions.
- Log input tokens, output tokens and estimated cost on every call, and show the running total in the CLI output and the app toolbar.

## Build order

### Day 1: Engine (CLI)
1. Package skeleton, `shell()`, and a checkpoint: `swift run swiftcheck` prints the `xcodebuild -version` output.
2. Project discovery: look for `.xcworkspace`, then `.xcodeproj`, then `Package.swift`. List schemes with `xcodebuild -list -json`.
3. Simulator selection with `simctl list devices available -j`. Never hardcode a device name.
4. `xcodebuild test -resultBundlePath`, then parse failures with `xcresulttool`. Check `xcrun xcresulttool help` for the current syntax. Fallback: grep the build log for `file:line: error:` lines.
5. Claude client using URLSession and the Messages API, plus the Haiku/Sonnet router and token logging.
6. Patch loop: diagnosis + unified diff → `Apply? (y/n)` → `git apply` → re-run tests.
7. Seeded-bug demo app (see below).

Checkpoint: all seeded test-failure bugs are fixed end to end from the CLI.

### Day 2: macOS app and inspectors
1. App shell. Three panes: file tree, inspector, findings/chat. Console at the bottom, token meter in the toolbar.
2. Add a folder with `NSOpenPanel` and security-scoped bookmarks. Watch for changes with FSEvents and re-analyze only changed files.
3. Swift inspector: outline and pattern checks with SwiftSyntax. SwiftUI checks:
   - `@StateObject` vs `@ObservedObject` misuse
   - unstable `ForEach` identity
   - heavy work inside `body`
   - main-actor violations
4. Objective-C inspector: `clang -Xclang -ast-dump=json`. Checks: missing nullability annotations, strong `self` inside blocks.
5. XIB inspector: parse with `XMLParser` into a view tree. Checks:
   - outlets missing from the Swift or Obj-C class (cross-reference the source)
   - missing accessibility identifiers
   - hardcoded strings
   - fixed fonts
6. Improvements panel: each finding shows a diff with Approve / Reject, and approval runs the same verify loop as the CLI.
7. Unit test generation: Swift Testing (XCTest for older deployment targets). Keep only tests that compile and pass, and show the coverage change.

Checkpoint: open the demo app's folder in the UI, see findings in all three inspectors, approve one fix and one generated test.

### Day 3: Debugger, previews, demo
1. Post-mortem debugger:
   - ingest `.ips` crash logs, symbolicate, map frames to source
   - stream live logs with `xcrun simctl spawn booted log stream`
2. Stretch: SwiftUI preview rendering. Find `#Preview` with SwiftSyntax, render it in a simulator host, take a screenshot, and run vision checks in dark mode and at large Dynamic Type sizes.
3. Stretch: live LLDB, driving `lldb` as a subprocess attached to the simulator app.
4. Demo polish: readable output, 3 dry runs from a fresh `git checkout`, and a recorded backup video.

Cut line: if Day 2 runs late, previews and live LLDB move to the roadmap slide. The demo must not depend on them.

## Seeded-bug demo app

A small iOS app (Swift + SwiftUI, one Obj-C class, one XIB) with planted bugs:
- off-by-one error (caught by a test)
- force unwrap on optional data (crash)
- wrong sorting logic (caught by a test)
- `@ObservedObject` where `@StateObject` is needed
- `ForEach` with unstable ids
- Obj-C header with no nullability annotations; a block capturing `self` strongly
- XIB outlet renamed in code but not in the XIB
- one untested service class (target for test generation)

Commit the buggy state on a branch called `demo-start` so every dry run starts from the same point.

## Demo script (about 10 minutes)

1. The problem: QA time and regressions slipping through.
2. CLI: run → failures → diagnosis → approve → green. Show the cost per run.
3. App: open the folder, then the Swift, Obj-C and XIB findings, then approve a fix and generate a test.
4. Crash triage from an `.ips` file.
5. Architecture and roadmap: previews, live LLDB, CI and Slack integration.
6. The ask: a pilot on one real project, using the measured cost per run.
