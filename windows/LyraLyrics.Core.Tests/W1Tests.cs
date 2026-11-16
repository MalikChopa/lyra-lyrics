using System.Text.RegularExpressions;

namespace LyraLyrics.Core.Tests;

/// <summary>Tests du jalon W1 : logique extraite pour être exécutable sur le Mac.</summary>
public class SessionBinderTests
{
    private sealed class FakeSession { public string Id = "Spotify.exe"; public int Subs; }

    private sealed class Rig
    {
        public List<FakeSession> Sessions = new();
        public List<string> Log = new();
        public int Attached, Detached;
        public SessionBinder<FakeSession> Binder;
        public Rig() => Binder = new(() => Sessions.FirstOrDefault(s => s.Id.StartsWith("Spotify")), s => s.Id,
            s => { s.Subs++; Attached++; }, s => { s.Subs--; Detached++; }, Log.Add);
    }

    [Fact]
    public async Task Poll_AttachesSessionThatAppearedWithoutEvent_ThenRunsRefresh()
    {
        var r = new Rig();
        var refreshed = 0;
        Assert.False(await r.Binder.PollAsync(() => { refreshed++; return Task.CompletedTask; }));      // rien encore
        Assert.Null(r.Binder.Current); Assert.Equal(0, refreshed);
        var s = new FakeSession(); r.Sessions.Add(s);                                                  // Spotify apparaît, aucun événement
        Assert.True(await r.Binder.PollAsync(() => { refreshed++; return Task.CompletedTask; }));
        Assert.Same(s, r.Binder.Current);
        Assert.Equal(1, s.Subs); Assert.Equal(1, refreshed);
        Assert.Contains(r.Log, l => l.Contains("sondage"));
    }

    [Fact]
    public async Task Poll_DoesNothing_WhenASessionIsAlreadyFollowed()
    {
        var r = new Rig(); r.Sessions.Add(new FakeSession());
        Assert.True(r.Binder.Rebind(false));
        var refreshed = 0;
        Assert.False(await r.Binder.PollAsync(() => { refreshed++; return Task.CompletedTask; }));
        Assert.Equal(0, refreshed); Assert.Equal(1, r.Attached);
    }

    [Fact]
    public void Rebind_KeepsSameId_UnlessForced_AndUnsubscribesTheOldOne()
    {
        var r = new Rig(); var a = new FakeSession(); r.Sessions.Add(a);
        Assert.True(r.Binder.Rebind(false));
        var b = new FakeSession(); r.Sessions[0] = b;                      // nouvel objet, même identifiant (Spotify relancé)
        Assert.False(r.Binder.Rebind(false)); Assert.Same(a, r.Binder.Current);
        Assert.True(r.Binder.Rebind(true)); Assert.Same(b, r.Binder.Current);
        Assert.Equal(0, a.Subs); Assert.Equal(1, b.Subs);                  // l'ancienne est désabonnée
    }

    [Fact]
    public void Rebind_ToNone_DetachesAndLogs()
    {
        var r = new Rig(); var a = new FakeSession(); r.Sessions.Add(a);
        r.Binder.Rebind(false); r.Sessions.Clear();
        Assert.True(r.Binder.Rebind(true));
        Assert.Null(r.Binder.Current); Assert.Equal(0, a.Subs);
        Assert.Contains(r.Log, l => l.Contains("aucune session"));
        r.Binder.Detach(); Assert.Equal(1, r.Detached);                    // déjà détachée : sans effet
    }
}

public class TrackGuardTests
{
    [Fact]
    public void ImplausiblePosition_Waits_ThenStartsForced_AfterTheBound()
    {
        Assert.Equal(3.0, TrackGuard.MaxWaitSeconds);
        var g = new TrackGuard();
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t1", false, 100.0));
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t1", false, 101.0));
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t1", false, 102.9));
        Assert.Equal(TrackGuard.Verdict.StartForced, g.Decide("t1", false, 103.0));      // 3 s écoulées : on charge quand même
    }

    [Fact]
    public void PlausiblePosition_StartsAtOnce_AndClearsTheWait()
    {
        var g = new TrackGuard();
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t1", false, 10.0));
        Assert.Equal(TrackGuard.Verdict.Start, g.Decide("t1", true, 11.0));
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t1", false, 50.0));              // nouvelle attente : l'horloge repart
    }

    [Fact]
    public void ANewerTrack_RestartsTheClock()
    {
        var g = new TrackGuard();
        g.Decide("t1", false, 0); g.Decide("t1", false, 2);
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t2", false, 2.5));
        Assert.Equal(TrackGuard.Verdict.Wait, g.Decide("t2", false, 5.0));
        Assert.Equal(TrackGuard.Verdict.StartForced, g.Decide("t2", false, 5.5));
    }
}

