using System.Reflection;
using System.Text.Json;

namespace LyraLyrics.Core.Tests;

using E = DisplayState.Event;
using S = DisplayState.Screen;

public class DisplayStateTests
{
    private static DisplayState R(DisplayState s, DisplayState.Event e) => DisplayState.Reduce(s, e);

    [Fact]
    public void Nothing_Initial_And_Stop()
    {
        Assert.IsType<S.Nothing>(DisplayState.Initial.Current);
        Assert.Equal("Rien en lecture", DisplayState.Initial.StateText!.Value.Title);
        Assert.Equal("Aucune lecture", DisplayState.Initial.BarTitleWhenIdle);
        var s = R(R(DisplayState.Initial, new E.TrackChanged()), new E.Stopped());
        Assert.IsType<S.Nothing>(s.Current);
        Assert.False(s.HasTrack);
    }

    [Fact]
    public void Searching_Hint_ThenResult()
    {
        var s = R(DisplayState.Initial, new E.TrackChanged());
        Assert.Equal(new S.Searching(false), s.Current);
        s = R(s, new E.SearchHintDue());
        Assert.Equal(new S.Searching(true), s.Current);
        Assert.IsType<S.SyncedScreen>(R(s, new E.LyricsSynced()).Current);
    }

    [Fact]
    public void Synced_Unsynced_Instrumental_Unavailable_AndExitOnNewTrack()
    {
        var s = R(DisplayState.Initial, new E.TrackChanged());
        Assert.IsType<S.Unsynced>(R(s, new E.LyricsUnsynced()).Current);
        Assert.IsType<S.InstrumentalScreen>(R(s, new E.Instrumental()).Current);
        Assert.IsType<S.Unavailable>(R(s, new E.NotFound()).Current);
        Assert.IsType<S.Unavailable>(R(s, new E.BudgetExhausted()).Current);
        Assert.Equal(new S.Searching(false), R(R(s, new E.LyricsSynced()), new E.TrackChanged()).Current);
        Assert.IsType<S.Nothing>(R(DisplayState.Initial, new E.LyricsSynced()).Current);    // sans titre, rien
    }

    [Fact]
    public void Pause_FlagKeepsScreen_ResumeClears()
    {
        var s = R(R(DisplayState.Initial, new E.TrackChanged()), new E.LyricsSynced());
        var p = R(s, new E.Paused());
        Assert.True(p.Paused);
        Assert.IsType<S.SyncedScreen>(p.Current);
        Assert.False(R(p, new E.Resumed()).Paused);
        Assert.False(R(DisplayState.Initial, new E.Paused()).Paused);
    }

    [Fact]
    public void Busy_Countdown_WaitEnded_Stalled_NeverUnavailable()
    {
        var s = R(DisplayState.Initial, new E.TrackChanged());
        s = R(s, new E.ServiceBusy(5));
        Assert.Equal("Nouvel essai dans 5 s.", s.StateText!.Value.Body);
        s = R(s, new E.BusyCountdown(2.2));
        Assert.Equal("Nouvel essai dans 3 s.", s.StateText!.Value.Body);
        Assert.Equal(new S.Searching(false), R(s, new E.WaitEnded()).Current);
        s = R(s, new E.ServiceStalled());
        Assert.Equal(new S.Busy(0), s.Current);
        Assert.Equal("Service de paroles occupé", s.StateText!.Value.Title);
        Assert.Contains("ne répond pas", s.StateText!.Value.Body);
        var o = R(R(DisplayState.Initial, new E.TrackChanged()), new E.WentOffline());
        Assert.IsType<S.Offline>(R(o, new E.ServiceStalled()).Current);
        Assert.IsType<S.Nothing>(R(DisplayState.Initial, new E.ServiceStalled()).Current);
    }

    [Fact]
    public void Offline_ThenBackOnline_ResumesSearch()
    {
        var s = R(R(DisplayState.Initial, new E.TrackChanged()), new E.WentOffline());
        Assert.Equal("Hors connexion", s.StateText!.Value.Title);
        Assert.Equal(new S.Searching(false), R(s, new E.BackOnline()).Current);
        Assert.IsType<S.Offline>(R(s, new E.TrackChanged()).Current);   // on attend le réseau pour ce titre
    }

