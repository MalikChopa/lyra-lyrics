using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>W4 : port de <c>ManualChoiceTests.swift</c> et des tests de <c>Features110Tests.swift</c> propres à Windows, plus le service et le modèle.</summary>
public class W4Tests
{
    private static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    // ---- Port de ManualChoiceTests.swift

    [Fact]
    public void ManualChoice_DoesNotExpire_AutomaticDoes()
    {
        var index = new LookupIndex();
        index.Record("auto", new LookupIndex.Outcome.Found(1), T0);
        index.RecordManual("manuel", 42, T0);
        var later = T0 + LookupIndex.MaxAge + TimeSpan.FromSeconds(60);
        index.Purge(later);
        Assert.Null(index.Lookup("auto", later));
        Assert.Equal(42, index.ManualChoice("manuel"));
    }

    [Fact]
    public void ManualChoice_CoexistsWithAutomatic_RevertRemovesOnlyTheFirst()
    {
        var index = new LookupIndex();
        index.Record("k", new LookupIndex.Outcome.Found(7), T0);
        index.RecordManual("k", 99, T0);
        Assert.Equal(99, index.ManualChoice("k"));
        Assert.Equal(new LookupIndex.Outcome.Found(7), index.Lookup("k", T0));
        index.RemoveManual("k");
        Assert.Null(index.ManualChoice("k"));
        Assert.Equal(new LookupIndex.Outcome.Found(7), index.Lookup("k", T0));
        index.Remove("k");                              // « Réessayer » ne touche pas aux choix manuels
        index.RecordManual("k", 5, T0);
        index.Remove("k");
        Assert.Equal(5, index.ManualChoice("k"));
        index.Clear();
        Assert.Equal(0, index.Count);
    }

