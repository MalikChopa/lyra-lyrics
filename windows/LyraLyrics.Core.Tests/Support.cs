using System.Text;
using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>Accès aux Fixtures partagées du dépôt (dossier <c>Fixtures/</c> à la racine, remonté depuis le dossier de test).</summary>
public static class Fixtures
{
    public static string Root { get; } = Locate();
    private static string Locate()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            var candidate = Path.Combine(dir.FullName, "Fixtures", "golden", "matching.json");
            if (File.Exists(candidate)) return Path.Combine(dir.FullName, "Fixtures");
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("Dossier Fixtures introuvable en remontant depuis " + AppContext.BaseDirectory);
    }
    public static string Text(string relative) => File.ReadAllText(Path.Combine(Root, relative), new UTF8Encoding(false));
    public static byte[] Bytes(string relative) => File.ReadAllBytes(Path.Combine(Root, relative));
    public static JsonDocument Json(string relative) => JsonDocument.Parse(Bytes(relative));
}

/// <summary>Horloge simulée : seule l'attente la fait avancer.</summary>
public sealed class VirtualClock
{
    private readonly object _l = new();
    private double _t;
    public double Now { get { lock (_l) return _t; } }
    public void Advance(double s) { lock (_l) _t += Math.Max(0, s); }
    public Func<double, CancellationToken, Task> Sleeper => async (s, ct) => { Advance(s); await Task.Yield(); };
}

/// <summary>Faux LRCLIB piloté par une fonction.</summary>
public sealed class ScriptedTransport : ILrclibTransport
{
    public sealed record Call(string Path, IReadOnlyDictionary<string, string> Query, double At);
    public abstract record Reply
    {
        public sealed record Http(int Status, Dictionary<string, string>? Headers = null, byte[]? Body = null) : Reply;
        public sealed record Error(LrclibException Exception) : Reply;
    }

    private readonly object _l = new();
    private readonly List<Call> _calls = new();
    private readonly VirtualClock _clock;
    private readonly Func<Call, int, Reply> _handler;
    public ScriptedTransport(VirtualClock clock, Func<Call, int, Reply> handler) { _clock = clock; _handler = handler; }

    public Task<HttpReply> SendAsync(LrclibRequest request, double timeoutSeconds, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        var url = request.Url;
        var query = new Dictionary<string, string>();
        foreach (var pair in url.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var kv = pair.Split('=', 2);
            query.TryAdd(Uri.UnescapeDataString(kv[0]), kv.Length > 1 ? Uri.UnescapeDataString(kv[1]) : "");
        }
        var call = new Call(url.AbsolutePath, query, _clock.Now);
        int nth;
        lock (_l) { _calls.Add(call); nth = _calls.Count(c => c.Path == call.Path); }
        switch (_handler(call, nth))
        {
            case Reply.Http h: return Task.FromResult(new HttpReply(h.Status, h.Headers, h.Body));
            case Reply.Error e: throw e.Exception;
            default: throw new InvalidOperationException();
        }
    }

    public List<Call> Calls { get { lock (_l) return _calls.ToList(); } }
    public List<string> Paths => Calls.Select(c => c.Path).ToList();
    public List<Call> CallsTo(string path) => Calls.Where(c => c.Path == path).ToList();
}

public static class Wire
{
    public static Dictionary<string, object?> Record(int id, string title, string artist, string album = "Album fictif", double duration = 200,
                                                    bool synced = true, bool plain = true, bool instrumental = false)
    {
        var d = new Dictionary<string, object?> { ["id"] = id, ["trackName"] = title, ["artistName"] = artist, ["albumName"] = album, ["duration"] = duration, ["instrumental"] = instrumental };
        if (synced) d["syncedLyrics"] = "[00:01.00]Un\n[00:03.00]Deux\n[00:05.00]Trois";
        if (plain) d["plainLyrics"] = "Un\nDeux\nTrois";
        return d;
    }
    public static byte[] Json(object o) => JsonSerializer.SerializeToUtf8Bytes(o);
    public static ScriptedTransport.Reply Ok(Dictionary<string, object?> record) => new ScriptedTransport.Reply.Http(200, null, Json(record));
    public static ScriptedTransport.Reply List(params Dictionary<string, object?>[] records) => new ScriptedTransport.Reply.Http(200, null, Json(records));
    public static readonly ScriptedTransport.Reply NotFound = new ScriptedTransport.Reply.Http(404, null, Encoding.UTF8.GetBytes("{\"code\":404}"));
    public static ScriptedTransport.Reply Busy(string? retryAfter = "1") =>
        new ScriptedTransport.Reply.Http(503, retryAfter is null ? null : new Dictionary<string, string> { ["Retry-After"] = retryAfter }, Encoding.UTF8.GetBytes("The server is busy"));
    public static ScriptedTransport.Reply Err(LrclibErrorKind k) => new ScriptedTransport.Reply.Error(new LrclibException(k));
}

public sealed class EventLog
{
    private readonly object _l = new();
    private readonly List<LookupEvent> _items = new();
    public void Add(LookupEvent e) { lock (_l) _items.Add(e); }
    public List<LookupEvent> Events { get { lock (_l) return _items.ToList(); } }
    public int BusyCount => Events.Count(e => e is LookupEvent.Busy);
    public int Retrying => Events.Count(e => e is LookupEvent.Retrying);
    public double? FirstBusy => Events.OfType<LookupEvent.Busy>().Select(b => (double?)b.RetryIn).FirstOrDefault();
}