    [Fact]
    public void WindowsTexts_NoAppleMusicWording()
    {
        foreach (var screen in new S[] { new S.Nothing(), new S.Unavailable(), new S.Busy(3), new S.Busy(0), new S.Offline(), new S.PermissionNeeded(false), new S.Unreadable() })
        {
            var t = new DisplayState(screen).StateText!.Value;
            Assert.DoesNotContain("Apple", t.Title + t.Body);
            Assert.DoesNotContain("Musique", t.Title + t.Body);
        }
    }
}

public class CacheIndexTests
{
    private static Lyrics L(string t) => Lyrics.Plain(t);

    [Fact]
    public void Cache_TwoEntries_OldestLeaves_FetchRefreshes_Clear()
    {
        var c = new LyricsCache();
        c.Store(L("a"), "a"); c.Store(L("b"), "b");
        Assert.Equal(new[] { "a", "b" }, c.Keys);
        Assert.NotNull(c.Fetch("a"));
        Assert.Equal(new[] { "b", "a" }, c.Keys);
        c.Store(L("c"), "c");
        Assert.Equal(new[] { "a", "c" }, c.Keys);
        Assert.Null(c.Peek("b"));
        c.Remove("a"); Assert.Equal(1, c.Count);
        c.Clear(); Assert.Equal(0, c.Count);
    }

    [Fact]
    public void Index_HashedKey_24h_500Entries_Remove()
    {
        var t = new TrackInfo("Phares sur la mer - Remastered 2011", "Artiste fictif", Duration: 119.6);
        var same = new TrackInfo("Phares sur la mer", "Artiste Fictif", Duration: 120.2);
        Func<string, string> hasher = m => "h:" + m.GetHashCode();
        Assert.Equal(LookupIndex.KeyFor(t, hasher), LookupIndex.KeyFor(same, hasher));
        var now = new DateTimeOffset(2026, 10, 27, 20, 0, 0, TimeSpan.Zero);
        var idx = new LookupIndex();
        idx.Record("k1", new LookupIndex.Outcome.Found(42), now);
        idx.Record("k2", new LookupIndex.Outcome.NotFound(), now);
        Assert.Equal(new LookupIndex.Outcome.Found(42), idx.Lookup("k1", now.AddHours(23)));
        Assert.Equal(new LookupIndex.Outcome.NotFound(), idx.Lookup("k2", now.AddHours(1)));
        Assert.Null(idx.Lookup("k1", now.AddHours(25)));
        Assert.Equal(0, idx.Count);
        for (var i = 0; i < 520; i++) idx.Record($"k{i}", new LookupIndex.Outcome.NotFound(), now.AddSeconds(i));
        Assert.Equal(LookupIndex.MaxEntries, idx.Count);
        idx.Remove("k519"); Assert.Equal(LookupIndex.MaxEntries - 1, idx.Count);
    }

