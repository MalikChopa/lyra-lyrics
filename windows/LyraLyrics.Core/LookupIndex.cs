using System.Text.Json;
using System.Text.Json.Serialization;

namespace LyraLyrics.Core;

/// <summary>Entrée de l'index disque (D4), vue publique : clé hachée, identifiant LRCLIB ou « non trouvé » (null), date. AUCUN champ texte.</summary>
public sealed record LookupEntry(
    [property: JsonPropertyName("key")] string Key,
    [property: JsonPropertyName("lrclibID")] int? LrclibId,
    [property: JsonPropertyName("storedAt")] DateTimeOffset StoredAt);

/// <summary>
/// Entrée telle qu'écrite sur le disque : comme <see cref="LookupEntry"/> plus le drapeau <c>manual</c> (choix MANUEL de l'utilisateur, 1.1.0 :
/// ne périme pas après 24 h ; absent = automatique, comme sur le Mac). Toujours sans texte.
/// </summary>
internal sealed record StoredEntry(
    [property: JsonPropertyName("key")] string Key,
    [property: JsonPropertyName("lrclibID")] int? LrclibId,
    [property: JsonPropertyName("storedAt")] DateTimeOffset StoredAt,
    [property: JsonPropertyName("manual"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] bool? Manual = null);

/// <summary>
/// Index disque sans texte (D4, port de LookupIndex.swift) : clé = SHA-256 salé injecté par l'app ; valeur = identifiant LRCLIB ou
/// « non trouvé » ; 24 h ; 500 entrées au plus.
/// </summary>
public sealed class LookupIndex
{
    public static readonly TimeSpan MaxAge = TimeSpan.FromHours(24);
    public const int MaxEntries = 500;
    public const int MaxManualEntries = 200;
    public const string FileName = "lookup-index.json";

    public abstract record Outcome
    {
        public sealed record Found(int Id) : Outcome;
        public sealed record NotFound : Outcome;
    }

    private List<StoredEntry> _entries;
    private readonly object _lock = new();
    /// <summary>W2 (constat 18) : une seule écriture de fichier à la fois (même fichier temporaire pour tous les appels de Save).</summary>
    private readonly object _saveLock = new();

    internal LookupIndex(IEnumerable<StoredEntry> entries) { _entries = entries.ToList(); }
    public LookupIndex() { _entries = new(); }

    public int Count { get { lock (_lock) return _entries.Count; } }
    public IReadOnlyList<LookupEntry> Entries { get { lock (_lock) return _entries.Select(e => new LookupEntry(e.Key, e.LrclibId, e.StoredAt)).ToList(); } }

    /// <summary>Matière hachée : titre et artiste normalisés, durée arrondie à la seconde (« ? » si inconnue).</summary>
    public static string Material(TrackInfo track)
    {
        var duration = track.Duration is double d ? ((long)Math.Round(d, MidpointRounding.AwayFromZero)).ToString() : "?";
        return string.Join("\u001F", TrackMatcher.NormalizeTitle(track.Title), TrackMatcher.NormalizeArtist(track.Artist), duration);
    }

    public static string KeyFor(TrackInfo track, Func<string, string> hasher) => hasher(Material(track));

    public Outcome? Lookup(string key, DateTimeOffset now)
    {
        lock (_lock)
        {
            PurgeLocked(now);
            var e = _entries.FirstOrDefault(x => x.Key == key && x.Manual != true);
            if (e is null) return null;
            return e.LrclibId is int id ? new Outcome.Found(id) : new Outcome.NotFound();
        }
    }

    public void Record(string key, Outcome outcome, DateTimeOffset now)
    {
        lock (_lock)
        {
            _entries.RemoveAll(e => e.Key == key && e.Manual != true);
            _entries.Add(new StoredEntry(key, outcome is Outcome.Found f ? f.Id : null, now));
            PurgeLocked(now);
            DropOldestAutomaticLocked();
        }
    }

    /// <summary>Au-delà de 500 entrées, on retire les plus anciennes entrées AUTOMATIQUES (les choix manuels restent, comme sur le Mac).</summary>
    private void DropOldestAutomaticLocked()
    {
        while (_entries.Count > MaxEntries)
        {
            var i = _entries.FindIndex(e => e.Manual != true);
            if (i < 0) break;
            _entries.RemoveAt(i);
        }
    }

    /// <summary>Choix manuel mémorisé pour cette clé (sans limite de 24 h).</summary>
    public int? ManualChoice(string key)
    {
        lock (_lock) return _entries.FirstOrDefault(e => e.Key == key && e.Manual == true)?.LrclibId;
    }

    public void RecordManual(string key, int id, DateTimeOffset now)
    {
        lock (_lock)
        {
            _entries.RemoveAll(e => e.Key == key && e.Manual == true);
            _entries.Add(new StoredEntry(key, id, now, true));
            if (_entries.Count(e => e.Manual == true) > MaxManualEntries) { var i = _entries.FindIndex(e => e.Manual == true); if (i >= 0) _entries.RemoveAt(i); }
            DropOldestAutomaticLocked();
        }
    }

    /// <summary>« Revenir au choix automatique ».</summary>
    public void RemoveManual(string key) { lock (_lock) _entries.RemoveAll(e => e.Key == key && e.Manual == true); }

    public void Purge(DateTimeOffset now) { lock (_lock) PurgeLocked(now); }
    private void PurgeLocked(DateTimeOffset now) => _entries.RemoveAll(e => e.Manual != true && (now - e.StoredAt > MaxAge || e.StoredAt > now.AddSeconds(60)));

    /// <summary>Oublie le résultat automatique d'une clé (« Réessayer ») : ne touche jamais à un choix manuel.</summary>
    public void Remove(string key) { lock (_lock) _entries.RemoveAll(e => e.Key == key && e.Manual != true); }
    public void Clear() { lock (_lock) _entries.Clear(); }

    // ---- Disque (seules les entrées sans texte sont encodées)

    public static LookupIndex Load(string path)
    {
        try
        {
            var data = File.ReadAllBytes(path);
            return new LookupIndex(JsonSerializer.Deserialize<List<StoredEntry>>(data) ?? new());
        }
        catch { return new LookupIndex(); }
    }

    public void Save(string path)
    {
        // L'instantané est pris DANS le verrou d'écriture : la dernière écriture porte toujours l'état le plus récent.
        lock (_saveLock)
        {
            List<StoredEntry> copy;
            lock (_lock) copy = _entries.ToList();
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var tmp = path + ".tmp";
            File.WriteAllBytes(tmp, JsonSerializer.SerializeToUtf8Bytes(copy));
            File.Move(tmp, path, overwrite: true);
        }
    }
}
