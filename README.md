# SwiftCheck

An AI-assisted QA agent for iOS development. It plugs into any Xcode project, runs your tests, proposes guardrailed fixes, writes missing unit tests, and does a human-approved visual review of your app's UI in the simulator — all gated on developer approval, never auto-applied.

Available as both a CLI and a native macOS SwiftUI app.

## Why

Most "AI does your QA" tools either need deep IDE integration or quietly rewrite your code with no one checking. SwiftCheck is built around one rule instead: **every change goes through propose → developer approves → apply → rebuild → re-test.** Nothing is silently edited or silently shipped.

## Features

- **Project discovery** — finds your `.xcworkspace`/`.xcodeproj`/`Package.swift`, lists schemes, and lists available simulators automatically. No config files.
- **Test running & diagnosis** — runs `xcodebuild test`, parses real failures out of the `.xcresult` bundle, and explains them.
- **Guardrailed fixes** — proposes a fix as a unified diff. You approve it before anything touches disk; it's then applied, rebuilt, and re-tested to confirm the fix actually holds (auto-reverted if it doesn't).
- **Test generation** — writes missing unit tests for a file you select. You can describe the behavior you intend, so it tests what the code is *supposed* to do, not just what it happens to do today.
- **Visual UI review, with consent** — launches your app in the simulator; you navigate it by hand while SwiftCheck captures each distinct screen. Nothing is sent anywhere until you explicitly approve which captured screens are worth reviewing — then only those go to Claude for a layout/rendering pass.
- **Cost-aware model routing** — Haiku by default, escalating to Sonnet only for patch proposals, failed-fix retries, and multi-file issues. Every call logs input/output tokens and estimated cost, shown live in the app toolbar.
- **Guardrails** — responses that fall outside the file/scope they were asked about are rejected before they ever reach an Approve button.

## How it works

```
SwiftCheck (Swift package)
 ├── QACore         library: all logic — discovery, test running, Claude client, guardrails. No UI code.
 ├── swiftcheck     CLI executable: thin wrapper over QACore
 └── SwiftCheckApp  macOS SwiftUI app: thin view layer over QACore
```

- Deterministic tools run first; the LLM runs second. Claude only ever receives narrowed evidence (a failure message, a function, a diff) — never whole files or raw logs.
- SwiftCheck never adds code, dependencies, or build settings to the project it's checking, and never edits `project.pbxproj` automatically.
- The visual UI check uses `simctl` screenshots, not Accessibility/UI-automation APIs — it watches for genuine screen changes (byte-level diff) rather than driving taps itself, so it works without any special permissions.

## Requirements

- macOS 14+
- Xcode command-line tools (`xcodebuild`, `simctl`, `xcresulttool`)
- An Anthropic API key

## Setup

Set your API key via environment variable (preferred):

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

Or, as a fallback, create `~/.qa-agent/credentials` (owner-only permissions):

```bash
mkdir -p ~/.qa-agent && chmod 700 ~/.qa-agent
echo "ANTHROPIC_API_KEY=sk-ant-..." > ~/.qa-agent/credentials
chmod 600 ~/.qa-agent/credentials
```

The environment variable always wins if both are set. The key is never hardcoded or committed — `credentials` and `.env` files are gitignored.

## Usage

### CLI

```bash
swift run swiftcheck
```

### macOS app

```bash
swift run SwiftCheckApp
```

Then: **Open Folder** to point it at any Xcode project → pick a scheme and simulator from the toolbar → **Run Tests**, **Watch UI**, or select a file to generate tests / propose improvements for it.

## Project structure

```
Sources/
  QACore/            Discovery, simulator selection, test running, Claude client,
                      guardrails, patch loop, visual UI watch loop.
  swiftcheck/         CLI entry point.
  SwiftCheckApp/      macOS SwiftUI app (AppModel + views).
DemoApp/              Small iOS app with a few seeded bugs, used to exercise SwiftCheck end-to-end.
```

## Limitations

- No Accessibility/computer-use permission is assumed — the visual UI check is screenshot-based and requires a developer to navigate the app by hand; it does not inject taps.
- Designed for Xcode projects (workspace, project, or Swift package) with a test target. If there is no test target, SwiftCheck tells you rather than creating one via `project.pbxproj`.

## License

MIT — see [LICENSE](LICENSE).
