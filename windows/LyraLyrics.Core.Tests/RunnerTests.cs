namespace LyraLyrics.Core.Tests;

public class LookupRunnerTests
{
    private static readonly TrackInfo Track = new("Phares sur la mer", "Artiste fictif", "Album fictif", 200, Player: "fake");

    private static (LookupRunner, ScriptedTransport, VirtualClock) Make(Func<ScriptedTransport.Call, int, ScriptedTransport.Reply> handler, int titlesBeforeBreaker = 3)
    {
        var clock = new VirtualClock();
        var transport = new ScriptedTransport(clock, handler);
        var client = new LrclibClient(transport, "Test/0 (test)", new Uri("http://127.0.0.1:1"));
        var runner = new LookupRunner(client, new RequestGate(titlesBeforeBreaker, random: () => 0.5), () => clock.Now, clock.Sleeper);
        return (runner, transport, clock);
    }

    private static Task<LookupOutcome> Run(LookupRunner r, TrackInfo t, int? knownId = null, EventLog? log = null)
    {
        log ??= new EventLog();
        return r.RunAsync(t, knownId, log.Add, CancellationToken.None);
    }

    private static bool IsSynced(LookupOutcome o) => o is LookupOutcome.Found f && f.Lyrics.IsSynced;

    [Fact]
    public async Task GetHit_SingleRequest()
    {
        var (r, t, _) = Make((c, n) => Wire.Ok(Wire.Record(1, "Phares sur la mer", "Artiste fictif")));
        Assert.True(IsSynced(await Run(r, Track)));
        Assert.Equal(new[] { "/api/get" }, t.Paths);
    }

