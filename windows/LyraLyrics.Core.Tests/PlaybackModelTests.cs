using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>Faux effets : enregistre ce que le modèle demande au monde extérieur.</summary>
internal sealed class FakeEffects : IPlaybackEffects
{
    public List<(TrackInfo Track, string Identity)> Lookups { get; } = new();
    public List<(TrackInfo Track, string Identity)> Retries { get; } = new();
    public int Cancels { get; private set; }
    public List<bool> Online { get; } = new();
    public List<string> Logs { get; } = new();
    public void StartLookup(TrackInfo track, string identity) => Lookups.Add((track, identity));
    public void RetryLookup(TrackInfo track, string identity) => Retries.Add((track, identity));
    public void CancelLookup() => Cancels++;
    public void SetServiceOnline(bool online) => Online.Add(online);
    public void ClearCache() { }
    public void Log(string zone, string message) => Logs.Add(zone + ": " + message);
}

internal sealed class ModelRig
{
    public double Now;
    public FakeEffects Fx = new();
    public PlaybackModel M;
    public int Changes;
    public ModelRig() { M = new PlaybackModel(() => Now, Fx); M.Changed += () => Changes++; }

    public static TrackInfo Track(string id, double? duration = 200) => new("Titre " + id, "Artiste", null, duration, id, "Spotify");

    public SmtcUpdate Update(string? id, double? pos, PlaybackState state = PlaybackState.Playing, double? duration = 200, bool plausible = true) =>
        new(id is not null, id is null ? null : Track(id, duration), state, pos, duration, Now, plausible);

    public void Send(string? id, double? pos, PlaybackState state = PlaybackState.Playing, double? duration = 200, bool plausible = true) =>
        M.OnUpdate(Update(id, pos, state, duration, plausible));

    public void At(double t) { Now = t; }
    public void TickAt(double t) { Now = t; M.Tick(); }

    public static Lyrics Synced() => Lyrics.Synced(new LyricLine[] { new(10, "un"), new(20, "deux"), new(30, "trois"), new(40, "quatre") });
    public void Found(string id, Lyrics l, bool cached = false) => M.OnServiceEvent(new LyricsServiceEvent.Found(l, cached), Track(id).Identity);
    public void Svc(string id, LyricsServiceEvent e) => M.OnServiceEvent(e, Track(id).Identity);
}

/// <summary>Constat 13 : scénarios du modèle de lecture PUR (aucune interface, aucun minuteur) ; fixtures partagées + cas propres à Windows.</summary>
public class PlaybackModelTests
{
    // ---- Fixture partagée avec le pilote Swift (Fixtures/golden/playback.json)

