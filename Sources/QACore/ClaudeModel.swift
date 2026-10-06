import Foundation

public enum ClaudeModel {
    public static let haiku = "claude-haiku-4-5-20251001"
    public static let sonnet = "claude-sonnet-4-6"
}

public enum TaskKind {
    case summarizeLogs
    case classifyFindings
    case explainLintIssue
    case generateQuiz
    case visualQACheck
    case proposePatch
    case retryFailedFix
    case multiFileIssue
    case generateTest
    case suggestImprovement
}

// Why: Haiku is the default per CLAUDE.md; only patch proposals, failed-verification retries, and
// multi-file issues escalate to Sonnet. Test generation isn't explicitly listed in CLAUDE.md's routing
// rules, but "keep only tests that compile and pass" sets a correctness bar closer to a patch proposal
// than a summary/classification task, so it routes to Sonnet too. A visual UI check is a classification-style
// task (spot an issue, describe it) like the other Haiku-tier items, not code generation, so it stays on Haiku.
// A code-improvement suggestion is itself a patch — same quality bar as proposePatch — so it's Sonnet too.
public func model(for task: TaskKind) -> String {
    switch task {
    case .summarizeLogs, .classifyFindings, .explainLintIssue, .generateQuiz, .visualQACheck:
        return ClaudeModel.haiku
    case .proposePatch, .retryFailedFix, .multiFileIssue, .generateTest, .suggestImprovement:
        return ClaudeModel.sonnet
    }
}
