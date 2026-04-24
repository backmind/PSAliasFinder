using System.Collections.Concurrent;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Subsystem;
using System.Management.Automation.Subsystem.Feedback;

namespace PSAliasFinder;

public sealed class PSAliasFeedback
    : IFeedbackProvider, IModuleAssemblyInitializer, IModuleAssemblyCleanup
{
    private static readonly Guid ProviderId = new("e6fac608-af42-4aa0-81bb-fb9e5f9c8930");

    public Guid Id => ProviderId;
    public string Name => "PSAliasFinder";
    public string Description => "Suggests shorter aliases for long commands you just ran.";
    public Dictionary<string, string>? FunctionsToDefine => null;
    public FeedbackTrigger Trigger => FeedbackTrigger.Success;

    private readonly System.Management.Automation.PowerShell _powershell
        = System.Management.Automation.PowerShell.Create();
    private readonly AliasCache _cache;
    private readonly ConcurrentDictionary<string, DateTimeOffset> _recentSuggestions
        = new(StringComparer.OrdinalIgnoreCase);

    public PSAliasFeedback()
    {
        _cache = new AliasCache(_powershell);
    }

    public FeedbackItem? GetFeedback(FeedbackContext context, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();

        var config = ProviderConfig.Current;
        if (!config.Enabled) return null;

        var root = context.CommandLineAst as ScriptBlockAst;
        var cmdAst = root?.Find(a => a is CommandAst, searchNestedScriptBlocks: false) as CommandAst;
        if (cmdAst is null) return null;

        var invoked = cmdAst.GetCommandName();
        if (string.IsNullOrEmpty(invoked)) return null;

        token.ThrowIfCancellationRequested();

        var pipeline = root?.Find(a => a is PipelineAst, searchNestedScriptBlocks: false) as PipelineAst;
        if (pipeline is not null && pipeline.PipelineElements.Count > config.MaxPipes + 1) return null;

        if (context.CommandLine.Split(' ').Length > config.MaxArguments) return null;

        if (invoked.Length < config.MinCommandLength) return null;

        token.ThrowIfCancellationRequested();

        if (_cache.IsAlias(invoked)) return null;

        foreach (var ignored in config.IgnoredCommands)
        {
            if (string.Equals(ignored, invoked, StringComparison.OrdinalIgnoreCase)) return null;
        }

        var all = _cache.GetAliasesFor(invoked);
        if (all is null || all.Count == 0) return null;

        var shortest = all[0];
        if (invoked.Length - shortest.Length < config.MinCharsSaved) return null;

        token.ThrowIfCancellationRequested();

        if (config.CooldownSeconds > 0)
        {
            var now = DateTimeOffset.UtcNow;
            if (_recentSuggestions.TryGetValue(invoked, out var lastShown) &&
                now - lastShown < TimeSpan.FromSeconds(config.CooldownSeconds))
            {
                return null;
            }
            _recentSuggestions[invoked] = now;
        }

        var take = Math.Max(1, Math.Min(config.MaxSuggestions, all.Count));
        var actions = new List<string>(take);
        for (var i = 0; i < take; i++) actions.Add(all[i]);

        var header = take == 1
            ? $"Shorter alias for '{invoked}':"
            : $"Shorter aliases for '{invoked}':";

        return new FeedbackItem(
            header: header,
            actions: actions,
            footer: null,
            layout: FeedbackDisplayLayout.Portrait);
    }

    public void OnImport()
    {
        try
        {
            SubsystemManager.RegisterSubsystem(SubsystemKind.FeedbackProvider, this);
        }
        catch (InvalidOperationException)
        {
        }
    }

    public void OnRemove(PSModuleInfo psModuleInfo)
    {
        try { SubsystemManager.UnregisterSubsystem<IFeedbackProvider>(Id); }
        catch (InvalidOperationException) { }

        _powershell.Dispose();
    }
}