    [Fact]
    public void SharedScenarios_PlaybackJson()
    {
        using var doc = Fixtures.Json("golden/playback.json");
        var root = doc.RootElement;
        var sets = root.GetProperty("lineSets");
        var failures = new List<string>();
        var steps = 0;
        foreach (var sc in root.GetProperty("scenarios").EnumerateArray())
        {
            var rig = new ModelRig();
            string? current = null;
            foreach (var st in sc.GetProperty("steps").EnumerateArray())
            {
                steps++;
                rig.At(st.GetProperty("t").GetDouble());
                var op = st.GetProperty("op").GetString()!;
                switch (op)
                {
                    case "track":
                    {
                        current = st.GetProperty("id").GetString()!;
                        rig.Send(current, Opt(st, "pos"), State(st), Opt(st, "duration"));
                        break;
                    }
                    case "reading": rig.Send(current, Opt(st, "pos"), State(st), 200); break;
                    case "stop": rig.Send(null, null); current = null; break;
                    case "tick": rig.M.Tick(); break;
                    case "offset": rig.M.SetManualOffset(st.GetProperty("value").GetDouble()); break;
                    case "retry": rig.M.RetryLookup(); break;
                    case "net-off": rig.M.SetOnline(false); break;
                    case "net-on": rig.M.SetOnline(true); break;
                    case "service":
                    {
                        var target = st.TryGetProperty("for", out var f) ? f.GetString()! : current ?? "?";
                        var retryIn = st.TryGetProperty("retryIn", out var r) ? r.GetDouble() : 0;
                        LyricsServiceEvent e = st.GetProperty("kind").GetString() switch
                        {
                            "found-synced" => new LyricsServiceEvent.Found(Lyrics.Synced(sets.GetProperty(st.GetProperty("lines").GetString()!).EnumerateArray()
                                .Select(l => new LyricLine(l[0].GetDouble(), l[1].GetString()!)).ToList()), false),
                            "found-plain" => new LyricsServiceEvent.Found(Lyrics.Plain("texte"), false),
                            "found-instrumental" => new LyricsServiceEvent.Found(Lyrics.Instrumental(), false),
                            "busy" => new LyricsServiceEvent.Busy(retryIn, "test"),
                            "offline" => new LyricsServiceEvent.Offline(),
                            "notfound" => new LyricsServiceEvent.NotFound("test"),
                            "stalled" => new LyricsServiceEvent.Stalled("test"),
                            "retrying" => new LyricsServiceEvent.Retrying(),
                            var k => throw new InvalidOperationException("kind " + k),
                        };
                        rig.M.OnServiceEvent(e, ModelRig.Track(target).Identity);
                        break;
                    }
                    default: throw new InvalidOperationException("op " + op);
                }
                foreach (var ex in st.GetProperty("expect").EnumerateObject())
                {
                    var got = Observe(rig.M, ex.Name);
                    var ok = ex.Value.ValueKind switch
                    {
                        JsonValueKind.Number => got is double d && Math.Abs(d - ex.Value.GetDouble()) < 1e-9,
                        JsonValueKind.True or JsonValueKind.False => got is bool b && b == ex.Value.GetBoolean(),
                        _ => got is string s && s == ex.Value.GetString(),
                    };
                    if (!ok) failures.Add($"{sc.GetProperty("name").GetString()} / t={rig.Now} {op}: {ex.Name} = {got}, attendu {ex.Value}");
                }
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures.Take(15)));
        Assert.True(steps >= 100, "fixture lue en entier : " + steps);
    }

    private static double? Opt(JsonElement e, string n) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
    private static PlaybackState State(JsonElement e) => e.GetProperty("state").GetString() switch { "paused" => PlaybackState.Paused, "stopped" => PlaybackState.Stopped, _ => PlaybackState.Playing };

    private static object? Observe(PlaybackModel m, string name) => name switch
    {
        "screen" => m.Display.Current.Name,
        "hint" => m.Display.Current is DisplayState.Screen.Searching s ? s.Hint : null,
        "hasTrack" => m.Display.HasTrack,
        "paused" => m.Display.Paused,
        "index" => (double)m.CurrentIndex,
        "offset" => m.ManualOffset,
        "retryIn" => m.Display.Current is DisplayState.Screen.Busy b ? b.RetryIn : null,
        _ => throw new InvalidOperationException("expect " + name),
    };

    // ---- Cas propres à l'app Windows

