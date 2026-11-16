namespace LyraLyrics.Core;

/// <summary>Cache mémoire des paroles (D2) : 2 entrées au plus, jamais sur disque, vidé à la fermeture.</summary>
public sealed class LyricsCache
{
    public const int Capacity = 2;
    private readonly List<(string Key, Lyrics Lyrics)> _entries = new();   // du plus ancien au plus récent
    private readonly object _lock = new();

    public int Count { get { lock (_lock) return _entries.Count; } }
    public IReadOnlyList<string> Keys { get { lock (_lock) return _entries.Select(e => e.Key).ToList(); } }

    public Lyrics? Peek(string key) { lock (_lock) return _entries.FirstOrDefault(e => e.Key == key).Lyrics; }

    public Lyrics? Fetch(string key)
    {
        lock (_lock)
        {
            var i = _entries.FindIndex(e => e.Key == key);
            if (i < 0) return null;
            var e = _entries[i]; _entries.RemoveAt(i); _entries.Add(e);
            return e.Lyrics;
        }
    }

    public void Store(Lyrics lyrics, string key)
    {
        lock (_lock)
        {
            _entries.RemoveAll(e => e.Key == key);
            _entries.Add((key, lyrics));
            while (_entries.Count > Capacity) _entries.RemoveAt(0);
        }
    }

    public void Remove(string key) { lock (_lock) _entries.RemoveAll(e => e.Key == key); }
    public void Clear() { lock (_lock) _entries.Clear(); }
}
