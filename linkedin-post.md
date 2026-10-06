I spent a few focused days building SwiftCheck — a QA agent for iOS development that plugs into any Xcode project.

The idea: let Claude handle the tedious parts of QA, but never let it touch code unsupervised.

What it does:
→ Discovers your project, schemes, and simulators automatically — no config files
→ Runs your test suite and parses real failures out of xcresult bundles
→ Proposes a fix as a diff, you approve it, then it applies, rebuilds, and re-tests to confirm the fix actually holds
→ Writes missing unit tests — and you can tell it the behavior you intended, so it tests what the code should do, not just what it happens to do
→ Watches you navigate the app in the simulator, captures each distinct screen, and does a visual pass for layout/rendering issues — but only on the screens you explicitly approve. Nothing goes to Claude without a human picking what's worth reviewing.

A few things I cared about getting right:
• Every change is propose → developer approves → apply → re-verify. No silent edits, ever.
• Guardrails reject out-of-scope AI output before it ever reaches an Approve button.
• Cost-aware model routing — Haiku by default, escalating to Sonnet only when a fix actually needs it — with full token/cost logging in the UI.
• A native macOS SwiftUI front end over a Swift Package engine, so it's just as usable from the CLI.

Still early, but it's already catching real bugs and writing real tests on my own projects. Screen recording below 👇

#iOS #Swift #SwiftUI #QA #AI #ClaudeAI #BuildInPublic #DeveloperTools
