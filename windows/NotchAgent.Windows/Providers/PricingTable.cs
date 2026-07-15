using NotchAgent.Windows.Models;

namespace NotchAgent.Windows.Providers;

/// USD per million tokens. Values mirror public pricing pages and are only
/// used for local *estimates* — the UI always labels results as estimated.
public readonly record struct ModelPricing(double Input, double Output, double CacheWrite, double CacheRead);

public static class PricingTable
{
    /// Longest-prefix match wins, so keep more specific prefixes first.
    private static readonly (string Prefix, ModelPricing Pricing)[] Entries =
    {
        ("claude-fable", new ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-opus", new ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-sonnet", new ModelPricing(3, 15, 3.75, 0.3)),
        ("claude-haiku", new ModelPricing(1, 5, 1.25, 0.1)),
        ("claude-3-5-haiku", new ModelPricing(0.8, 4, 1, 0.08)),
        ("claude-3-opus", new ModelPricing(15, 75, 18.75, 1.5)),
        ("claude-3-haiku", new ModelPricing(0.25, 1.25, 0.3, 0.03)),
        ("claude", new ModelPricing(3, 15, 3.75, 0.3)),
        ("gpt-5", new ModelPricing(1.25, 10, 0, 0.125)),
        ("gpt-4", new ModelPricing(2.5, 10, 0, 1.25)),
        ("gemini-2.5-pro", new ModelPricing(1.25, 10, 0, 0.31)),
        ("gemini-2.5-flash", new ModelPricing(0.3, 2.5, 0, 0.075)),
        ("gemini", new ModelPricing(1.25, 10, 0, 0.31)),
    };

    public static ModelPricing? Pricing(string model)
    {
        foreach (var (prefix, pricing) in Entries)
        {
            if (model.StartsWith(prefix, StringComparison.Ordinal))
            {
                return pricing;
            }
        }
        return null;
    }

    /// `usage.Input` must already exclude cached tokens for providers that
    /// report cache reads separately (Claude does; Codex is normalized upstream).
    public static double CostUsd(string model, TokenUsage usage)
    {
        if (Pricing(model) is not { } p)
        {
            return 0;
        }
        return usage.Input / 1e6 * p.Input
            + usage.Output / 1e6 * p.Output
            + usage.CacheWrite / 1e6 * p.CacheWrite
            + usage.CacheRead / 1e6 * p.CacheRead;
    }
}
