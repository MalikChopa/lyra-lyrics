using System.Text.Json;

namespace LyraLyrics.Core;

/// <summary>Réponse HTTP minimale rendue par un transport.</summary>
public sealed record HttpReply(int Status, IReadOnlyDictionary<string, string>? Headers = null, byte[]? Body = null)
{
    public byte[] BodyBytes => Body ?? Array.Empty<byte>();
    public string? Header(string name) => Headers?.FirstOrDefault(h => string.Equals(h.Key, name, StringComparison.OrdinalIgnoreCase)).Value;
}

public sealed record LrclibRequest(Uri Url, string UserAgent);

/// <summary>Transport injectable : <c>HttpClient</c> sans cache ni cookies côté app, bouchon dans les tests.</summary>
public interface ILrclibTransport
{
    Task<HttpReply> SendAsync(LrclibRequest request, double timeoutSeconds, CancellationToken ct);
}

public enum LrclibErrorKind { NotFound, RateLimited, ServerError, UnexpectedStatus, InvalidJson, Timeout, Cancelled, Offline, Transport }

public sealed class LrclibException : Exception
{
    public LrclibErrorKind Kind { get; }
    public int Status { get; }
    public string? RetryAfter { get; }
    public LrclibException(LrclibErrorKind kind, int status = 0, string? retryAfter = null, string? message = null)
        : base(message ?? kind.ToString()) { Kind = kind; Status = status; RetryAfter = retryAfter; }
}