public class IdentityAndColorTests
{
    private static string PropsPath()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null) { var p = Path.Combine(dir.FullName, "Directory.Build.props"); if (File.Exists(p)) return p; dir = dir.Parent; }
        throw new FileNotFoundException("Directory.Build.props");
    }

    [Fact]
    public void Version_IsReadFromTheSingleSource_DirectoryBuildProps()
    {
        var m = Regex.Match(File.ReadAllText(PropsPath()), @"<Version>([^<]+)</Version>");
        Assert.True(m.Success);
        Assert.Equal(m.Groups[1].Value, AppIdentity.Version);
        Assert.Contains("LyraLyrics/" + AppIdentity.Version, AppIdentity.UserAgent);
    }

    [Fact]
    public void TextColor_IsAlwaysTheChosenOne_ArtworkOnlyTintsTheBackground()
    {
        Assert.Equal("#FFD60A", LineColorRule.TextHex("#FFD60A", true, "#123456"));
        Assert.Equal("#FFD60A", LineColorRule.TextHex("#FFD60A", false, null));
    }
}

public class ScrubAndDiagnosticTests
{
    private static readonly string[] FakeLog =
    {
        "2026-11-16 20:00:01.000 [app] démarrage LyraLyrics/1.0.1 · Windows 10.0.22631",
        "2026-11-16 20:00:02.000 [smtc] sessions=[Spotify.exe]",
        "2026-11-16 20:00:03.000 [lookup] lookup=index resultat=id 424242",
        "2026-11-16 20:00:04.000 [lookup] lookup=livre resultat=synced id=424242 provenance=search, id 424242, score 17",
        "2026-11-16 20:00:05.000 [model] service -> écran Paroles (search, id 424242, score 17)",
        "2026-11-16 20:00:06.000 [x] GET /api/get/424242 ok",
        "2026-11-16 20:00:07.000 [x] titre=Chanson Fictive Du Canari artiste=Groupe Imaginaire",
        "2026-11-16 20:00:08.000 [erreur] C:\\Users\\jean.dupont\\AppData\\Roaming\\LyraLyrics\\settings.json illisible",
        "2026-11-16 20:00:09.000 [x] la ligne Chanson Fictive Du Canari est affichée",
    };

    [Fact]
    public void Report_ContainsNoTitleArtistLyricsIdOrUserName()
    {
        var facts = new[] { new KeyValuePair<string, string>("Windows", "10.0.22631"), new("Fenêtre", "x=10 y=20 w=500 h=190") };
        var text = DiagnosticReport.Build("Lyra Lyrics", "1.0.1", facts, FakeLog, new[] { "Chanson Fictive Du Canari", "Groupe Imaginaire" });
        Assert.DoesNotContain("424242", text);
        Assert.DoesNotContain("Chanson Fictive", text);
        Assert.DoesNotContain("Groupe Imaginaire", text);
        Assert.DoesNotContain("jean.dupont", text);
        Assert.Contains("Spotify.exe", text);
        Assert.Contains("Windows : 10.0.22631", text);
        Assert.Contains("%USERPROFILE%", text);
    }

    [Fact]
    public void Report_KeepsOnlyTheLast200LogLines()
    {
        var lines = Enumerable.Range(1, 500).Select(i => $"ligne-{i:000}").ToList();
        var text = DiagnosticReport.Build("A", "1", Array.Empty<KeyValuePair<string, string>>(), lines);
        Assert.DoesNotContain("ligne-300", text);
        Assert.Contains("ligne-301", text); Assert.Contains("ligne-500", text);
        Assert.Equal(200, Regex.Matches(text, @"ligne-\d{3}").Count);
    }

    [Fact]
    public void DescribeException_KeepsTypeMessageStackAndInner()
    {
        Exception ex;
        try { try { throw new InvalidOperationException("interne"); } catch (Exception inner) { throw new ArgumentException("externe", inner); } }
        catch (Exception e) { ex = e; }
        var t = DiagnosticReport.DescribeException(ex);
        Assert.Contains("System.ArgumentException", t); Assert.Contains("externe", t);
        Assert.Contains("System.InvalidOperationException", t); Assert.Contains("interne", t);
        Assert.Contains("HResult=0x", t); Assert.Contains("DescribeException_KeepsTypeMessageStackAndInner", t);
    }
}

public class RollingLogTests
{
    private static string Temp() => Path.Combine(Path.GetTempPath(), "lyra-log-" + Guid.NewGuid().ToString("N"));