    [Fact]
    public void IndexFile_NeverHoldsText_RoundTrip_AndOldFilesStillLoad()
    {
        var dir = Path.Combine(Path.GetTempPath(), "lyra-w4-" + Guid.NewGuid().ToString("N"));
        try
        {
            var index = new LookupIndex();
            var key = new string('a', 64);
            index.RecordManual(key, 12, T0);
            index.Record(new string('b', 64), new LookupIndex.Outcome.Found(3), T0);
            var path = Path.Combine(dir, "index.json");
            index.Save(path);
            using (var doc = JsonDocument.Parse(File.ReadAllBytes(path)))
            {
                var allowed = new HashSet<string> { "key", "lrclibID", "storedAt", "manual" };
                foreach (var o in doc.RootElement.EnumerateArray()) Assert.True(o.EnumerateObject().Select(p => p.Name).ToHashSet().IsSubsetOf(allowed));
                Assert.Contains(doc.RootElement.EnumerateArray(), o => o.TryGetProperty("manual", out var m) && m.GetBoolean());
                Assert.Contains(doc.RootElement.EnumerateArray(), o => !o.TryGetProperty("manual", out _));   // « manual » absent pour l'automatique, comme le Mac
            }
            Assert.Equal(12, LookupIndex.Load(path).ManualChoice(key));
            var old = Path.Combine(dir, "old.json");
            File.WriteAllText(old, "[{\"key\":\"abc\",\"lrclibID\":3,\"storedAt\":\"2026-10-27T10:00:00Z\"}]");
            Assert.Equal(1, LookupIndex.Load(old).Count);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void ManualChoice_TrustsDuration_AutomaticChecksIt()
    {
        var rec = new LrclibRecord(1, "T", "A", null, 200, false, "x", "[00:01.00] x\n[00:03.00] y");
        var track = new TrackInfo("T", "A", null, 140);
        Assert.False(LrclibClient.LyricsFrom(rec, track, "p")!.IsSynced);
        Assert.True(LrclibClient.LyricsFrom(rec, track, "p", trustDuration: true)!.IsSynced);
    }

    // ---- C1 : délai de grâce

    [Fact]
    public void AutoHide_Grace_WaitsUntilTheEndOfTheGrace()
    {
        Assert.Equal(6.05, AutoHideState.GraceWait(100, 106), 6);
        Assert.Equal(0, AutoHideState.GraceWait(106, 106));
        Assert.Equal(0, AutoHideState.GraceWait(200, 106));
        Assert.Equal(6, AutoHideState.GraceSeconds);
    }

    // ---- Service : recherche manuelle, choix, retour au choix automatique

    private sealed class Rig
    {
        public readonly VirtualClock Clock = new();
        public readonly ScriptedTransport Transport;
        public readonly LyricsService Service;
        public readonly List<string> Logs = new();
        public Rig(Func<ScriptedTransport.Call, int, ScriptedTransport.Reply> handler, string? indexPath = null)
        {
            Transport = new ScriptedTransport(Clock, handler);
            Service = new LyricsService(new LrclibClient(Transport, "T/0 (t)", new Uri("http://127.0.0.1:1")), indexPath, LyricsService.SaltedHasher("s"), () => Clock.Now, Clock.Sleeper,
                log: f => Logs.Add(string.Join(" ", f.Select(kv => kv.Key + "=" + kv.Value))));
        }
    }

    private static readonly TrackInfo SomeTrack = new("Titre fictif", "Artiste fictif", "Album fictif", 140, Player: "fake");

    [Fact]
    public async Task Search_OneRequest_MetadataOnly_MaxThirty()
    {
        var many = Enumerable.Range(1, 40).Select(i => Wire.Record(i, "Titre " + i, "Artiste", duration: 140)).ToArray();
        var rig = new Rig((c, n) => c.Path == "/api/search" ? Wire.List(many) : Wire.NotFound);
        var outcome = await rig.Service.SearchAsync(" Titre ", " Artiste ");
        var results = Assert.IsType<ManualSearchOutcome.Results>(outcome).Candidates;
        Assert.Equal(30, results.Count);
        Assert.Single(rig.Transport.Calls);
        var call = rig.Transport.Calls[0];
        Assert.Equal("Titre", call.Query["track_name"]); Assert.Equal("Artiste", call.Query["artist_name"]);
        Assert.True(results[0].Synced);
        Assert.All(rig.Logs, l => Assert.DoesNotContain("Titre", l));
    }

    [Fact]
    public async Task Search_OneFieldEmpty_UsesCombinedQuery_BothEmpty_NoRequest()
    {
        var rig = new Rig((c, n) => Wire.List());
        await rig.Service.SearchAsync("Seulement le titre", "");
        Assert.Equal("Seulement le titre", rig.Transport.Calls[0].Query["q"]);
        var none = await rig.Service.SearchAsync("  ", "");
        Assert.Empty(Assert.IsType<ManualSearchOutcome.Results>(none).Candidates);
        Assert.Single(rig.Transport.Calls);
    }

    [Fact]
    public async Task Search_Failures_GiveReadableMessages_NoRetry()
    {
        var rig = new Rig((c, n) => Wire.Err(LrclibErrorKind.Timeout));
        Assert.Equal("Le service met trop de temps à répondre", Assert.IsType<ManualSearchOutcome.Failed>(await rig.Service.SearchAsync("a", "b")).Message);
        Assert.Single(rig.Transport.Calls);
        var rig2 = new Rig((c, n) => Wire.Busy());
        Assert.Equal("Le service ne répond pas pour l'instant", Assert.IsType<ManualSearchOutcome.Failed>(await rig2.Service.SearchAsync("a", "b")).Message);
        Assert.Single(rig2.Transport.Calls);
    }

    [Fact]
    public async Task Choose_UsesAtOnce_Remembers_NoIdInLogs_AndNextLookupUsesGetById()
    {
        var dir = Path.Combine(Path.GetTempPath(), "lyra-w4-" + Guid.NewGuid().ToString("N"));
        try
        {
            var path = Path.Combine(dir, LookupIndex.FileName);
            // la durée du candidat (200 s) diffère du titre joué (140 s) : le choix manuel reste synchronisé
            var rig = new Rig((c, n) => c.Path switch
            {
                "/api/search" => Wire.List(Wire.Record(777, "Autre version", "Artiste fictif", duration: 200)),
                "/api/get/777" => Wire.Ok(Wire.Record(777, "Autre version", "Artiste fictif", duration: 200)),
                _ => Wire.NotFound,
            }, path);
            await rig.Service.SearchAsync("Titre fictif", "Artiste fictif");
            LyricsServiceEvent? got = null;
            Assert.True(rig.Service.Choose(777, SomeTrack, e => got = e));
            var found = Assert.IsType<LyricsServiceEvent.Found>(got);
            Assert.True(found.Lyrics.IsSynced);
            Assert.True(rig.Service.HasManualChoice(SomeTrack));
            Assert.False(rig.Service.Choose(12345, SomeTrack, _ => { }));           // inconnu de la dernière recherche
            Assert.All(rig.Logs, l => Assert.DoesNotContain("777", l));            // D6 : jamais l'identifiant dans le journal
            var disk = File.ReadAllText(path);
            Assert.DoesNotContain("Autre version", disk); Assert.DoesNotContain("Un", disk.Replace("manual", "").Replace("lrclibID", ""));
            Assert.Contains("\"manual\":true", disk);

            // nouveau service sur le même fichier (autre démarrage) : une seule requête get/{id}, pas de recherche
            var rig2 = new Rig((c, n) => c.Path == "/api/get/777" ? Wire.Ok(Wire.Record(777, "Autre version", "Artiste fictif", duration: 200)) : Wire.NotFound, path);
            var tcs = new TaskCompletionSource<LyricsServiceEvent>();
            await rig2.Service.LookupAsync(SomeTrack, e => { if (e is LyricsServiceEvent.Found or LyricsServiceEvent.NotFound) tcs.TrySetResult(e); });
            var again = Assert.IsType<LyricsServiceEvent.Found>(await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5)));
            Assert.True(again.Lyrics.IsSynced);
            Assert.Equal(new[] { "/api/get/777" }, rig2.Transport.Paths);
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task PinnedChoice_GetFails_FallsBackToTheNormalSearch()
    {
        var rig = new Rig((c, n) => c.Path switch
        {
            "/api/search" when c.Query.ContainsKey("track_name") && c.Query["track_name"] == "Titre fictif" && n == 1 => Wire.List(Wire.Record(5, "Autre", "Artiste fictif", duration: 200)),
            "/api/get/5" => Wire.Ok(Wire.Record(5, "Autre", "Artiste fictif", duration: 200)),
            "/api/get" => Wire.Ok(Wire.Record(9, "Titre fictif", "Artiste fictif", duration: 140)),
            _ => Wire.NotFound,
        });
        await rig.Service.SearchAsync("Titre fictif", "Artiste fictif");
        Assert.True(rig.Service.Choose(5, SomeTrack, _ => { }));
        // le service redémarre avec le choix mémorisé mais get/5 répond 404 : la recherche normale prend le relais
        var rig2 = new Rig((c, n) => c.Path == "/api/get" ? Wire.Ok(Wire.Record(9, "Titre fictif", "Artiste fictif", duration: 140)) : Wire.NotFound);
        Assert.False(rig2.Service.HasManualChoice(SomeTrack));
    }

    [Fact]
    public async Task Revert_RemovesTheChoice_AndSearchesNormally()
    {
        var rig = new Rig((c, n) => c.Path switch
        {
            "/api/search" when c.Query.ContainsKey("track_name") && c.Query["track_name"] == "Titre fictif" => Wire.List(Wire.Record(5, "Autre", "Artiste fictif", duration: 200)),
            "/api/get" => Wire.Ok(Wire.Record(9, "Titre fictif", "Artiste fictif", duration: 140)),
            _ => Wire.NotFound,
        });
        await rig.Service.SearchAsync("Titre fictif", "Artiste fictif");
        Assert.True(rig.Service.Choose(5, SomeTrack, _ => { }));
        var tcs = new TaskCompletionSource<LyricsServiceEvent>();
        await rig.Service.RevertToAutomaticAsync(SomeTrack, e => { if (e is LyricsServiceEvent.Found) tcs.TrySetResult(e); });
        var found = Assert.IsType<LyricsServiceEvent.Found>(await tcs.Task.WaitAsync(TimeSpan.FromSeconds(5)));
        Assert.False(rig.Service.HasManualChoice(SomeTrack));
        Assert.Equal(9, found.Lyrics.LrclibId);
    }

    // ---- Modèle : états et second bouton, activité, retour automatique

    [Fact]
    public void Model_SecondaryAction_OnUnavailableAndBusyOnly()
    {
        var rig = new ModelRig();
        rig.Send("a", 5);
        Assert.Null(rig.M.SecondaryActionLabel);
        rig.M.OnServiceEvent(new LyricsServiceEvent.NotFound("x"), ModelRig.Track("a").Identity);
        Assert.Equal("Chercher une version", rig.M.SecondaryActionLabel);
        rig.M.RetryLookup();
        rig.M.OnServiceEvent(new LyricsServiceEvent.Stalled("x"), ModelRig.Track("a").Identity);
        Assert.Equal("Chercher une version", rig.M.SecondaryActionLabel);
        rig.M.OnServiceEvent(new LyricsServiceEvent.Found(ModelRig.Synced(), false), ModelRig.Track("a").Identity);
        Assert.Null(rig.M.SecondaryActionLabel);
    }

    [Fact]
    public void Model_Activity_NothingPausedPlaying()
    {
        var rig = new ModelRig();
        Assert.Equal(PlaybackActivity.Nothing, rig.M.Activity);
        rig.Send("a", 5);
        Assert.Equal(PlaybackActivity.Playing, rig.M.Activity);
        rig.Send("a", 6, PlaybackState.Paused);
        Assert.Equal(PlaybackActivity.Paused, rig.M.Activity);
        rig.Send(null, null, PlaybackState.Stopped);
        Assert.Equal(PlaybackActivity.Nothing, rig.M.Activity);
    }

    [Fact]
    public void Model_ManualChoice_FromProvenance_AndChoiceOnUnavailableShowsLyrics()
    {
        var rig = new ModelRig();
        rig.Send("a", 5);
        var id = ModelRig.Track("a").Identity;
        rig.M.OnServiceEvent(new LyricsServiceEvent.NotFound("x"), id);
        Assert.False(rig.M.IsManualChoice);
        var chosen = Lyrics.Synced(new LyricLine[] { new(1, "un"), new(9, "deux") }, 5, "choix manuel, durée inconnue");
        rig.M.OnServiceEvent(new LyricsServiceEvent.Found(chosen, false), id);
        Assert.True(rig.M.IsManualChoice);
        Assert.IsType<DisplayState.Screen.SyncedScreen>(rig.M.Display.Current);
        Assert.Null(rig.M.SecondaryActionLabel);
    }

    [Fact]
    public void Model_RevertToAutomatic_AsksTheEffect_AndRestartsTheSearch()
    {
        var rig = new ModelRig();
        rig.Send("a", 5);
        var id = ModelRig.Track("a").Identity;
        rig.M.OnServiceEvent(new LyricsServiceEvent.Found(Lyrics.Synced(new LyricLine[] { new(1, "un") }, 5, "choix manuel"), false), id);
        rig.M.RevertToAutomatic();
        Assert.IsType<DisplayState.Screen.Searching>(rig.M.Display.Current);
        Assert.False(rig.M.IsManualChoice);
        Assert.Single(rig.Fx.Retries);          // l'effet par défaut du faux = « Réessayer » (le vrai adaptateur oublie d'abord le choix)
    }
}