    [Fact]
    public void Index_DiskRoundTrip_FileHasNoTitleNorArtist()
    {
        var dir = Path.Combine(Path.GetTempPath(), "lyra-core-tests-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(dir, LookupIndex.FileName);
        try
        {
            var t = new TrackInfo("Titre-canari-A9", "Artiste-canari-B7", Duration: 100);
            var key = LookupIndex.KeyFor(t, LyricsService.SaltedHasher("sel"));
            var idx = new LookupIndex();
            idx.Record(key, new LookupIndex.Outcome.Found(7), DateTimeOffset.UtcNow);
            idx.Save(path);
            var text = File.ReadAllText(path);
            Assert.DoesNotContain("canari", text);
            Assert.Equal(64, key.Length);
            var loaded = LookupIndex.Load(path);
            Assert.Equal(new LookupIndex.Outcome.Found(7), loaded.Lookup(key, DateTimeOffset.UtcNow));
            Assert.Empty(LookupIndex.Load(Path.Combine(dir, "absent.json")).Entries);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void Privacy_LyricsAndRecordTypes_HaveNoSerializationSurface()
    {
        // D2 : les types qui portent du texte de paroles ne sont ni [Serializable], ni [DataContract], ni [JsonConstructor]…
        foreach (var type in new[] { typeof(Lyrics), typeof(LrclibRecord), typeof(LyricLine) })
        {
            Assert.DoesNotContain(type.GetCustomAttributes(), a => a.GetType().Namespace is "System.Runtime.Serialization" or "System.Text.Json.Serialization");
            Assert.DoesNotContain(type.GetProperties().SelectMany(p => p.GetCustomAttributes()), a => a.GetType().Namespace is "System.Text.Json.Serialization");
        }
        // L'index disque ne contient aucun champ texte libre : clé hachée, identifiant, date.
        var fields = typeof(LookupEntry).GetProperties().Select(p => p.Name).OrderBy(n => n).ToArray();
        Assert.Equal(new[] { "Key", "LrclibId", "StoredAt" }, fields);
    }

    [Fact]
    public void AppIdentity_Token_And_UserAgent_AreAscii()
    {
        Assert.Equal("LyraLyrics", AppIdentity.UserAgentToken);
        Assert.Equal("LyraLyrics/1.3.1 (+https://github.com/MalikChopa/lyra-lyrics)", AppIdentity.UserAgent);
        Assert.All(AppIdentity.UserAgent, ch => Assert.True(ch < 128));
        Assert.Equal("EleveEte", AppIdentity.Token("Élève été"));
    }
}

public class SettingsTests
{
    [Fact]
    public void Defaults_MatchMac()
    {
        var s = new Settings();
        Assert.Equal(BackgroundStyle.Glass, s.Style);
        Assert.Equal(26, s.Size); Assert.Equal(38, s.BackgroundOpacity);
        Assert.Equal(3, s.LineCountValue); Assert.True(s.ArtworkColors);
        Assert.Equal(FontTheme.Classic, s.Theme);
        Assert.Equal("Ctrl+Alt+Maj+L", s.HotKey.Display);
        Assert.False(s.SystemBackdrop);
    }

    [Fact]
    public void RoundTrip_AndTolerantDecoding()
    {
        var s = new Settings { Style = BackgroundStyle.Clear, Size = 30, ClickThrough = true, WindowWidth = 500, WindowHeight = 220, Position = new WindowPosition(10, 20), IndexSalt = "abc", SystemBackdrop = true };
        s.Apply(FontTheme.Neon);
        var (back, outcome) = Settings.Decode(s.Encode());
        Assert.Equal(Settings.DecodeOutcome.Ok, outcome);
        Assert.Equal(BackgroundStyle.Clear, back.Style); Assert.Equal(30, back.Size); Assert.True(back.ClickThrough);
        Assert.Equal(500, back.WindowWidth); Assert.Equal(new WindowPosition(10, 20), back.Position); Assert.Equal("abc", back.IndexSalt);
        Assert.Equal(FontTheme.Neon, back.Theme); Assert.True(back.Glow); Assert.True(back.SystemBackdrop);
        var (tolerant, o2) = Settings.Decode("{\"size\": 999, \"style\": \"nimporte\", \"lineCount\": 4, \"backgroundOpacity\": -5, \"hotKey\": {\"modifiers\": 4, \"key\": 76, \"label\": \"L\"}}"u8.ToArray());
        Assert.Equal(Settings.DecodeOutcome.Ok, o2);
        Assert.Equal(44, tolerant.Size); Assert.Equal(BackgroundStyle.Glass, tolerant.Style); Assert.Equal(5, tolerant.LineCountValue);
        Assert.Equal(0, tolerant.BackgroundOpacity);
        Assert.Equal(HotKeyCombo.Default, tolerant.HotKey);                 // Maj seul invalide → défaut
        Assert.Equal(Settings.DecodeOutcome.Corrupt, Settings.Decode("{pas du json"u8.ToArray()).Outcome);
        Assert.Equal(Settings.DecodeOutcome.Missing, Settings.Decode(null).Outcome);
        Assert.Equal(Settings.DecodeOutcome.NewerVersion, Settings.Decode("{\"version\": 9}"u8.ToArray()).Outcome);
    }

    [Fact]
    public void EncodedSettings_HaveNoLyricsFields()
    {
        var json = System.Text.Encoding.UTF8.GetString(new Settings().Encode());
        Assert.DoesNotContain("lyric", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("title", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Themes_And_Styles_And_LineCount_And_Window()
    {
        Assert.Equal(BackgroundStyle.Glass, BackgroundStyle.Solid.Next());
        Assert.Equal(BackgroundStyle.Clear, BackgroundStyle.Glass.Next());
        Assert.Equal(BackgroundStyle.Solid, BackgroundStyle.Clear.Next());
        var s = new Settings { Font = LyricFont.Mono };
        Assert.Equal(FontTheme.Custom, s.Theme);
        s.Apply(FontTheme.Minimal);
        Assert.Equal(LyricWeight.Light, s.FontWeight); Assert.Equal(0.72, s.NeighbourRatio);
        Assert.Equal(1, LineCount.Clamped(0)); Assert.Equal(3, LineCount.Clamped(2)); Assert.Equal(5, LineCount.Clamped(4)); Assert.Equal(5, LineCount.Clamped(9));
        var tiny = new Settings { WindowWidth = 10, WindowHeight = 10 };
        tiny.Clamp();
        Assert.Equal(LyricsMetrics.MinResizeWidth, tiny.WindowWidth); Assert.Equal(LyricsMetrics.MinResizeHeight, tiny.WindowHeight);
        var half = new Settings { WindowWidth = 400 };
        half.Clamp();
        Assert.Null(half.WindowWidth);
    }

    [Fact]
    public void HotKey_Validation()
    {
        Assert.True(HotKeyCombo.Default.IsValid);
        Assert.False(new HotKeyCombo(HotKeyCombo.ModShift, 0x4C, "L").IsValid);
        Assert.False(new HotKeyCombo(0, 0x4C, "L").IsValid);
        Assert.False(new HotKeyCombo(HotKeyCombo.ModControl, 0, "").IsValid);
        Assert.Equal("Ctrl+Alt+Maj+L", HotKeyCombo.Default.Display);
        Assert.Equal("Ctrl+Win+7", new HotKeyCombo(HotKeyCombo.ModWin | HotKeyCombo.ModControl, 0x37, "7").Display);
    }
}

public class PaletteAndFitterTests
{
    private static byte[] Solid(int r, int g, int b, int n = 48 * 48)
    {
        var a = new byte[n * 4];
        for (var i = 0; i < n; i++) { a[i * 4] = (byte)r; a[i * 4 + 1] = (byte)g; a[i * 4 + 2] = (byte)b; a[i * 4 + 3] = 255; }
        return a;
    }

    [Theory]
    [InlineData(200, 30, 30)]
    [InlineData(30, 160, 60)]
    [InlineData(250, 250, 250)]
    [InlineData(5, 5, 5)]
    [InlineData(120, 120, 120)]
    [InlineData(250, 230, 20)]
    public void Palette_AccentAlwaysReadableOnTint(int r, int g, int b)
    {
        var p = ArtworkPalette.FromRgba(Solid(r, g, b), 48, 48)!;
        Assert.True(p.AccentContrast >= ArtworkPalette.MinContrast, $"contraste {p.AccentContrast}");
        var (_, _, v) = p.Tint.Hsb;
        Assert.True(v <= ArtworkPalette.MaxTintValue + 1e-9);
    }

    [Fact]
    public void Palette_TwoColours_DominantIsTheLargerSaturatedOne_EmptyIsNull()
    {
        var px = new byte[48 * 48 * 4];
        for (var i = 0; i < 48 * 48; i++)
        {
            var red = i % 4 != 0;      // 75 % rouge, 25 % bleu
            px[i * 4] = (byte)(red ? 220 : 20); px[i * 4 + 1] = 20; px[i * 4 + 2] = (byte)(red ? 20 : 220); px[i * 4 + 3] = 255;
        }
        var p = ArtworkPalette.FromRgba(px, 48, 48)!;
        Assert.True(p.Dominant.R > p.Dominant.B);
        Assert.True(p.Secondary.B > p.Secondary.R);
        Assert.Null(ArtworkPalette.FromRgba(new byte[0], 0, 0));
        Assert.Null(ArtworkPalette.FromRgba(new byte[16], 2, 2));        // tout transparent
        Assert.Equal("#ff8000", new Rgb(1, 0.5, 0).Hex);
    }

    [Fact]
    public void LineFitter_ShrinksUntilItFits_And_Grows_With_Window()
    {
        // mesure bouchon : hauteur = 1,22 × taille × nombre de lignes de retour à la ligne (0,55 × taille par caractère)
        double Measure(string text, double size, double width) => size * 1.22 * Math.Max(1, Math.Ceiling(text.Length * size * 0.55 / width));
        var fitter = new LineFitter(Measure);
        var lines = new[] { "Une ligne assez courte", "Une ligne courante un peu plus longue que les autres", "Fin" };
        var big = fitter.Fit(lines, 26, 900, 400, 0.66);
        Assert.Equal(26, big.CurrentSize);
        Assert.False(big.Shrunk);
        var small = fitter.Fit(lines, 26, 300, 130, 0.66);
        Assert.True(small.CurrentSize < 26 && small.Shrunk);
        Assert.True(small.CurrentSize >= LyricsMetrics.MinCurrentSize);
        var wider = fitter.Fit(lines, 26, 600, 130, 0.66);
        Assert.True(wider.CurrentSize >= small.CurrentSize);
        Assert.Equal(LyricsMetrics.MinCurrentSize, fitter.Fit(lines, 26, 280, 110, 0.66).CurrentSize);
    }
}

public class ServiceCatalogTests
{
    private sealed record Rec(int Id, string Title, string Artist, string Album, double Duration, bool Instrumental, string? Plain, string? Synced);

    private static List<Rec> LoadCatalog()
    {
        using var doc = Fixtures.Json("lrclib/catalog.json");
        string? S(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
        return doc.RootElement.GetProperty("records").EnumerateArray()
            .Select(e => new Rec(e.GetProperty("id").GetInt32(), S(e, "trackName")!, S(e, "artistName")!, S(e, "albumName") ?? "", e.GetProperty("duration").GetDouble(),
                                 e.GetProperty("instrumental").GetBoolean(), S(e, "plainLyrics"), S(e, "syncedLyrics"))).ToList();
    }

    private static Dictionary<string, object?> Wire(Rec r) => new()
    {
        ["id"] = r.Id, ["trackName"] = r.Title, ["artistName"] = r.Artist, ["albumName"] = r.Album, ["duration"] = r.Duration,
        ["instrumental"] = r.Instrumental, ["plainLyrics"] = r.Plain, ["syncedLyrics"] = r.Synced,
    };

    private static ScriptedTransport.Reply FakeServer(List<Rec> catalog, ScriptedTransport.Call c)
    {
        if (c.Path.StartsWith("/api/get/")) { var id = int.Parse(c.Path[9..]); var r = catalog.FirstOrDefault(x => x.Id == id); return r is null ? global::LyraLyrics.Core.Tests.Wire.NotFound : global::LyraLyrics.Core.Tests.Wire.Ok(Wire(r)); }
        if (c.Path == "/api/get")
        {
            var r = catalog.FirstOrDefault(x => x.Title == c.Query["track_name"] && x.Artist == c.Query["artist_name"]);
            return r is null ? global::LyraLyrics.Core.Tests.Wire.NotFound : global::LyraLyrics.Core.Tests.Wire.Ok(Wire(r));
        }
        var q = c.Query.GetValueOrDefault("q");
        var hits = catalog.Where(x => q is not null ? (x.Title + " " + x.Artist).Contains(q, StringComparison.OrdinalIgnoreCase) || q.Contains(x.Title, StringComparison.OrdinalIgnoreCase)
                                                    : x.Title.Equals(c.Query.GetValueOrDefault("track_name"), StringComparison.OrdinalIgnoreCase)).Select(Wire).ToArray();
        return global::LyraLyrics.Core.Tests.Wire.List(hits);
    }

    [Fact]
    public async Task EveryCatalogRecord_IsFound_With_ExpectedKind_ThroughTheService()
    {
        var catalog = LoadCatalog();
        Assert.True(catalog.Count >= 10);
        foreach (var rec in catalog)
        {
            var clock = new VirtualClock();
            var transport = new ScriptedTransport(clock, (c, n) => FakeServer(catalog, c));
            var service = new LyricsService(new LrclibClient(transport, "T/0 (t)", new Uri("http://127.0.0.1:1")), null, LyricsService.SaltedHasher("s"), () => clock.Now, clock.Sleeper);
            var tcs = new TaskCompletionSource<LyricsServiceEvent>();
            await service.LookupAsync(new TrackInfo(rec.Title, rec.Artist, rec.Album, rec.Duration, Player: "fake"), e =>
            {
                if (e is LyricsServiceEvent.Found or LyricsServiceEvent.NotFound or LyricsServiceEvent.Stalled) tcs.TrySetResult(e);
            });
            var done = await Task.WhenAny(tcs.Task, Task.Delay(5000));
            Assert.True(done == tcs.Task, $"délai dépassé pour {rec.Id}");
            var ev = await tcs.Task;
            if (rec.Plain is null && rec.Synced is null && !rec.Instrumental) { Assert.IsType<LyricsServiceEvent.NotFound>(ev); continue; }
            var found = Assert.IsType<LyricsServiceEvent.Found>(ev);
            Assert.Equal(rec.Id, found.Lyrics.LrclibId);
            if (rec.Instrumental) Assert.Equal(LyricsKind.Instrumental, found.Lyrics.Kind);
            else if (rec.Synced is not null) Assert.True(found.Lyrics.IsSynced, $"id {rec.Id}");
            else Assert.Equal(LyricsKind.Plain, found.Lyrics.Kind);
        }
    }

    [Fact]
    public async Task Service_CacheHit_IndexWritten_NoLyricsInIndexFile_ClearAllRemovesIt()
    {
        var catalog = LoadCatalog();
        var dir = Path.Combine(Path.GetTempPath(), "lyra-core-svc-" + Guid.NewGuid().ToString("N"));
        var indexPath = Path.Combine(dir, LookupIndex.FileName);
        try
        {
            var clock = new VirtualClock();
            var transport = new ScriptedTransport(clock, (c, n) => FakeServer(catalog, c));
            var service = new LyricsService(new LrclibClient(transport, "T/0 (t)", new Uri("http://127.0.0.1:1")), indexPath, LyricsService.SaltedHasher("s"), () => clock.Now, clock.Sleeper);
            var rec = catalog[0];
            var track = new TrackInfo(rec.Title, rec.Artist, rec.Album, rec.Duration, Player: "fake");
            async Task<LyricsServiceEvent> Once()
            {
                var tcs = new TaskCompletionSource<LyricsServiceEvent>();
                await service.LookupAsync(track, e => { if (e is LyricsServiceEvent.Found or LyricsServiceEvent.NotFound) tcs.TrySetResult(e); });
                return await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
            }
            Assert.False(((LyricsServiceEvent.Found)await Once()).Cached);
            Assert.True(((LyricsServiceEvent.Found)await Once()).Cached);
            Assert.Single(transport.Calls);
            Assert.Equal(1, service.CacheCount); Assert.Equal(1, service.IndexCount);
            var fileText = File.ReadAllText(indexPath);
            Assert.DoesNotContain(rec.Title, fileText);
            Assert.DoesNotContain("phares", fileText, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("glissent", fileText);
            service.ClearAll();
            Assert.Equal(0, service.CacheCount); Assert.Equal(0, service.IndexCount);
            Assert.Equal("[]", File.ReadAllText(indexPath).Trim());
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Service_429_ThenLyrics_ThroughVirtualClock()
    {
        var catalog = LoadCatalog();
        var rec = catalog.First(r => r.Title == "Occupé trois secondes");
        var clock = new VirtualClock();
        var first = true;
        var transport = new ScriptedTransport(clock, (c, n) =>
        {
            if (first) { first = false; return new ScriptedTransport.Reply.Http(429, new() { ["Retry-After"] = "3" }, Array.Empty<byte>()); }
            return FakeServer(catalog, c);
        });
        var service = new LyricsService(new LrclibClient(transport, "T/0 (t)", new Uri("http://127.0.0.1:1")), null, LyricsService.SaltedHasher("s"), () => clock.Now, clock.Sleeper);
        var events = new List<LyricsServiceEvent>();
        var tcs = new TaskCompletionSource<bool>();
        await service.LookupAsync(new TrackInfo(rec.Title, rec.Artist, rec.Album, rec.Duration, Player: "fake"), e =>
        {
            lock (events) events.Add(e);
            if (e is LyricsServiceEvent.Found) tcs.TrySetResult(true);
        });
        await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        lock (events) { Assert.Contains(events, e => e is LyricsServiceEvent.Busy); Assert.DoesNotContain(events, e => e is LyricsServiceEvent.NotFound); }
    }
}