    [Fact]
    public void SurvivesATransientError_AndReportsLostLines()
    {
        var dir = Temp(); Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, "lyra.log");
        try
        {
            using var log = new RollingLog(path);
            log.Write("avant");
            log.Dispose();
            Directory.CreateDirectory(path + ".bloc");
            File.Delete(path); Directory.CreateDirectory(path);          // un DOSSIER à la place du fichier : l'ouverture échoue
            log.Write("perdue 1"); log.Write("perdue 2");
            Assert.Equal(2, log.TotalFailures);
            Directory.Delete(path);                                       // l'erreur passe
            log.Write("après");
            var text = File.ReadAllText(path);
            Assert.Contains("après", text);
            Assert.Contains("2 ligne(s) perdue(s)", text);
            Assert.DoesNotContain("perdue 1", text);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public void Rotates_AtTheLimit_AndReadTailSpansBothFiles()
    {
        var dir = Temp();
        try
        {
            var path = Path.Combine(dir, "lyra.log");
            using var log = new RollingLog(path, maxBytes: 200);
            for (var i = 0; i < 30; i++) log.Write($"ligne {i:00}");
            Assert.True(File.Exists(path + ".1"));
            var tail = log.ReadTail(5);
            Assert.Equal(5, tail.Count);
            Assert.Equal("ligne 29", tail[^1]);
        }
        finally { Directory.Delete(dir, true); }
    }
}

public class ServiceRobustnessTests
{
    [Fact]
    public async Task InternalException_EndsInAVisibleStalledState_NotAnEndlessSearch()
    {
        var clock = new VirtualClock();
        var transport = new ScriptedTransport(clock, (c, n) => Wire.NotFound);
        var logs = new List<Dictionary<string, string>>();
        Func<string, string> boom = _ => throw new InvalidOperationException("secret Titre Fictif");
        var service = new LyricsService(new LrclibClient(transport, "T/0 (t)", new Uri("http://127.0.0.1:1")), null, boom, () => clock.Now, clock.Sleeper, log: logs.Add);
        var tcs = new TaskCompletionSource<LyricsServiceEvent>();
        await service.LookupAsync(new TrackInfo("Titre Fictif", "Artiste Fictif", null, 200, Player: "fake"), e => { if (e is not LyricsServiceEvent.Searching) tcs.TrySetResult(e); });
        var ev = await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var stalled = Assert.IsType<LyricsServiceEvent.Stalled>(ev);
        Assert.Equal("erreur interne", stalled.Reason);
        var line = string.Join(" ", logs.Select(l => string.Join(" ", l.Select(kv => kv.Key + "=" + kv.Value))));
        Assert.Contains("erreur-interne", line);
        Assert.Contains("InvalidOperationException", line);
        Assert.DoesNotContain("Titre Fictif", line);            // le message de l'exception n'est jamais journalisé
        // et l'état affiché sort bien de « Recherche » (bouton Réessayer)
        var state = DisplayState.Reduce(DisplayState.Reduce(DisplayState.Initial, new DisplayState.Event.TrackChanged()), new DisplayState.Event.ServiceStalled());
        Assert.IsNotType<DisplayState.Screen.Searching>(state.Current);
    }

    [Fact]
    public async Task ServiceLog_NeverContainsLrclibIdOrProvenance_OnAFoundLookup()
    {
        var clock = new VirtualClock();
        var rec = Wire.Record(987654, "Titre Fictif", "Artiste Fictif", duration: 200);
        var transport = new ScriptedTransport(clock, (c, n) => c.Path.StartsWith("/api/get/") ? Wire.Ok(rec) : Wire.List(rec));
        var logs = new List<string>();
        var service = new LyricsService(new LrclibClient(transport, "T/0 (t)", new Uri("http://127.0.0.1:1")), null, LyricsService.SaltedHasher("s"), () => clock.Now, clock.Sleeper,
            log: d => { lock (logs) logs.Add(string.Join(" ", d.Select(kv => kv.Key + "=" + kv.Value))); });
        var tcs = new TaskCompletionSource<LyricsServiceEvent>();
        await service.LookupAsync(new TrackInfo("Titre Fictif", "Artiste Fictif", null, 200, Player: "fake"), e => { if (e is LyricsServiceEvent.Found or LyricsServiceEvent.NotFound or LyricsServiceEvent.Stalled) tcs.TrySetResult(e); });
        Assert.IsType<LyricsServiceEvent.Found>(await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5)));
        string all; lock (logs) all = string.Join("\n", logs);
        Assert.Contains("lookup=livre", all);
        Assert.DoesNotContain("987654", all);
        Assert.DoesNotContain("provenance", all, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Titre Fictif", all);
    }
}
