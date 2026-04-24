using System.Collections.Concurrent;
using System.Management.Automation;

namespace PSAliasFinder;

internal sealed class AliasCache
{
    private static readonly TimeSpan Ttl = TimeSpan.FromSeconds(60);

    private readonly System.Management.Automation.PowerShell _ps;
    private readonly ConcurrentDictionary<string, string[]> _byDefinition
        = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, byte> _aliasNames
        = new(StringComparer.OrdinalIgnoreCase);
    private DateTimeOffset _builtAt = DateTimeOffset.MinValue;
    private readonly object _rebuildLock = new();

    public AliasCache(System.Management.Automation.PowerShell ps)
    {
        _ps = ps;
    }

    public IReadOnlyList<string>? GetAliasesFor(string command)
    {
        EnsureFresh();
        return _byDefinition.TryGetValue(command, out var arr) ? arr : null;
    }

    public string? GetShortestAliasFor(string command)
    {
        var all = GetAliasesFor(command);
        return all is { Count: > 0 } ? all[0] : null;
    }

    public bool IsAlias(string name)
    {
        EnsureFresh();
        return _aliasNames.ContainsKey(name);
    }

    private void EnsureFresh()
    {
        if (DateTimeOffset.UtcNow - _builtAt < Ttl) return;
        lock (_rebuildLock)
        {
            if (DateTimeOffset.UtcNow - _builtAt < Ttl) return;
            Rebuild();
            _builtAt = DateTimeOffset.UtcNow;
        }
    }

    private void Rebuild()
    {
        _byDefinition.Clear();
        _aliasNames.Clear();

        System.Collections.ObjectModel.Collection<PSObject> results;
        try
        {
            _ps.Commands.Clear();
            results = _ps.AddCommand("Get-Alias").Invoke();
        }
        finally
        {
            _ps.Commands.Clear();
        }

        var grouped = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var result in results)
        {
            if (result?.BaseObject is not AliasInfo alias) continue;

            _aliasNames.TryAdd(alias.Name, 0);

            var def = alias.Definition;
            if (string.IsNullOrEmpty(def)) continue;

            if (!grouped.TryGetValue(def, out var list))
            {
                list = new List<string>();
                grouped[def] = list;
            }
            list.Add(alias.Name);
        }

        foreach (var kv in grouped)
        {
            kv.Value.Sort(static (a, b) =>
            {
                var byLen = a.Length.CompareTo(b.Length);
                return byLen != 0 ? byLen : StringComparer.OrdinalIgnoreCase.Compare(a, b);
            });
            _byDefinition[kv.Key] = kv.Value.ToArray();
        }
    }
}
