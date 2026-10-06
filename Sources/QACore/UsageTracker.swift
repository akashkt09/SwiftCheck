import Foundation

public struct TokenUsage {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationInputTokens: Int
    public let cacheReadInputTokens: Int
}

private struct Pricing {
    let inputPerMillion: Double
    let outputPerMillion: Double

    // Why: prices from the current Claude model catalog ($/1M tokens).
    static func forModel(_ model: String) -> Pricing {
        switch model {
        case ClaudeModel.haiku:
            return Pricing(inputPerMillion: 1.0, outputPerMillion: 5.0)
        case ClaudeModel.sonnet:
            return Pricing(inputPerMillion: 3.0, outputPerMillion: 15.0)
        default:
            return Pricing(inputPerMillion: 3.0, outputPerMillion: 15.0)
        }
    }
}

// Why: cache writes cost 1.25x base input price, cache reads cost ~0.1x — see Anthropic prompt caching pricing.
public func estimatedCost(for usage: TokenUsage, model: String) -> Double {
    let pricing = Pricing.forModel(model)
    let inputCost = Double(usage.inputTokens) * pricing.inputPerMillion / 1_000_000
    let outputCost = Double(usage.outputTokens) * pricing.outputPerMillion / 1_000_000
    let cacheWriteCost = Double(usage.cacheCreationInputTokens) * pricing.inputPerMillion * 1.25 / 1_000_000
    let cacheReadCost = Double(usage.cacheReadInputTokens) * pricing.inputPerMillion * 0.1 / 1_000_000
    return inputCost + outputCost + cacheWriteCost + cacheReadCost
}

// Why: a single shared tracker so the CLI output and (later) the app toolbar read the same running total.
public final class UsageTracker {
    public private(set) var totalInputTokens = 0
    public private(set) var totalOutputTokens = 0
    public private(set) var totalCost = 0.0

    public init() {}

    @discardableResult
    public func record(_ usage: TokenUsage, model: String) -> Double {
        let cost = estimatedCost(for: usage, model: model)
        totalInputTokens += usage.inputTokens
        totalOutputTokens += usage.outputTokens
        totalCost += cost
        return cost
    }
}
