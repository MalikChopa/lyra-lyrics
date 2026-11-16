using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>
/// W6a : fixtures PARTAGÉES avec Swift (<c>Tests/AppSupportTests/SceneFixtureTests.swift</c>) :
/// <c>golden/scene-screen.json</c>, <c>golden/scene-math.json</c>, <c>golden/scene-layout.json</c> (valeurs produites par <c>scene-generator.py</c>).
/// </summary>
public class W6ParityTests
{
    private static double D(JsonElement e, string name) => e.GetProperty(name).GetDouble();
    private static double? DN(JsonElement e, string name) => e.GetProperty(name).ValueKind == JsonValueKind.Null ? null : e.GetProperty(name).GetDouble();
    private static string S(JsonElement e, string name) => e.GetProperty(name).GetString()!;
    private static void Near(double want, double got, string what, double tol = 1e-9) =>
        Assert.True(Math.Abs(want - got) <= tol, $"{what} : attendu {want:R}, obtenu {got:R}");
    private static List<LyricLineTime> Lines(JsonElement arr) => arr.EnumerateArray().Select(l => new LyricLineTime(D(l, "time"), S(l, "text"))).ToList();

    // ---- scene-screen.json

    [Fact]
    public void SceneScreen_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-screen.json");
        var cases = doc.RootElement.GetProperty("cases").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var names = c.GetProperty("names").EnumerateArray().Select(n => n.GetString()!).ToList();
            var got = SceneScreenChoice.Pick(S(c, "setting"), names, c.GetProperty("mainIndex").GetInt32(), c.GetProperty("windowIndex").GetInt32());
            Assert.True(c.GetProperty("expected").GetInt32() == got, $"{S(c, "label")} : attendu {c.GetProperty("expected").GetInt32()}, obtenu {got}");
        }
        Assert.Equal(18, cases.Count);
    }

    // ---- scene-math.json

    [Fact]
    public void SceneMath_Fill_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-math.json");
        var fill = doc.RootElement.GetProperty("fill");
        var songs = fill.GetProperty("songs").EnumerateObject().ToDictionary(p => p.Name, p => Lines(p.Value));
        var durations = fill.GetProperty("durations").EnumerateArray().ToList();
        foreach (var c in durations)
            Near(D(c, "expected"), SceneMath.FillDuration(songs[S(c, "song")], c.GetProperty("index").GetInt32()), $"fillDuration {S(c, "song")} {c.GetProperty("index")}");
        var fractions = fill.GetProperty("fractions").EnumerateArray().ToList();
        foreach (var c in fractions) Near(D(c, "expected"), SceneMath.FillFraction(D(c, "position"), D(c, "start"), D(c, "duration")), $"fillFraction {c}");
        Assert.Equal(18, durations.Count);
        Assert.Equal(11, fractions.Count);
    }

    [Fact]
    public void SceneMath_SungDuration_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-math.json");
        var cases = doc.RootElement.GetProperty("sungDuration").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var text = S(c, "text");
            Assert.True(c.GetProperty("characters").GetInt32() == SceneMath.CharacterCount(text), $"nombre de caractères de « {text} » : attendu {c.GetProperty("characters")}, obtenu {SceneMath.CharacterCount(text)}");
            Near(D(c, "expected"), SceneMath.SungDuration(text), $"sungDuration « {text} »");
        }
        Assert.Equal(12, cases.Count);
    }

    [Fact]
    public void SceneMath_Gaps_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-math.json");
        var cases = doc.RootElement.GetProperty("gaps").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var got = SceneMath.Gaps(Lines(c.GetProperty("lines")), S(c, "placeholder"), DN(c, "duration"));
            var want = c.GetProperty("expected").EnumerateArray().ToList();
            Assert.True(want.Count == got.Count, $"{S(c, "label")} : {want.Count} passage(s) attendu(s), {got.Count} obtenu(s)");
            for (var i = 0; i < want.Count; i++)
            {
                Near(D(want[i], "start"), got[i].Start, S(c, "label") + " début");
                Near(D(want[i], "end"), got[i].End, S(c, "label") + " fin");
                Near(D(want[i], "fadeOutAt"), got[i].FadeOutAt, S(c, "label") + " fadeOutAt");
            }
        }
        Assert.Equal(12, cases.Count);
        var at = doc.RootElement.GetProperty("gapAt").EnumerateArray().ToList();
        foreach (var c in at)
        {
            var gaps = c.GetProperty("gaps").EnumerateArray().Select(g => new SceneMath.Gap(D(g, "start"), D(g, "end"))).ToList();
            var found = SceneMath.GapAt(D(c, "position"), gaps);
            var want = c.GetProperty("expectedIndex").GetInt32();
            Assert.True(want == (found is { } f ? gaps.IndexOf(f) : -1), $"gapAt {D(c, "position")}");
        }
        Assert.Equal(11, at.Count);
    }

    /// <summary>Mesure factice de la fixture : lignes = ceil(n / max(1, floor(largeur / (taille × 0,5)))), hauteur = lignes × taille × 1,2.</summary>
    public static double FakeMeasure(string text, double size, double width)
    {
        var perLine = Math.Max(1, Math.Floor(width / (size * 0.5)));
        return Math.Ceiling(SceneMath.CharacterCount(text) / perLine) * size * 1.2;
    }

    [Fact]
    public void SceneMath_FitSize_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-math.json");
        var cases = doc.RootElement.GetProperty("fitSize").EnumerateArray().ToList();
        foreach (var c in cases)
            Near(D(c, "expected"), SceneMath.FitSize(S(c, "text"), D(c, "width"), D(c, "maxHeight"), D(c, "maxSize"), FakeMeasure, D(c, "minSize")), "fitSize " + S(c, "label"));
        Assert.Equal(10, cases.Count);
    }

    [Fact]
    public void SceneMath_Contrast_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-math.json");
        var k = doc.RootElement.GetProperty("contrast");
        var n = 0;
        foreach (var c in k.GetProperty("maxBackground").EnumerateArray()) { Near(D(c, "expected"), SceneMath.MaxBackgroundLuminance(D(c, "text")), "maxBackground"); n++; }
        foreach (var c in k.GetProperty("scrim").EnumerateArray()) { Near(D(c, "expected"), SceneMath.ScrimAlpha(D(c, "background"), D(c, "text")), $"scrim {c}"); n++; }
        foreach (var c in k.GetProperty("contrast").EnumerateArray()) { Near(D(c, "expected"), SceneMath.Contrast(D(c, "text"), D(c, "background"), D(c, "scrim")), $"contrast {c}"); n++; }
        foreach (var c in k.GetProperty("background").EnumerateArray())
        {
            var b = SceneMath.Background(D(c, "art"), D(c, "gradient"), D(c, "text"));
            Near(D(c, "artOpacity"), b.ArtOpacity, $"background art {c}");
            Near(D(c, "scrim"), b.Scrim, $"background voile {c}");
            Near(D(c, "contrast"), b.Contrast, $"background contraste {c}");
            n++;
        }
        Assert.Equal(6 + 33 + 6 + 45, n);
    }

    private static Rgb Col(JsonElement a) => new(a[0].GetDouble(), a[1].GetDouble(), a[2].GetDouble());

    [Fact]
    public void SceneBackdrop_Gradient_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-math.json");
        var g = doc.RootElement.GetProperty("gradient");
        var neutral = SceneBackdrop.GradientColors(null);
        for (var i = 0; i < 3; i++) Assert.Equal(Col(g.GetProperty("neutral").GetProperty("colors")[i]), neutral[i]);
        Near(D(g.GetProperty("neutral"), "luminance"), SceneBackdrop.GradientLuminance(null), "luminance neutre");
        var palettes = g.GetProperty("palettes").EnumerateArray().ToList();
        foreach (var c in palettes)
        {
            var p = new ArtworkPalette(Col(c.GetProperty("dominant")), Col(c.GetProperty("secondary")));
            var tint = Col(c.GetProperty("tint"));
            Near(tint.R, p.Tint.R, S(c, "label") + " teinte R"); Near(tint.G, p.Tint.G, S(c, "label") + " teinte V"); Near(tint.B, p.Tint.B, S(c, "label") + " teinte B");
            var cols = SceneBackdrop.GradientColors(p);
            for (var i = 0; i < 3; i++)
            {
                var w = Col(c.GetProperty("colors")[i]);
                Near(w.R, cols[i].R, S(c, "label") + " R"); Near(w.G, cols[i].G, S(c, "label") + " V"); Near(w.B, cols[i].B, S(c, "label") + " B");
            }
            Near(D(c, "luminance"), SceneBackdrop.GradientLuminance(p), S(c, "label") + " luminance");
        }
        Assert.Equal(5, palettes.Count);
    }

    // ---- scene-layout.json

    [Fact]
    public void SceneLayout_Frames_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-layout.json");
        var frames = doc.RootElement.GetProperty("frames").EnumerateArray().ToList();
        foreach (var c in frames)
        {
            var w = D(c, "width"); var h = D(c, "height"); var art = c.GetProperty("withArtwork").GetBoolean();
            var f = SceneFrame.Compute(w, h, art);
            var e = c.GetProperty("frame");
            var tag = $"{w}x{h} {(art ? "pochette" : "seules")} ";
            Near(D(e, "artSide"), f.ArtSide, tag + "artSide"); Near(D(e, "artLeft"), f.ArtLeft, tag + "artLeft");
            Near(D(e, "columnLeft"), f.ColumnLeft, tag + "columnLeft"); Near(D(e, "textWidth"), f.TextWidth, tag + "textWidth");
            Near(D(e, "textCenterX"), f.TextCenterX, tag + "textCenterX"); Near(D(e, "centerY"), f.CenterY, tag + "centerY");
            Near(D(e, "artTop"), f.ArtTop, tag + "artTop"); Near(D(e, "artCorner"), f.ArtCorner, tag + "artCorner");
            Near(D(e, "titleSize"), f.TitleSize, tag + "titleSize"); Near(D(e, "artistSize"), f.ArtistSize, tag + "artistSize");
            Near(D(e, "titleTop"), f.TitleTop, tag + "titleTop"); Near(D(e, "artistTop"), f.ArtistTop, tag + "artistTop");
            Near(D(e, "maxLineSize"), f.MaxLineSize, tag + "maxLineSize");
            Near(D(e, "infoTitleSize"), f.InfoTitleSize, tag + "infoTitleSize"); Near(D(e, "infoSubSize"), f.InfoSubSize, tag + "infoSubSize");
            Near(D(e, "infoTitleTop"), f.InfoTitleTop, tag + "infoTitleTop"); Near(D(e, "infoSubTop"), f.InfoSubTop, tag + "infoSubTop");
            foreach (var role in new[] { 0, 1, 2 })
            {
                Near(D(c.GetProperty("layoutWidth"), role.ToString()), f.LayoutWidth(role), tag + "layoutWidth " + role);
                Near(D(c.GetProperty("fitMaxHeight"), role.ToString()), f.FitMaxHeight(role), tag + "fitMaxHeight " + role);
            }
        }
        Assert.Equal(18, frames.Count);
    }

    [Fact]
    public void SceneLayout_Targets_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-layout.json");
        var cases = doc.RootElement.GetProperty("targets").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var f = SceneFrame.Compute(1920, D(c, "height"), true);          // seule la hauteur compte pour les ordonnées
            var t = f.Target(c.GetProperty("offset").GetInt32(), D(c, "hCur"), D(c, "hNext"), D(c, "hSelf"), c.GetProperty("fillEnabled").GetBoolean());
            var tag = $"H={D(c, "height")} décalage {c.GetProperty("offset")} ";
            Near(D(c, "y"), t.Y, tag + "y"); Near(D(c, "scale"), t.Scale, tag + "échelle"); Near(D(c, "opacity"), t.Opacity, tag + "opacité");
            Near(D(c, "sharp"), t.Sharp, tag + "net"); Near(D(c, "soft"), t.Soft, tag + "flou");
        }
        Assert.Equal(48, cases.Count);
    }

    [Fact]
    public void SceneZoom_LocalRect_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/scene-layout.json");
        var cases = doc.RootElement.GetProperty("zoom").EnumerateArray().ToList();
        static RectD R(JsonElement a) => new(a[0].GetDouble(), a[1].GetDouble(), a[2].GetDouble(), a[3].GetDouble());
        foreach (var c in cases)
        {
            var screen = R(c.GetProperty("screen"));
            var got = SceneZoom.LocalRect(R(c.GetProperty("small")), screen);
            var want = R(c.GetProperty("expectedLocal"));
            var tag = S(c, "label");
            Near(want.X, got.X, tag + " x"); Near(want.Y, got.Y, tag + " y"); Near(want.Width, got.Width, tag + " largeur"); Near(want.Height, got.Height, tag + " hauteur");
            Near(D(c, "expectedStartScale"), SceneZoom.StartScale(got, screen.Width), tag + " échelle de départ");
        }
        Assert.Equal(7, cases.Count);
    }

    [Fact]
    public void SceneMotion_Drift_And_Breath_AgainstIndependentValues()
    {
        using var doc = Fixtures.Json("golden/scene-layout.json");
        var tol = D(doc.RootElement, "motionTolerance");
        var cases = doc.RootElement.GetProperty("motion").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var t = D(c, "t"); var d = SceneMotion.DriftAt(t, D(c, "width"), D(c, "height"));
            var wd = c.GetProperty("drift");
            Near(D(wd, "scale"), d.Scale, $"dérive t={t} échelle", tol); Near(D(wd, "dx"), d.Dx, $"dérive t={t} dx", tol); Near(D(wd, "dy"), d.Dy, $"dérive t={t} dy", tol);
            var b = SceneMotion.BreathAt(t);
            Near(D(c.GetProperty("breath"), "mid"), b.Mid, $"respiration t={t} milieu", tol); Near(D(c.GetProperty("breath"), "end"), b.End, $"respiration t={t} fin", tol);
        }
        Assert.Equal(16, cases.Count);
    }
}