    [Fact]
    public void TrackChange_StartsOneLookup_PerTrack_AndStaleResultIsIgnored()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.At(0.2); r.Send("B", 0); r.At(0.4); r.Send("C", 0);
        Assert.Equal(new[] { "Spotify:A", "Spotify:B", "Spotify:C" }, r.Fx.Lookups.Select(l => l.Identity));
        r.Found("A", ModelRig.Synced());
        Assert.IsType<DisplayState.Screen.Searching>(r.M.Display.Current);
        Assert.Null(r.M.Lyrics);
        r.Found("C", ModelRig.Synced());
        Assert.IsType<DisplayState.Screen.SyncedScreen>(r.M.Display.Current);
        Assert.Equal(3, r.M.TrackEpoch);
    }

    [Fact]
    public void ImplausiblePosition_WaitsForNextSnapshot_ThenStarts()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.Found("A", ModelRig.Synced()); r.TickAt(150);
        r.At(150); r.Send("B", 190, duration: 100, plausible: false);          // position de l'ancien titre
        Assert.Equal("Spotify:A", r.M.Track!.Identity);
        Assert.Single(r.Fx.Lookups);
        r.At(151); r.Send("B", 1, duration: 100);
        Assert.Equal("Spotify:B", r.M.Track!.Identity);
        Assert.Equal(2, r.Fx.Lookups.Count);
        Assert.Equal(100, r.Fx.Lookups[1].Track.Duration);
    }

    [Fact]
    public void ImplausiblePosition_ForcedAfterThreeSeconds_PositionUnknown()
    {
        var r = new ModelRig();
        r.Send("A", 0);
        r.At(10); r.Send("B", 500, duration: 100, plausible: false);
        r.At(12); r.Send("B", 500, duration: 100, plausible: false);
        Assert.Equal("Spotify:A", r.M.Track!.Identity);
        r.At(13.1); r.Send("B", 500, duration: 100, plausible: false);
        Assert.Equal("Spotify:B", r.M.Track!.Identity);
        Assert.Contains(r.Fx.Logs, l => l.Contains("garde de piste levée"));
        r.Found("B", ModelRig.Synced());
        Assert.Equal(-1, r.M.CurrentIndex);                                        // la position implausible n'a pas alimenté l'estimateur
        r.TickAt(14);
        Assert.Equal(-1, r.M.CurrentIndex);
        Assert.Equal(0, r.M.Position);
    }

    [Fact]
    public void UnknownDuration_WaitsUpTo600ms_ThenSearchesWithoutIt()
    {
        var r = new ModelRig();
        r.Send("A", 0, duration: null);
        Assert.Empty(r.Fx.Lookups);
        Assert.True(r.M.WantsTimer);
        r.TickAt(0.5); Assert.Empty(r.Fx.Lookups);
        r.TickAt(0.7);
        Assert.Single(r.Fx.Lookups); Assert.Null(r.Fx.Lookups[0].Track.Duration);
    }

    [Fact]
    public void UnknownDuration_ThenSnapshotGivesIt_SearchStartsAtOnceWithIt()
    {
        var r = new ModelRig();
        r.Send("A", 0, duration: null);
        r.At(0.3); r.Send("A", 0.3, duration: 215);
        Assert.Single(r.Fx.Lookups);
        Assert.Equal(215, r.Fx.Lookups[0].Track.Duration);
        r.TickAt(2); Assert.Single(r.Fx.Lookups);
    }

    [Fact]
    public void SearchHint_AppearsAfter1500ms_OnlyWhileSearching()
    {
        var r = new ModelRig();
        r.Send("A", 0);
        r.TickAt(1.4); Assert.False(r.M.SearchHint);
        r.TickAt(1.6); Assert.True(r.M.SearchHint);
        Assert.Equal("Recherche des paroles…", r.M.LineItems(3)[1].Text);
        r.Found("A", ModelRig.Synced());
        r.TickAt(5); Assert.False(r.M.SearchHint);
        Assert.False(r.M.WantsTimer is true && r.M.Display.Current is DisplayState.Screen.Searching);
    }

    [Fact]
    public void HintDoesNotFire_AfterFoundBeforeDeadline()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.At(0.5); r.Found("A", Lyrics.Plain("x"));
        r.TickAt(3);
        Assert.IsType<DisplayState.Screen.Unsynced>(r.M.Display.Current);
    }

    [Fact]
    public void BusyCountdown_ShowsDecreasingSeconds_ThenSearchesAgain()
    {
        var r = new ModelRig();
        r.Send("A", 0);
        foreach (var s in new[] { 30.0, 29.0, 1.2 }) r.Svc("A", new LyricsServiceEvent.Busy(s, "429"));
        Assert.Equal("Nouvel essai dans 2 s.", r.M.Display.StateText!.Value.Body);
        Assert.Equal(1.2, r.M.BusyRetryIn);
        Assert.Equal("Réessayer", r.M.StateActionLabel);
        r.Svc("A", new LyricsServiceEvent.Retrying());
        Assert.False(r.M.SearchHint);
        Assert.IsType<DisplayState.Screen.Searching>(r.M.Display.Current);
        Assert.Null(r.M.StateActionLabel);
    }

    [Fact]
    public void Retry_AsksTheService_WithKnownDuration_AndOnlyFromUnavailableOrBusy()
    {
        var r = new ModelRig();
        r.Send("A", 0, duration: 180);
        r.M.RetryLookup(); Assert.Empty(r.Fx.Retries);                               // en recherche : sans effet
        r.Svc("A", new LyricsServiceEvent.NotFound("x"));
        Assert.Equal("Réessayer", r.M.StateActionLabel);
        r.M.RetryLookup();
        Assert.Single(r.Fx.Retries); Assert.Equal(180, r.Fx.Retries[0].Track.Duration);
        Assert.Equal("nouvel essai demandé", r.M.LastLookup);
        Assert.IsType<DisplayState.Screen.Searching>(r.M.Display.Current);
    }

    [Fact]
    public void Offline_SetsServiceOnline_AndRestoresLyricsInMemory()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.Found("A", ModelRig.Synced());
        r.M.SetOnline(false); Assert.IsType<DisplayState.Screen.SyncedScreen>(r.M.Display.Current);
        r.Svc("A", new LyricsServiceEvent.Offline());
        Assert.Equal("Hors connexion", r.M.Display.StateText!.Value.Title);
        r.M.SetOnline(true);
        Assert.IsType<DisplayState.Screen.SyncedScreen>(r.M.Display.Current);
        Assert.Equal(new[] { false, true }, r.Fx.Online);
    }

    [Fact]
    public void Stop_CancelsTheLookup_AndShowsNothing()
    {
        var r = new ModelRig();
        r.Send("A", 0);
        r.At(2); r.Send(null, null);
        Assert.Equal(1, r.Fx.Cancels);
        Assert.Equal("Rien en lecture", r.M.Display.StateText!.Value.Title);
        Assert.Equal("Aucune lecture", r.M.BarText.Title);
        Assert.False(r.M.Display.HasTrack);
        r.TickAt(5); Assert.False(r.M.SearchHint);                                  // l'échéance de l'indice est annulée
    }

    [Fact]
    public void PauseAndSeek_AreFollowed_ByTheLineIndex()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.Found("A", ModelRig.Synced());
        r.TickAt(25); Assert.Equal(1, r.M.CurrentIndex);
        r.At(25); r.Send("A", 25, PlaybackState.Paused);
        Assert.True(r.M.IsPaused); Assert.Equal("Artiste · En pause", r.M.BarText.Artist);
        r.TickAt(80); Assert.Equal(1, r.M.CurrentIndex); Assert.False(r.M.WantsTimer);
        r.At(80); r.Send("A", 5, PlaybackState.Playing);                              // reprise après un saut en arrière
        Assert.Equal(-1, r.M.CurrentIndex); Assert.True(r.M.WantsTimer);
    }

    [Fact]
    public void HiddenWindow_StopsTimer_AndCatchesUpWhenShown()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.Found("A", ModelRig.Synced());
        Assert.True(r.M.WantsTimer);
        r.M.SetWindowVisible(false); Assert.False(r.M.WantsTimer);
        r.TickAt(35); Assert.Equal(-1, r.M.CurrentIndex);
        r.M.SetWindowVisible(true); Assert.Equal(2, r.M.CurrentIndex);
    }

    [Fact]
    public void Notice_ExpiresOnTick_AndNeedsTimerUntilThen()
    {
        var r = new ModelRig();
        r.M.ShowNotice("Bonjour", 2);
        Assert.Equal("Bonjour", r.M.Notice); Assert.True(r.M.WantsTimer);
        r.TickAt(1.9); Assert.Equal("Bonjour", r.M.Notice);
        r.TickAt(2.1); Assert.Null(r.M.Notice); Assert.False(r.M.WantsTimer);
    }

    [Fact]
    public void Unsynced_ScrollPlan_IsArmedOnce_ReArmedOnlyWhenTrajectoryChanges()
    {
        var r = new ModelRig();
        r.Send("A", 0, duration: 200);
        r.At(1); r.Found("A", Lyrics.Plain("a\nb\nc"));
        var p0 = r.M.UnsyncedScroll;
        Assert.True(p0.Playing); Assert.InRange(p0.Remaining, 198.9, 199.1);
        Assert.False(r.M.WantsTimer);                                                // D1 : aucun minuteur pour le bloc
        for (var t = 2; t <= 60; t++) { r.At(t); r.Send("A", t); }                   // relevés réguliers : même trajectoire
        Assert.Equal(p0.Stamp, r.M.UnsyncedScroll.Stamp);
        r.At(61); r.Send("A", 150);                                                   // saut
        var p1 = r.M.UnsyncedScroll;
        Assert.True(p1.Stamp > p0.Stamp); Assert.InRange(p1.Progress, 0.74, 0.76); Assert.InRange(p1.Remaining, 49.9, 50.1);
        r.At(62); r.Send("A", 151, PlaybackState.Paused);                             // pause : plan figé
        var p2 = r.M.UnsyncedScroll;
        Assert.False(p2.Playing); Assert.True(p2.Stamp > p1.Stamp);
        r.At(70); r.Send("A", 151, PlaybackState.Playing);                            // reprise
        Assert.True(r.M.UnsyncedScroll.Playing);
        var before = r.M.UnsyncedScroll.Stamp;
        r.M.RefreshUnsynced(force: true);                                             // redimensionnement
        Assert.Equal(before + 1, r.M.UnsyncedScroll.Stamp);
    }

    [Fact]
    public void Palette_IsDroppedOnTrackChange_AndIgnoredForOtherTracks()
    {
        var r = new ModelRig();
        var pal = new ArtworkPalette(new Rgb(0.8, 0.2, 0.2), new Rgb(0.2, 0.2, 0.8));
        r.Send("A", 0);
        r.M.SetPalette("Spotify:B", pal); Assert.Null(r.M.Palette);
        r.M.SetPalette("Spotify:A", pal); Assert.NotNull(r.M.Palette);
        r.At(1); r.Send("B", 0); Assert.Null(r.M.Palette);
    }

    [Fact]
    public void Changed_IsRaisedOnlyForVisibleChanges_NotForSilentTicks()
    {
        var r = new ModelRig();
        r.Send("A", 0); r.Found("A", ModelRig.Synced());
        r.TickAt(10); var n = r.Changes;                                              // ligne 0
        r.TickAt(10.1); r.TickAt(10.2); r.TickAt(10.3);
        Assert.Equal(n, r.Changes);
        r.TickAt(19.9); Assert.Equal(n + 1, r.Changes);
    }

    [Fact]
    public void LineItems_ForEachState()
    {
        var r = new ModelRig();
        Assert.All(r.M.LineItems(3), i => Assert.Equal("", i.Text));
        r.Send("A", 0); r.Found("A", ModelRig.Synced());
        Assert.Equal(new[] { "", "♪", "un" }, r.M.LineItems(3).Select(i => i.Text));
        r.TickAt(21);
        Assert.Equal(new[] { "un", "deux", "trois" }, r.M.LineItems(3).Select(i => i.Text));
        Assert.Equal(new[] { "deux" }, r.M.LineItems(1).Select(i => i.Text));
        Assert.Equal(5, r.M.LineItems(5).Count);
    }
}