    [Fact]
    public async Task Get503_GoesImmediatelyToSearch()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get" ? Wire.Busy("1") : Wire.List(Wire.Record(2, "Phares sur la mer", "Artiste fictif")));
        Assert.True(IsSynced(await Run(r, Track)));
        Assert.Equal(new[] { "/api/get", "/api/search" }, t.Paths);
        var gap = t.Calls[1].At - t.Calls[0].At;
        Assert.True(gap >= 0.3 && gap < 1.0, $"écart {gap} s");
    }

    [Fact]
    public async Task GetTimeout_Or_TransportFailure_SearchTakesOver()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get" ? Wire.Err(LrclibErrorKind.Timeout) : Wire.List(Wire.Record(3, "Phares sur la mer", "Artiste fictif")));
        Assert.True(IsSynced(await Run(r, Track)));
        Assert.Equal(new[] { "/api/get", "/api/search" }, t.Paths);
        var (r2, t2, _) = Make((c, n) => c.Path == "/api/get" ? Wire.Err(LrclibErrorKind.Transport) : Wire.List(Wire.Record(3, "Phares sur la mer", "Artiste fictif")));
        Assert.True(IsSynced(await Run(r2, Track)));
        Assert.Equal(new[] { "/api/get", "/api/search" }, t2.Paths);
    }

    [Fact]
    public async Task Get503ThenRetriedAfterRetryAfter_WhenSearchEmpty()
    {
        var (r, t, _) = Make((c, nth) => c.Path == "/api/get"
            ? (nth == 1 ? Wire.Busy("2") : Wire.Ok(Wire.Record(4, "Phares sur la mer", "Artiste fictif")))
            : Wire.List());
        Assert.True(IsSynced(await Run(r, Track)));
        var gets = t.CallsTo("/api/get");
        Assert.Equal(2, gets.Count);
        Assert.True(gets[1].At - gets[0].At >= 2.0);
        Assert.True(t.Calls.Count <= RequestGate.MaxRequestsPerAttempt);
    }

    [Fact]
    public async Task AllBusyAtFirst_ThenGood_BusyThenAutomaticRetry_NeverUnavailable()
    {
        var failing = 0;
        var (r, t, clock) = Make((c, n) =>
        {
            if (failing < 9) { failing++; return Wire.Busy("1"); }
            return Wire.Ok(Wire.Record(5, "Phares sur la mer", "Artiste fictif"));
        });
        var log = new EventLog();
        var o = await Run(r, Track, log: log);
        Assert.True(IsSynced(o));
        Assert.True(log.BusyCount >= 1 && log.Retrying >= 1);
        Assert.True(log.FirstBusy <= 5.0);
        Assert.True(clock.Now >= 5);
        Assert.Equal(10, t.Calls.Count);
        Assert.True(t.Calls.Count(c => c.At < 5) <= RequestGate.MaxRequestsPerAttempt);
    }

    [Fact]
    public async Task PermanentOutage_Stalled_NotNotFound_BoundedRequests()
    {
        var (r, t, clock) = Make((c, n) => Wire.Busy("1"));
        var log = new EventLog();
        var o = await Run(r, Track, log: log);
        Assert.IsType<LookupOutcome.Stalled>(o);
        Assert.True(t.Calls.Count <= RequestGate.MaxRequestsPerAttempt + 6 * 3);
        Assert.True(clock.Now >= 5 + 10 + 20 + 40 + 60 + 60);
        Assert.Equal(6, log.Retrying);
    }

    [Fact]
    public async Task NotFeverywhere_DefinitiveNotFound_After5Requests()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get" ? Wire.NotFound : Wire.List());
        var o = await Run(r, new TrackInfo("Phares sur la mer (T.G.I.F.)", "Artiste fictif, Autre voix", Duration: 200));
        var nf = Assert.IsType<LookupOutcome.NotFound>(o);
        Assert.True(nf.Definitive);
        Assert.Equal(5, t.Calls.Count);
    }

    [Fact]
    public async Task NotDefinitive_WhenAStepStayedInError()
    {
        var (r, _, _) = Make((c, n) => c.Path == "/api/get" ? Wire.Busy("1") : Wire.List());
        Assert.False((await Run(r, Track)) is LookupOutcome.NotFound);
    }

    [Fact]
    public async Task QueryNormalisation_KeepsCaseAndApostrophes_CombinedQ()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get" ? Wire.NotFound : Wire.List());
        await Run(r, new TrackInfo("Don't Stop Believin' (feat. Invité) - Remastered 2011", "Journey", Duration: 250));
        var searches = t.CallsTo("/api/search");
        Assert.Equal("Don't Stop Believin'", searches[0].Query["track_name"]);
        Assert.Equal("Journey", searches[0].Query["artist_name"]);
        Assert.Contains(searches, s => s.Query.GetValueOrDefault("q") == "Don't Stop Believin' Journey");
        Assert.Equal("Don't Stop Believin' (feat. Invité) - Remastered 2011", t.CallsTo("/api/get")[0].Query["track_name"]);
    }

    [Fact]
    public async Task ThePrefix_CombinedQueryWithoutThe()
    {
        var (r, t, _) = Make((c, n) =>
        {
            if (c.Path == "/api/get") return Wire.NotFound;
            if (c.Query.ContainsKey("q")) return Wire.List(Wire.Record(7, "I Gotta Feeling", "Black Eyed Peas", duration: 289));
            return Wire.List();
        });
        Assert.True(IsSynced(await Run(r, new TrackInfo("I Gotta Feeling", "The Black Eyed Peas", Duration: 289))));
        Assert.Equal("I Gotta Feeling Black Eyed Peas", t.CallsTo("/api/search").Last().Query["q"]);
    }

    [Fact]
    public async Task MultiArtist_PrimaryArtistIsTried()
    {
        var (r, t, _) = Make((c, n) =>
        {
            if (c.Path == "/api/get") return Wire.NotFound;
            if (c.Query.GetValueOrDefault("artist_name") == "Justin Bieber") return Wire.List(Wire.Record(8, "Peaches (feat. Daniel Caesar & Giveon)", "Justin Bieber", duration: 198));
            return Wire.List();
        });
        Assert.True(IsSynced(await Run(r, new TrackInfo("Peaches (feat. Daniel Caesar & Giveon)", "Justin Bieber, Daniel Caesar, Giveon", Duration: 198))));
        var s = t.CallsTo("/api/search");
        Assert.Equal(2, s.Count);
        Assert.Equal("Justin Bieber, Daniel Caesar, Giveon", s[0].Query["artist_name"]);
        Assert.Equal("Justin Bieber", s[1].Query["artist_name"]);
        Assert.Equal("Peaches", s[1].Query["track_name"]);
    }

    [Fact]
    public async Task ShortTitleStep()
    {
        var (r, t, _) = Make((c, n) =>
        {
            if (c.Path == "/api/get") return Wire.NotFound;
            if (c.Query.GetValueOrDefault("track_name") == "Last Friday Night") return Wire.List(Wire.Record(9, "Last Friday Night", "Katy Perry", duration: 230));
            return Wire.List();
        });
        Assert.True(IsSynced(await Run(r, new TrackInfo("Last Friday Night (T.G.I.F.)", "Katy Perry", Duration: 230))));
        Assert.Equal("Last Friday Night", t.CallsTo("/api/search").Last().Query["track_name"]);
    }

    [Fact]
    public async Task DurationGap_6to15Synced_Over15Plain()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get" ? Wire.NotFound : Wire.List(Wire.Record(10, "Phares sur la mer", "Artiste fictif", duration: 211)));
        var f = Assert.IsType<LookupOutcome.Found>(await Run(r, Track));
        Assert.True(f.Lyrics.IsSynced);
        Assert.Contains("toléré ≤ 15 s", f.Lyrics.Provenance);
        Assert.Equal(2, t.Calls.Count);
        var (r2, _, _) = Make((c, n) => c.Path == "/api/get" ? Wire.NotFound : Wire.List(Wire.Record(11, "Phares sur la mer", "Artiste fictif", duration: 230)));
        var f2 = Assert.IsType<LookupOutcome.Found>(await Run(r2, Track));
        Assert.True(f2.Lyrics.PlainText is not null && !f2.Lyrics.IsSynced);
    }

    [Fact]
    public async Task GetPlainOnly_SearchesAndPrefersSynced()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get"
            ? Wire.Ok(Wire.Record(12, "Phares sur la mer", "Artiste fictif", synced: false))
            : Wire.List(Wire.Record(13, "Phares sur la mer", "Artiste fictif")));
        var f = Assert.IsType<LookupOutcome.Found>(await Run(r, Track));
        Assert.True(f.Lyrics.IsSynced && f.Lyrics.LrclibId == 13);
        Assert.Equal(new[] { "/api/get", "/api/search" }, t.Paths);
    }

    [Fact]
    public async Task PlainOnly_NothingBetter_PlainReturned()
    {
        var (r, _, _) = Make((c, n) => c.Path == "/api/get" ? Wire.Ok(Wire.Record(14, "Phares sur la mer", "Artiste fictif", synced: false)) : Wire.List());
        var f = Assert.IsType<LookupOutcome.Found>(await Run(r, Track));
        Assert.NotNull(f.Lyrics.PlainText);
    }

    [Fact]
    public async Task PlainOnly_StopsEarlyIfConfirmed_ElseKeepsTrying()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get"
            ? Wire.Ok(Wire.Record(14, "Phares sur la mer", "Artiste fictif", synced: false))
            : Wire.List(Wire.Record(14, "Phares sur la mer", "Artiste fictif", synced: false)));
        Assert.NotNull(Assert.IsType<LookupOutcome.Found>(await Run(r, Track)).Lyrics.PlainText);
        Assert.Equal(new[] { "/api/get", "/api/search" }, t.Paths);
        var (r2, t2, _) = Make((c, n) => c.Path == "/api/get" ? Wire.NotFound : Wire.List(Wire.Record(15, "Phares sur la mer", "Quelqu'un d'autre", synced: false)));
        await Run(r2, Track);
        Assert.Equal(3, t2.Calls.Count);
    }

    [Fact]
    public async Task Instrumental_StopsImmediately()
    {
        var (r, t, _) = Make((c, n) => Wire.Ok(Wire.Record(15, "Phares sur la mer", "Artiste fictif", synced: false, plain: false, instrumental: true)));
        Assert.Equal(LyricsKind.Instrumental, Assert.IsType<LookupOutcome.Found>(await Run(r, Track)).Lyrics.Kind);
        Assert.Single(t.Calls);
    }

    [Fact]
    public async Task KnownId_GetByIdFirst_404FallsBackToNormal()
    {
        var (r, t, _) = Make((c, n) => c.Path == "/api/get/77" ? Wire.NotFound : Wire.Ok(Wire.Record(16, "Phares sur la mer", "Artiste fictif")));
        Assert.True(IsSynced(await Run(r, Track, 77)));
        Assert.Equal(new[] { "/api/get/77", "/api/get" }, t.Paths);
        var (r2, t2, _) = Make((c, n) => Wire.Ok(Wire.Record(77, "Phares sur la mer", "Artiste fictif")));
        Assert.True(IsSynced(await Run(r2, Track, 77)));
        Assert.Equal(new[] { "/api/get/77" }, t2.Paths);
    }

    [Fact]
    public async Task RateLimited_GateClosedUntilRetryAfter_ThenLyrics()
    {
        var (r, t, clock) = Make((c, nth) =>
        {
            if (nth == 1 && c.Path == "/api/get") return new ScriptedTransport.Reply.Http(429, new() { ["Retry-After"] = "3" }, Array.Empty<byte>());
            if (c.Path == "/api/search") return Wire.List();
            return Wire.Ok(Wire.Record(17, "Phares sur la mer", "Artiste fictif"));
        });
        var log = new EventLog();
        Assert.True(IsSynced(await Run(r, Track, log: log)));
        Assert.True(log.BusyCount >= 3 && log.Retrying == 1);
        Assert.True(clock.Now >= 3.5 - 0.001);
        Assert.True(t.Calls[1].At >= 3.5 - 0.001);
    }

    [Fact]
    public async Task RateLimitedAgain_Stalled()
    {
        var (r, _, _) = Make((c, n) => new ScriptedTransport.Reply.Http(429, new() { ["Retry-After"] = "1" }, Array.Empty<byte>()));
        Assert.IsType<LookupOutcome.Stalled>(await Run(r, Track));
    }

    [Fact]
    public async Task Offline_NoRequest_ResumesWhenOnline()
    {
        var (r, t, _) = Make((c, n) => Wire.Ok(Wire.Record(18, "Phares sur la mer", "Artiste fictif")));
        r.SetOnline(false);
        var log = new EventLog();
        var task = Run(r, Track, log: log);
        await Task.Delay(100);
        Assert.Empty(t.Calls);
        Assert.Contains(log.Events, e => e is LookupEvent.Offline);
        r.SetOnline(true);
        Assert.True(IsSynced(await task));
        Assert.Single(t.Calls);
    }

    [Fact]
    public async Task Cancellation_DuringWait()
    {
        var clock = new VirtualClock();
        var transport = new ScriptedTransport(clock, (c, n) => Wire.Busy("1"));
        var client = new LrclibClient(transport, "Test/0 (test)", new Uri("http://127.0.0.1:1"));
        var runner = new LookupRunner(client, new RequestGate(3, random: () => 0.5), () => clock.Now, async (s, ct) =>
        {
            try { await Task.Delay(20, ct); } catch (OperationCanceledException) { }
            clock.Advance(s);
        });
        using var cts = new CancellationTokenSource();
        var task = runner.RunAsync(Track, null, _ => { }, cts.Token);
        await Task.Delay(150);
        cts.Cancel();
        Assert.IsType<LookupOutcome.Cancelled>(await task);
    }

    [Fact]
    public void Plan_OrderAndNoDuplicates()
    {
        string[] Names(TrackInfo t) => LookupRunner.Plan(t).Select(s => s.Name).ToArray();
        Assert.Equal(new[] { "get", "search", "search (q)" }, Names(new TrackInfo("Roar", "Katy Perry")));
        var full = Names(new TrackInfo("Dark Horse (feat. Juicy J)", "Katy Perry, Juicy J"));
        Assert.Equal(new[] { "get", "search", "search (1er artiste)", "search (q)" }, full);
        Assert.Equal(new[] { "get", "search", "search (q)", "search (titre court)" }, Names(new TrackInfo("Last Friday Night (T.G.I.F.)", "Katy Perry")));
        Assert.Equal(new[] { "get", "search (q)" }, Names(new TrackInfo("Titre seul", "")));
        Assert.True(full.Length <= 5);
    }
}

