using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>
/// W6c+d : fixture PARTAGÉE avec Swift (<c>Tests/AppSupportTests/SceneFixtureTests.swift</c>) : <c>golden/scene-extras.json</c>
/// (produite par <c>scene-generator.py</c>) : karaoké, passages sans paroles, carte du titre, barre de commandes, sortie de ligne, repli d'écran.
/// </summary>
public class W6cdParityTests
{
    private static double D(JsonElement e, string name) => e.GetProperty(name).GetDouble();
    private static string S(JsonElement e, string name) => e.GetProperty(name).GetString()!;
    private static bool B(JsonElement e, string name) => e.GetProperty(name).GetBoolean();
    private static void Near(double want, double got, string what, double tol = 1e-9) =>
        Assert.True(Math.Abs(want - got) <= tol, $"{what} : attendu {want:R}, obtenu {got:R}");
    private static List<LyricLineTime> Lines(JsonElement arr) => arr.EnumerateArray().Select(l => new LyricLineTime(D(l, "time"), S(l, "text"))).ToList();
    private static List<T> List<T>(JsonElement arr, Func<JsonElement, T> f) => arr.EnumerateArray().Select(f).ToList();
    private static JsonDocument Doc() => Fixtures.Json("golden/scene-extras.json");

    [Fact]
    public void Karaoke_Spec_SharedFixture()
    {
        using var doc = Doc();
        var cases = doc.RootElement.GetProperty("karaoke").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var got = KaraokeFill.Compute(Lines(c.GetProperty("lines")), c.GetProperty("index").GetInt32(), D(c, "position"), B(c, "playing"), B(c, "enabled"), B(c, "reduceMotion"), SyncEngine.Placeholder);
            var tag = $"{S(c, "song")} index {c.GetProperty("index")}";
            var want = c.GetProperty("expected");
            if (want.ValueKind == JsonValueKind.Null) { Assert.True(got is null, tag + " : aucun remplissage attendu"); continue; }
            Assert.True(got is not null, tag + " : remplissage attendu");
            Near(D(want, "duration"), got!.Value.Duration, tag + " durée"); Near(D(want, "fraction"), got.Value.Fraction, tag + " part");
            Assert.Equal(B(want, "playing"), got.Value.Playing);
        }
        Assert.Equal(60, cases.Count);
    }

    [Fact]
    public void Karaoke_Pieces_And_Resync_SharedFixture()
    {
        using var doc = Doc();
        var cases = doc.RootElement.GetProperty("fillPieces").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var widths = List(c.GetProperty("widths"), e => e.GetDouble());
            var cum = KaraokeFill.Cumulative(widths);
            var wantCum = List(c.GetProperty("cumulative"), e => e.GetDouble());
            Assert.Equal(wantCum.Count, cum.Length);
            for (var i = 0; i < cum.Length; i++) Near(wantCum[i], cum[i], $"cumul {i} de {string.Join(",", widths)}");
            var pieces = c.GetProperty("pieces").EnumerateArray().ToList();
            for (var i = 0; i < pieces.Count; i++)
            {
                var got = KaraokeFill.Schedule(cum, i, D(c, "startFraction"), D(c, "duration"), B(c, "playing"), B(c, "animated"));
                var tag = $"morceau {i} de {string.Join(",", widths)} départ {D(c, "startFraction")}";
                Near(D(pieces[i], "start"), got.Start, tag + " départ"); Near(D(pieces[i], "begin"), got.Begin, tag + " retard");
                Near(D(pieces[i], "duration"), got.Duration, tag + " durée"); Assert.Equal(B(pieces[i], "animated"), got.Animated);
            }
        }
        Assert.Equal(45, cases.Count);
        var resync = doc.RootElement.GetProperty("fillResync").EnumerateArray().ToList();
        foreach (var c in resync)
            Assert.Equal(B(c, "expectedResync"), KaraokeFill.NeedsResync(B(c, "currentPlaying"), D(c, "expected"), B(c, "wantPlaying"), D(c, "wantFraction")));
        Assert.Equal(8, resync.Count);
    }

    [Fact]
    public void GapWanted_SharedFixture()
    {
        using var doc = Doc();
        var cases = doc.RootElement.GetProperty("gapWanted").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var gaps = List(c.GetProperty("gaps"), g => new SceneMath.Gap(D(g, "start"), D(g, "end")));
            var mode = S(c, "mode") switch { "synced" => SceneGapRule.Mode.Synced, "searching" => SceneGapRule.Mode.Searching, "offline" => SceneGapRule.Mode.Offline, "busy" => SceneGapRule.Mode.Busy, _ => SceneGapRule.Mode.Other };
            Assert.True(B(c, "expected") == SceneGapRule.Wanted(mode, B(c, "playingOrPaused"), D(c, "position"), gaps), $"{S(c, "label")} {S(c, "mode")} à {D(c, "position")} s");
        }
        Assert.Equal(178, cases.Count);
        var budget = doc.RootElement.GetProperty("particleBudget");
        Assert.Equal(budget.GetProperty("budget").GetInt32(), GapParticles.Budget);
        Assert.Equal(budget.GetProperty("maximum").GetInt32(), GapParticles.Maximum);
        Near(D(budget, "birthRate"), GapParticles.BirthRate, "naissance"); Near(D(budget, "lifetime"), GapParticles.Lifetime, "vie");
    }

    [Fact]
    public void Bar_SharedFixture()
    {
        using var doc = Doc();
        var root = doc.RootElement;
        foreach (var c in root.GetProperty("barFormat").EnumerateArray()) Assert.Equal(S(c, "expected"), SceneBar.Format(D(c, "seconds")));
        Assert.Equal("-:--", SceneBar.Total(null));
        foreach (var c in root.GetProperty("barFraction").EnumerateArray())
            Near(D(c, "expected"), SceneBar.Fraction(D(c, "position"), c.GetProperty("duration").ValueKind == JsonValueKind.Null ? null : D(c, "duration")), $"part {c}");
        var layouts = root.GetProperty("barLayout").EnumerateArray().ToList();
        foreach (var c in layouts)
        {
            var l = SceneBar.Compute(D(c, "width"), D(c, "height")); var tag = $"barre {D(c, "width")}x{D(c, "height")} ";
            Near(D(c, "barWidth"), l.Width, tag + "largeur"); Near(D(c, "left"), l.Left, tag + "gauche"); Near(D(c, "top"), l.Top, tag + "haut");
            Near(D(c, "prevX"), l.PrevX, tag + "précédent"); Near(D(c, "playX"), l.PlayX, tag + "lecture"); Near(D(c, "nextX"), l.NextX, tag + "suivant"); Near(D(c, "exitX"), l.ExitX, tag + "sortie");
            Near(D(c, "rowY"), l.RowY, tag + "rangée"); Near(D(c, "trackLeft"), l.TrackLeft, tag + "piste x"); Near(D(c, "trackWidth"), l.TrackWidth, tag + "piste largeur");
            Near(D(c, "trackTop"), l.TrackTop, tag + "piste y"); Near(D(c, "elapsedLeft"), l.ElapsedLeft, tag + "écoulé"); Near(D(c, "totalLeft"), l.TotalLeft, tag + "total"); Near(D(c, "timeTop"), l.TimeTop, tag + "temps y");
        }
        Assert.Equal(5, layouts.Count);
        Assert.Equal(14, root.GetProperty("barFormat").GetArrayLength());
    }

    [Fact]
    public void LineExit_And_Card_SharedFixture()
    {
        using var doc = Doc();
        var root = doc.RootElement;
        foreach (var c in root.GetProperty("lineExit").EnumerateArray())
        {
            var p = LineExit.For(c.GetProperty("words").GetInt32());
            Near(D(c, "step"), p.Step, $"pas {c.GetProperty("words")}"); Near(D(c, "wordDuration"), p.WordDuration, $"mot {c.GetProperty("words")}"); Near(D(c, "total"), p.Total, $"total {c.GetProperty("words")}");
        }
        var cards = root.GetProperty("card").EnumerateArray().ToList();
        foreach (var c in cards)
        {
            var l = SceneCard.Compute(D(c, "width"), D(c, "height")); var tag = $"carte {D(c, "width")}x{D(c, "height")} ";
            Near(D(c, "side"), l.Side, tag + "côté"); Near(D(c, "artLeft"), l.ArtLeft, tag + "x"); Near(D(c, "artTop"), l.ArtTop, tag + "y"); Near(D(c, "artCorner"), l.ArtCorner, tag + "coin");
            Near(D(c, "reflectionTop"), l.ReflectionTop, tag + "reflet y"); Near(D(c, "reflectionHeight"), l.ReflectionHeight, tag + "reflet h");
            Near(D(c, "titleSize"), l.TitleSize, tag + "titre"); Near(D(c, "artistSize"), l.ArtistSize, tag + "artiste"); Near(D(c, "textLeft"), l.TextLeft, tag + "texte x"); Near(D(c, "textWidth"), l.TextWidth, tag + "texte l");
            Near(D(c, "titleTop"), l.TitleTop, tag + "titre y"); Near(D(c, "titleHeight"), l.TitleHeight, tag + "titre h"); Near(D(c, "artistTop"), l.ArtistTop, tag + "artiste y"); Near(D(c, "artistHeight"), l.ArtistHeight, tag + "artiste h");
        }
        Assert.Equal(5, cards.Count);
        foreach (var c in root.GetProperty("cardTiming").EnumerateArray())
        {
            var r = B(c, "reduce");
            Near(D(c, "in"), SceneCard.InSeconds(r), "entrée"); Near(D(c, "hold"), SceneCard.Hold, "tenue"); Near(D(c, "out"), SceneCard.OutSeconds(r), "sortie"); Near(D(c, "total"), SceneCard.Total(r), "total");
        }
    }

    [Fact]
    public void ScreenFallback_SharedFixture()
    {
        using var doc = Doc();
        var cases = doc.RootElement.GetProperty("screenFallback").EnumerateArray().ToList();
        static SceneScreenFallback.Bounds Bd(JsonElement a) { var v = a.EnumerateArray().ToList(); return new(v[0].GetString()!, v[1].GetInt32(), v[2].GetInt32(), v[3].GetInt32(), v[4].GetInt32()); }
        foreach (var c in cases)
        {
            var screens = List(c.GetProperty("screens"), Bd);
            Assert.True(c.GetProperty("expected").GetInt32() == SceneScreenFallback.Reconcile(screens, c.GetProperty("mainIndex").GetInt32(), Bd(c.GetProperty("current"))), S(c, "label"));
        }
        Assert.Equal(10, cases.Count);
    }
}
