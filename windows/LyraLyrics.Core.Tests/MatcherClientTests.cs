using System.Text;
using System.Text.Json;
using Xunit.Abstractions;

namespace LyraLyrics.Core.Tests;

public class TrackMatcherTests
{
    private readonly ITestOutputHelper _out;
    public TrackMatcherTests(ITestOutputHelper o) { _out = o; }

    [Fact]
    public void GoldenTable_AllCasesPass()
    {
        using var doc = Fixtures.Json("golden/matching.json");
        int total = 0, passed = 0;
        var failures = new List<string>();
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            var name = c.GetProperty("name").GetString()!;
            if (c.TryGetProperty("normalize", out var norms))
            {
                foreach (var n in norms.EnumerateArray())
                {
                    total++;
                    var input = n.GetProperty("in").GetString()!; var output = n.GetProperty("out").GetString()!;
                    var got = TrackMatcher.NormalizeTitle(input);
                    if (got == output) passed++; else failures.Add($"{name} : « {input} » → « {got} » (attendu « {output} »)");
                }
                continue;
            }
            if (!c.TryGetProperty("track", out var t) || !c.TryGetProperty("candidates", out var cands) || !c.TryGetProperty("expect", out var expect)) continue;
            total++;
            double? Num(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
            string? Str(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
            bool Bool(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.True;
            var track = new TrackInfo(Str(t, "title")!, Str(t, "artist")!, Str(t, "album"), Num(t, "duration"), Player: "fake");
            var candidates = cands.EnumerateArray().Select(x => new TrackMatcher.Candidate(
                x.GetProperty("id").GetInt32(), Str(x, "title")!, Str(x, "artist")!, Str(x, "album"), Num(x, "duration"),
                Bool(x, "instrumental"), Bool(x, "synced"), Bool(x, "plain"))).ToList();
            var d = TrackMatcher.Choose(track, candidates);
            int? expId = expect.TryGetProperty("id", out var idEl) && idEl.ValueKind == JsonValueKind.Number ? idEl.GetInt32() : null;
            var expMode = expect.GetProperty("mode").GetString()!;
            if (d.Candidate?.Id == expId && d.Mode.ToString().Equals(expMode, StringComparison.OrdinalIgnoreCase)) passed++;
            else failures.Add($"{name} : obtenu id {d.Candidate?.Id.ToString() ?? "null"} mode {d.Mode} ({d.Reason}) ; attendu id {expId?.ToString() ?? "null"} mode {expMode}");
        }
        _out.WriteLine($"GOLDEN_MATCHING passed={passed} total={total} rate={(total == 0 ? 0 : passed * 100.0 / total):F1}%");
        foreach (var f in failures) _out.WriteLine("ÉCHEC : " + f);
        Assert.True(total >= 25, $"total={total}");
        Assert.Empty(failures);
        Assert.Equal(total, passed);
    }

    [Fact]
    public void ArtistHelpers_VideoTitles_DurationVerdict()
    {
        Assert.Equal(new HashSet<string> { "duo fictif", "chanteuse fictive" }, TrackMatcher.ArtistTokens("Duo fictif / Chanteuse fictive"));
        Assert.Contains("duo fictif", TrackMatcher.ArtistTokens("Duo fictif feat. Chanteuse fictive"));
        Assert.Equal(new HashSet<string> { "marin", "phare" }, TrackMatcher.ArtistTokens("Marin & Phare"));
        Assert.True(TrackMatcher.LooksLikeVideoTitle("Artiste - Chanson (Official Video)"));
        Assert.True(TrackMatcher.LooksLikeVideoTitle("Chanson | Lyrics"));
        Assert.False(TrackMatcher.LooksLikeVideoTitle("Artiste fictif"));
        Assert.Equal(new TrackMatcher.DurationVerdict.Close(4), TrackMatcher.GetDurationVerdict(100, 104));
        Assert.Equal(new TrackMatcher.DurationVerdict.Close(5), TrackMatcher.GetDurationVerdict(100, 105));
        Assert.Equal(new TrackMatcher.DurationVerdict.Far(-6), TrackMatcher.GetDurationVerdict(100, 94));
        Assert.Equal(new TrackMatcher.DurationVerdict.Unknown(), TrackMatcher.GetDurationVerdict(null, 94));
        Assert.Equal(new TrackMatcher.DurationVerdict.Unknown(), TrackMatcher.GetDurationVerdict(100, null));
    }

    [Fact]
    public void QueryHelpers()
    {
        Assert.Equal("Don't Stop Believin'", TrackMatcher.QueryTitle("Don't Stop Believin' (feat. Invité) - Remastered 2011"));
        Assert.Equal("Last Friday Night", TrackMatcher.ShortQueryTitle("Last Friday Night (T.G.I.F.)"));
        Assert.Equal("Roar", TrackMatcher.ShortQueryTitle("Roar"));
        Assert.Equal("Justin Bieber", TrackMatcher.PrimaryArtist("Justin Bieber, Daniel Caesar, Giveon"));
        Assert.Equal("Katy Perry", TrackMatcher.PrimaryArtist("Katy Perry feat. Kanye West"));
        Assert.Equal("AC/DC", TrackMatcher.PrimaryArtist("AC/DC"));
        Assert.Equal("Black Eyed Peas", TrackMatcher.WithoutThe("The Black Eyed Peas"));
        Assert.Equal("where is the love", TrackMatcher.TitleKey("Where Is The Love?"));
        Assert.Equal("?", TrackMatcher.TitleKey("?"));
        Assert.Equal("cafe", TrackMatcher.TitleKey("Café"));
        Assert.True(TrackMatcher.ArtistMatches("Black Eyed Peas", new TrackInfo("x", "The Black Eyed Peas")));
        Assert.True(TrackMatcher.ArtistMatches("Black Eyed Peas, Justin Timberlake", new TrackInfo("x", "Black Eyed Peas")));
        Assert.False(TrackMatcher.ArtistMatches("Artiste - Chanson (Official Video)", new TrackInfo("x", "Artiste")));
    }

    [Fact]
    public void NormalizeTitle_Basics()
    {
        Assert.Equal("rivière de papier", TrackMatcher.NormalizeTitle("Rivière de papier - Remastered 2011"));
        Assert.Equal("lanterne", TrackMatcher.NormalizeTitle("Lanterne (feat. Invité fictif)"));
        Assert.Equal("horloge (live)", TrackMatcher.NormalizeTitle("Horloge (Live)"));
        Assert.Equal("a and b", TrackMatcher.NormalizeTitle("A & B"));
    }
}

public class LrclibClientTests
{
    private static readonly byte[] Json200 = Encoding.UTF8.GetBytes("{\"id\":101,\"name\":\"Phares sur la mer\",\"trackName\":\"Phares sur la mer\",\"artistName\":\"Artiste fictif\",\"albumName\":\"Album fictif\",\"duration\":120.0,\"instrumental\":false,\"plainLyrics\":\"Les phares glissent sur la mer\\nEt la ville s'éteint sans bruit\",\"syncedLyrics\":\"[00:00.00] Les phares glissent sur la mer\\n[00:02.80] Et la ville s'éteint sans bruit\"}");
    private static readonly byte[] Json404 = Encoding.UTF8.GetBytes("{\"code\":404,\"name\":\"TrackNotFound\"}");
    private static readonly TrackInfo Track = new("Phares sur la mer", "Artiste fictif", "Album fictif", 120, Player: "fake");

    private sealed class Stub : ILrclibTransport
    {
        public abstract record Step;
        public sealed record Response(HttpReply Reply) : Step;
        public sealed record Failure(LrclibException E) : Step;
        public sealed record Hang : Step;
        private readonly Queue<Step> _steps;
        public List<LrclibRequest> Requests { get; } = new();
        public List<double> Timeouts { get; } = new();
        public Stub(params Step[] steps) { _steps = new(steps); }
        public async Task<HttpReply> SendAsync(LrclibRequest request, double timeout, CancellationToken ct)
        {
            Step step;
            lock (this) { Requests.Add(request); Timeouts.Add(timeout); step = _steps.Count == 0 ? new Failure(new LrclibException(LrclibErrorKind.Transport)) : _steps.Dequeue(); }
            switch (step)
            {
                case Response r: return r.Reply;
                case Failure f: throw f.E;
                default: await Task.Delay(TimeSpan.FromSeconds(30), ct); throw new LrclibException(LrclibErrorKind.Timeout);
            }
        }
    }

    private static (LrclibClient, Stub) Client(params Stub.Step[] steps)
    {
        var t = new Stub(steps);
        return (new LrclibClient(t, "TestApp/0.0.0 (test)", new Uri("http://127.0.0.1:1")), t);
    }

    private static Stub.Step Resp(int status, byte[]? body = null, Dictionary<string, string>? headers = null) => new Stub.Response(new HttpReply(status, headers, body));

    private static Dictionary<string, string> Query(Uri u) =>
        u.Query.TrimStart('?').Split('&').Select(p => p.Split('=', 2)).ToDictionary(p => Uri.UnescapeDataString(p[0]), p => Uri.UnescapeDataString(p[1]));

    [Fact]
    public async Task Get200_QueryFieldsAndUserAgent()
    {
        var (c, t) = Client(Resp(200, Json200));
        var result = await c.LookupAsync(Track);
        Assert.Equal("get", result.Via);
        Assert.Equal(101, result.Records[0].Id);
        Assert.True(result.Records[0].Candidate.HasSynced);
        var req = t.Requests[0];
        var q = Query(req.Url);
        Assert.Equal("/api/get", req.Url.AbsolutePath);
        Assert.Equal("Phares sur la mer", q["track_name"]);
        Assert.Equal("Artiste fictif", q["artist_name"]);
        Assert.Equal("Album fictif", q["album_name"]);
        Assert.Equal("120", q["duration"]);
        Assert.Equal("TestApp/0.0.0 (test)", req.UserAgent);
        var lyrics = LrclibClient.LyricsFrom(result.Records[0], Track, "get");
        Assert.Equal(2, lyrics!.Lines.Count);
        Assert.Equal(101, lyrics.LrclibId);
    }

    [Fact]
    public async Task NotFound_ThenSearch_WithPauseBetween()
    {
        var searchBody = Encoding.UTF8.GetBytes("[" + Encoding.UTF8.GetString(Json200) + "]");
        var (c, t) = Client(Resp(404, Json404), Resp(200, searchBody));
        var pauses = 0;
        var result = await c.LookupAsync(new TrackInfo("Phares sur la mer - Remastered 2031", "Artiste fictif", Duration: 120), betweenRequests: () => { pauses++; return Task.CompletedTask; });
        Assert.Equal("search", result.Via);
        Assert.Single(result.Records);
        Assert.Equal(1, pauses);
        Assert.Equal("/api/search", t.Requests[1].Url.AbsolutePath);
        Assert.Equal("Phares sur la mer", Query(t.Requests[1].Url)["track_name"]);
        var (c2, _) = Client(Resp(404, Json404), Resp(200, Encoding.UTF8.GetBytes("[]")));
        Assert.Empty((await c2.LookupAsync(Track)).Records);
    }

    [Fact]
    public void LyricsKinds()
    {
        var instrumental = new LrclibRecord(1, "Vent instrumental", "Trio imaginaire", Duration: 180, Instrumental: true);
        Assert.Equal(LyricsKind.Instrumental, LrclibClient.LyricsFrom(instrumental, Track, "get")!.Kind);
        var plain = new LrclibRecord(2, "Brume", "Duo fictif", Duration: 120, PlainLyrics: "Un\nDeux");
        var plainL = LrclibClient.LyricsFrom(plain, Track, "get")!;
        Assert.Equal(LyricsKind.Plain, plainL.Kind); Assert.Equal("Un\nDeux", plainL.PlainText);
        var far = new LrclibRecord(3, "Phares sur la mer", "Artiste fictif", Duration: 150, SyncedLyrics: "[00:01.00]Un\n[00:02.00]\n[00:03.00]Deux");
        var farL = LrclibClient.LyricsFrom(far, Track, "search")!;
        Assert.Equal("Un\nDeux", farL.PlainText);
        Assert.Contains("> 5 s", farL.Provenance);
        var tolerated = new LrclibRecord(6, "Phares sur la mer", "Artiste fictif", Duration: 128, SyncedLyrics: "[00:01.00]Un\n[00:03.00]Deux");
        var tolL = LrclibClient.LyricsFrom(tolerated, Track, "search")!;
        Assert.True(tolL.IsSynced);
        Assert.Contains("toléré ≤ 15 s", tolL.Provenance);
        var stranger = new LrclibRecord(7, "Phares sur la mer", "Quelqu'un d'autre", Duration: 128, SyncedLyrics: "[00:01.00]Un\n[00:03.00]Deux");
        Assert.False(LrclibClient.LyricsFrom(stranger, Track, "search")!.IsSynced);
        var unknown = new LrclibRecord(4, "Phares sur la mer", "Artiste fictif", Duration: null, SyncedLyrics: "[00:01.00]Un");
        Assert.True(LrclibClient.LyricsFrom(unknown, Track, "get")!.IsSynced);
        var empty = new LrclibRecord(5, "Rien", "Personne", Duration: 120, PlainLyrics: "  ", SyncedLyrics: "");
        Assert.Null(LrclibClient.LyricsFrom(empty, Track, "get"));
    }

    [Fact]
    public async Task Errors_InvalidJson_429_503_Unexpected_Timeout_Cancel()
    {
        var (bad, _) = Client(Resp(200, Encoding.UTF8.GetBytes("{pas du json")));
        Assert.Equal(LrclibErrorKind.InvalidJson, (await Assert.ThrowsAsync<LrclibException>(() => bad.GetAsync(Track))).Kind);
        var (limited, _) = Client(Resp(429, null, new() { ["retry-after"] = "3" }));
        var e429 = await Assert.ThrowsAsync<LrclibException>(() => limited.GetAsync(Track));
        Assert.Equal(LrclibErrorKind.RateLimited, e429.Kind); Assert.Equal("3", e429.RetryAfter);
        var (down, _) = Client(Resp(503, null, new() { ["Retry-After"] = "1" }));
        var e503 = await Assert.ThrowsAsync<LrclibException>(() => down.GetAsync(Track));
        Assert.Equal(LrclibErrorKind.ServerError, e503.Kind); Assert.Equal(503, e503.Status); Assert.Equal("1", e503.RetryAfter);
        var (odd, _) = Client(Resp(418));
        var e418 = await Assert.ThrowsAsync<LrclibException>(() => odd.GetAsync(Track));
        Assert.Equal(LrclibErrorKind.UnexpectedStatus, e418.Kind); Assert.Equal(418, e418.Status);
        var (slow, t) = Client(new Stub.Failure(new LrclibException(LrclibErrorKind.Timeout)));
        Assert.Equal(LrclibErrorKind.Timeout, (await Assert.ThrowsAsync<LrclibException>(() => slow.GetAsync(Track, 2.5))).Kind);
        Assert.Equal(new[] { 2.5 }, t.Timeouts);
        var (hanging, _) = Client(new Stub.Hang());
        using var cts = new CancellationTokenSource();
        var task = hanging.GetAsync(Track, ct: cts.Token);
        await Task.Delay(50);
        cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => task);
    }

    [Fact]
    public async Task GetById_Path()
    {
        var (c, t) = Client(Resp(200, Json200));
        var r = await c.GetAsync(101);
        Assert.Equal(101, r.Id);
        Assert.Equal("/api/get/101", t.Requests[0].Url.AbsolutePath);
    }
}
