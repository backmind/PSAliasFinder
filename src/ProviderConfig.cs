using System.Text.Json;

namespace PSAliasFinder;

public sealed class ProviderConfig
{
    public bool Enabled { get; set; } = true;
    public int MinCommandLength { get; set; } = 8;
    public int MaxPipes { get; set; } = 1;
    public int MaxArguments { get; set; } = 10;
    public int MinCharsSaved { get; set; } = 4;
    public int CooldownSeconds { get; set; } = 1800;
    public int MaxSuggestions { get; set; } = 1;
    public string[] IgnoredCommands { get; set; } = Array.Empty<string>();

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
    };

    private static readonly object _ioLock = new();
    private static ProviderConfig _current = LoadFromDisk();

    public static ProviderConfig Current => _current;

    public static string ConfigDir
    {
        get
        {
            var overrideDir = Environment.GetEnvironmentVariable("PSALIASFINDER_CONFIG_DIR");
            if (!string.IsNullOrEmpty(overrideDir)) return overrideDir;
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "PSAliasFinder");
        }
    }

    public static string ConfigFile => Path.Combine(ConfigDir, "config.json");

    public static ProviderConfig LoadOrDefault() => _current;

    private static ProviderConfig LoadFromDisk()
    {
        try
        {
            if (!File.Exists(ConfigFile)) return new ProviderConfig();
            var json = File.ReadAllText(ConfigFile);
            return JsonSerializer.Deserialize<ProviderConfig>(json, JsonOpts) ?? new ProviderConfig();
        }
        catch
        {
            return new ProviderConfig();
        }
    }

    public void Save()
    {
        lock (_ioLock)
        {
            Directory.CreateDirectory(ConfigDir);
            var json = JsonSerializer.Serialize(this, JsonOpts);
            File.WriteAllText(ConfigFile, json);
            _current = this;
        }
    }

    public static void Reload()
    {
        lock (_ioLock)
        {
            _current = LoadFromDisk();
        }
    }
}