/// <summary>Entrée LRCLIB telle que reçue. NON sérialisable (D2) : construite depuis le JSON, jamais réencodée.</summary>
public sealed record LrclibRecord(int Id, string TrackName, string ArtistName, string? AlbumName = null, double? Duration = null,
                                  bool Instrumental = false, string? PlainLyrics = null, string? SyncedLyrics = null)
{
    public TrackMatcher.Candidate Candidate => new(Id, TrackName, ArtistName, AlbumName, Duration, Instrumental,
        HasSynced: !string.IsNullOrWhiteSpace(SyncedLyrics), HasPlain: !string.IsNullOrWhiteSpace(PlainLyrics));

    internal static LrclibRecord? FromJson(JsonElement e)
    {
        if (e.ValueKind != JsonValueKind.Object) return null;
        if (!e.TryGetProperty("id", out var idEl) || idEl.ValueKind != JsonValueKind.Number || !idEl.TryGetInt32(out var id)) return null;
        string? Str(string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        double? Num(string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
        var instrumental = e.TryGetProperty("instrumental", out var iv) && iv.ValueKind == JsonValueKind.True;
        return new LrclibRecord(id, Str("trackName") ?? "", Str("artistName") ?? "", Str("albumName"), Num("duration"), instrumental, Str("plainLyrics"), Str("syncedLyrics"));
    }
}

public sealed record LookupResult(IReadOnlyList<LrclibRecord> Records, string Via);

/// <summary>Requête de /api/search : champs séparés ou recherche combinée (q).</summary>
public abstract record SearchQuery
{
    public sealed record Fields(string Title, string Artist) : SearchQuery;
    public sealed record Combined(string Q) : SearchQuery;

    internal IReadOnlyList<(string, string)> Items => this switch
    {
        Fields f => new[] { ("track_name", f.Title), ("artist_name", f.Artist) },
        Combined c => new[] { ("q", c.Q) },
        _ => Array.Empty<(string, string)>(),
    };
}

/// <summary>Client LRCLIB (port de LRCLIBClient.swift) : GET /api/get puis, si 404, GET /api/search ; GET /api/get/{id}.</summary>
public sealed class LrclibClient
{
    public static readonly Uri PublicBaseUrl = new("https://lrclib.net");

    public Uri BaseUrl { get; }
    public ILrclibTransport Transport { get; }
    public string UserAgent { get; }

    public LrclibClient(ILrclibTransport transport, string userAgent, Uri? baseUrl = null)
    { Transport = transport; UserAgent = userAgent; BaseUrl = baseUrl ?? PublicBaseUrl; }

    public LrclibRequest MakeRequest(string path, IEnumerable<(string, string)>? query = null)
    {
        var b = new UriBuilder(BaseUrl) { Path = path };
        var q = query?.ToList();
        if (q is { Count: > 0 }) b.Query = string.Join("&", q.Select(p => $"{Uri.EscapeDataString(p.Item1)}={Uri.EscapeDataString(p.Item2)}"));
        return new LrclibRequest(b.Uri, UserAgent);
    }

    public async Task<LrclibRecord> GetAsync(TrackInfo track, double timeout = RequestGate.PerRequestTimeout, CancellationToken ct = default)
    {
        var query = new List<(string, string)> { ("track_name", track.Title), ("artist_name", track.Artist) };
        if (!string.IsNullOrEmpty(track.Album)) query.Add(("album_name", track.Album));
        if (track.Duration is double d && d > 0) query.Add(("duration", ((long)Math.Round(d, MidpointRounding.AwayFromZero)).ToString()));
        var reply = await Transport.SendAsync(MakeRequest("/api/get", query), timeout, ct).ConfigureAwait(false);
        Check(reply);
        return DecodeOne(reply.BodyBytes) ?? throw new LrclibException(LrclibErrorKind.InvalidJson);
    }

    public async Task<LrclibRecord> GetAsync(int id, double timeout = RequestGate.PerRequestTimeout, CancellationToken ct = default)
    {
        var reply = await Transport.SendAsync(MakeRequest($"/api/get/{id}"), timeout, ct).ConfigureAwait(false);
        Check(reply);
        return DecodeOne(reply.BodyBytes) ?? throw new LrclibException(LrclibErrorKind.InvalidJson);
    }

    public async Task<IReadOnlyList<LrclibRecord>> SearchAsync(SearchQuery query, double timeout = RequestGate.PerRequestTimeout, CancellationToken ct = default)
    {
        var reply = await Transport.SendAsync(MakeRequest("/api/search", query.Items), timeout, ct).ConfigureAwait(false);
        if (reply.Status == 404) return Array.Empty<LrclibRecord>();
        Check(reply);
        return DecodeMany(reply.BodyBytes) ?? throw new LrclibException(LrclibErrorKind.InvalidJson);
    }

    public Task<IReadOnlyList<LrclibRecord>> SearchAsync(TrackInfo track, double timeout = RequestGate.PerRequestTimeout, CancellationToken ct = default)
        => SearchAsync(new SearchQuery.Fields(TrackMatcher.QueryTitle(track.Title), track.Artist), timeout, ct);

    /// <summary>get puis, si 404, search ; <c>betweenRequests</c> laisse la porte imposer l'espacement.</summary>
    public async Task<LookupResult> LookupAsync(TrackInfo track, double timeout = RequestGate.PerRequestTimeout,
                                                Func<Task>? betweenRequests = null, CancellationToken ct = default)
    {
        try
        {
            var record = await GetAsync(track, timeout, ct).ConfigureAwait(false);
            return new LookupResult(new[] { record }, "get");
        }
        catch (LrclibException e) when (e.Kind == LrclibErrorKind.NotFound)
        {
            if (betweenRequests is not null) await betweenRequests().ConfigureAwait(false);
            var records = await SearchAsync(track, timeout, ct).ConfigureAwait(false);
            return new LookupResult(records, "search");
        }
    }

    /// <summary>
    /// Paroles à afficher pour une entrée : instrumental ; LRC parsé si la durée colle (≤ 5 s) ou est inconnue, ou si l'écart est de
    /// 5 à 15 s avec un artiste concordant ; sinon texte seul ; null s'il n'y a aucun texte.
    /// </summary>
    /// <param name="trustDuration">Choix manuel de l'utilisateur (1.1.0) : l'écart de durée n'écarte plus la synchro.</param>
    public static Lyrics? LyricsFrom(LrclibRecord record, TrackInfo track, string provenance, bool trustDuration = false)
    {
        if (record.Instrumental) return Lyrics.Instrumental(record.Id, provenance);
        var verdict = trustDuration ? new TrackMatcher.DurationVerdict.Unknown() : TrackMatcher.GetDurationVerdict(track.Duration, record.Duration);
        var lines = record.SyncedLyrics is null ? new List<LyricLine>() : LrcParser.Parse(record.SyncedLyrics).ToList();
        var why = provenance;
        var tolerated = false;
        switch (verdict)
        {
            case TrackMatcher.DurationVerdict.Unknown: why += ", durée inconnue"; break;
            case TrackMatcher.DurationVerdict.Close c: why += $", durée {TrackMatcher.Signed(c.Delta)} s"; break;
            case TrackMatcher.DurationVerdict.Far f:
                tolerated = TrackMatcher.SyncToleratesGap(f.Delta, TrackMatcher.ArtistMatches(record.ArtistName, track));
                why += $", durée {TrackMatcher.Signed(f.Delta)} s (> 5 s{(tolerated ? ", toléré ≤ 15 s" : "")})";
                break;
        }
        if (lines.Count > 0 && verdict is TrackMatcher.DurationVerdict.Far && !tolerated)
        {
            var trimmed = record.PlainLyrics?.Trim();
            var text = string.IsNullOrEmpty(trimmed) ? LrcParser.PlainText(lines) : trimmed;
            return Lyrics.Plain(text, record.Id, why);
        }
        if (lines.Count > 0) return Lyrics.Synced(lines, record.Id, why);
        var plain = record.PlainLyrics?.Trim();
        if (!string.IsNullOrEmpty(plain)) return Lyrics.Plain(plain, record.Id, why + ", texte seul");
        return null;
    }

    // ---- Détails

    internal static void Check(HttpReply r)
    {
        switch (r.Status)
        {
            case >= 200 and <= 299: return;
            case 404: throw new LrclibException(LrclibErrorKind.NotFound, 404);
            case 429: throw new LrclibException(LrclibErrorKind.RateLimited, 429, r.Header("Retry-After"));
            case >= 500 and <= 599: throw new LrclibException(LrclibErrorKind.ServerError, r.Status, r.Header("Retry-After"));
            default: throw new LrclibException(LrclibErrorKind.UnexpectedStatus, r.Status);
        }
    }

    internal static LrclibRecord? DecodeOne(byte[] data)
    {
        try { using var doc = JsonDocument.Parse(data); return LrclibRecord.FromJson(doc.RootElement); }
        catch (JsonException) { return null; }
    }

    internal static List<LrclibRecord>? DecodeMany(byte[] data)
    {
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return null;
            return doc.RootElement.EnumerateArray().Select(LrclibRecord.FromJson).Where(r => r is not null).Select(r => r!).ToList();
        }
        catch (JsonException) { return null; }
    }
}