public class QueryHelperTests
{
    [Fact]
    public void QueryTitle_Suffixes()
    {
        Assert.Equal("Peaches", TrackMatcher.QueryTitle("Peaches (feat. Daniel Caesar & Giveon)"));
        Assert.Equal("Bohemian Rhapsody", TrackMatcher.QueryTitle("Bohemian Rhapsody - Remastered 2011"));
        Assert.Equal("Alors on danse", TrackMatcher.QueryTitle("Alors on danse - Radio Edit"));
        Assert.Equal("Billie Jean", TrackMatcher.QueryTitle("Billie Jean - Single Version"));
        Assert.Equal("Hey Jude", TrackMatcher.QueryTitle("Hey Jude - 2015 Remaster"));
        Assert.Equal("Don't Stop Believin'", TrackMatcher.QueryTitle("Don't Stop Believin'"));
        Assert.Equal("La Vie en rose", TrackMatcher.QueryTitle("La Vie en rose (Remastered)"));
        Assert.Equal("Où est l’amour ?", TrackMatcher.QueryTitle("Où est l’amour ? feat. Quelqu'un"));
        Assert.Equal("Horloge (Live)", TrackMatcher.QueryTitle("Horloge (Live)"));
    }

    [Fact]
    public void ShortAndArtists()
    {
        Assert.Equal("Last Friday Night", TrackMatcher.ShortQueryTitle("Last Friday Night (T.G.I.F.)"));
        Assert.Equal("Titre", TrackMatcher.ShortQueryTitle("Titre - From \"Un film\""));
        Assert.Equal("Mark Ronson", TrackMatcher.PrimaryArtist("Mark Ronson feat. Bruno Mars"));
        Assert.Equal("Duo fictif", TrackMatcher.PrimaryArtist("Duo fictif & Chanteuse fictive"));
        Assert.Equal("Katy Perry", TrackMatcher.PrimaryArtist("Katy Perry"));
        Assert.Equal("Theory of a Deadman", TrackMatcher.WithoutThe("Theory of a Deadman"));
        Assert.Equal(TrackMatcher.TitleKey("Éléphant d'été"), TrackMatcher.TitleKey("Elephant d'ete"));
        Assert.True(TrackMatcher.ArtistMatches("Édith Piaf", new TrackInfo("X", "Edith Piaf")));
        Assert.True(TrackMatcher.ArtistMatches("Justin Bieber", new TrackInfo("X", "Justin Bieber, Daniel Caesar, Giveon")));
        Assert.False(TrackMatcher.ArtistMatches("Quelqu'un d'autre", new TrackInfo("X", "The Black Eyed Peas")));
        Assert.False(TrackMatcher.ArtistMatches("Black Eyed Peas | Official Video", new TrackInfo("X", "The Black Eyed Peas")));
    }

    [Fact]
    public void TitleCountedOnceForBreaker_EvenAcrossAttempts()
    {
        var g = new RequestGate(titlesBeforeBreaker: 3, random: () => 0.5);
        g.BeginTitle();
        var now = 0.0;
        for (var a = 0; a < 3; a++)
        {
            g.BeginAttempt();
            for (var k = 0; k < 3; k++) { g.RequestStarted(now); now += 1; g.RequestFinished(now, new RequestGate.Outcome.ServerError(503, 1)); now += 1; }
        }
        Assert.True(g.FailedTitlesInARow == 1 && g.ClosedUntil is null);
    }
}
