namespace LyraLyrics.Core.Tests;

/// <summary>W6a : parties pures de la Scène sans équivalent Mac testable (pochette floutée, textes d'état, cadence d'images, courbe de mouvement).</summary>
public class W6Tests
{
    private static byte[] Solid(int w, int h, byte r, byte g, byte b)
    {
        var px = new byte[w * h * 4];
        for (var i = 0; i < w * h; i++) { px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b; px[i * 4 + 3] = 255; }
        return px;
    }

    [Fact]
    public void Blur_KeepsASolidColour_AndSpreadsAnEdge()
    {
        var solid = SceneArtworkMath.Blur(Solid(SceneArtworkMath.Side, SceneArtworkMath.Side, 200, 80, 20));
        Assert.All(Enumerable.Range(0, SceneArtworkMath.Side * SceneArtworkMath.Side), i =>
        {
            Assert.InRange(solid[i * 4], 199, 201); Assert.InRange(solid[i * 4 + 1], 79, 81); Assert.InRange(solid[i * 4 + 2], 19, 21); Assert.Equal(255, solid[i * 4 + 3]);
        });
        // moitié gauche noire, moitié droite blanche : après flou, le milieu est gris et les bords restent proches de leur couleur
        var side = SceneArtworkMath.Side; var edge = new byte[side * side * 4];
        for (var y = 0; y < side; y++) for (var x = 0; x < side; x++) { var v = (byte)(x < side / 2 ? 0 : 255); var i = (y * side + x) * 4; edge[i] = edge[i + 1] = edge[i + 2] = v; edge[i + 3] = 255; }
        var blurred = SceneArtworkMath.Blur(edge);
        int At(int x) => blurred[(5 * side + x) * 4];
        Assert.InRange(At(side / 2), 100, 155);
        Assert.True(At(0) < 40 && At(side - 1) > 215, $"bords : {At(0)} / {At(side - 1)}");
        Assert.True(At(side / 2 - 10) < At(side / 2 + 10));
    }

    [Fact]
    public void AspectFill_SamplesTheCentralSquare()
    {
        // image 4×2 : colonnes 0-1 rouges, colonnes 2-3 vertes ; le carré central 2×2 = colonnes 1-2 : moitié rouge, moitié vert
        var w = 4; var h = 2; var px = new byte[w * h * 4];
        for (var y = 0; y < h; y++) for (var x = 0; x < w; x++) { var i = (y * w + x) * 4; px[i] = (byte)(x < 2 ? 255 : 0); px[i + 1] = (byte)(x < 2 ? 0 : 255); px[i + 3] = 255; }
        var sq = SceneArtworkMath.AspectFillSquare(px, w, h, 8);
        Assert.Equal(8 * 8 * 4, sq.Length);
        Assert.True(sq[(2 * 8 + 0) * 4] > 200 && sq[(2 * 8 + 7) * 4 + 1] > 200);
        Assert.Equal(new byte[8 * 8 * 4], SceneArtworkMath.AspectFillSquare(new byte[3], 4, 2, 8));      // image invalide : carré vide, pas d'exception
    }

    [Fact]
    public void MaxLuminance_FindsTheBrightestCell()
    {
        var w = 120; var px = Solid(w, w, 0, 0, 0);
        for (var y = 0; y < 10; y++) for (var x = 0; x < 10; x++) { var i = (y * w + x) * 4; px[i] = px[i + 1] = px[i + 2] = 255; }       // une case blanche
        Assert.InRange(SceneArtworkMath.MaxLuminance(px, w, w), 0.999, 1.001);
        Assert.Equal(0, SceneArtworkMath.MaxLuminance(Solid(w, w, 0, 0, 0), w, w));
        Assert.Equal(1, SceneArtworkMath.MaxLuminance(new byte[4], 10, 10));          // données invalides : 1 (voile maximal prudent, comme le Mac)
        Assert.InRange(SceneArtworkMath.MaxLuminance(Solid(7, 5, 128, 128, 128), 7, 5), 0.2, 0.23);      // image plus petite que la grille
    }

    [Fact]
    public void Ease_IsMonotonicSymmetricAndHitsTheEnds()
    {
        Assert.Equal(0, SceneMotion.Ease(0)); Assert.Equal(1, SceneMotion.Ease(1));
        Assert.Equal(0, SceneMotion.Ease(-3)); Assert.Equal(1, SceneMotion.Ease(7));
        var last = 0.0;
        for (var i = 1; i <= 100; i++) { var v = SceneMotion.Ease(i / 100.0); Assert.True(v >= last - 1e-12); last = v; }
        Assert.InRange(SceneMotion.Ease(0.5), 0.4999999, 0.5000001);
        Assert.True(SceneMotion.Ease(0.1) < 0.1 && SceneMotion.Ease(0.9) > 0.9);      // démarrage et arrivée doux
    }

    [Fact]
    public void Motion_IsPeriodic_AndStartsAtRest()
    {
        var d0 = SceneMotion.DriftAt(0, 1920, 1080);
        Assert.Equal(1, d0.Scale); Assert.Equal(-1920 * 0.055, d0.Dx, 9); Assert.Equal(1080 * 0.035, d0.Dy, 9);
        var d48 = SceneMotion.DriftAt(48, 1920, 1080);
        Assert.Equal(1.2, d48.Scale, 9); Assert.Equal(1920 * 0.055, d48.Dx, 9); Assert.Equal(-1080 * 0.04, d48.Dy, 9);
        var d96 = SceneMotion.DriftAt(96, 1920, 1080);
        Assert.Equal(d0.Scale, d96.Scale, 9); Assert.Equal(d0.Dx, d96.Dx, 9);
        var b0 = SceneMotion.BreathAt(0); var b26 = SceneMotion.BreathAt(26); var b52 = SceneMotion.BreathAt(52);
        Assert.Equal((0.5, 1.0), b0); Assert.Equal(0.3, b26.Mid, 9); Assert.Equal(0.76, b26.End, 9); Assert.Equal(b0.Mid, b52.Mid, 9);
        Assert.Equal(1, SceneMotion.DriftAt(-5, 100, 100).Scale);          // temps négatif : au repos
    }

    [Fact]
    public void SceneInfo_UsesTheMacWords()
    {
        var track = new TrackInfo("Titre", "Artiste");
        DisplayState S(DisplayState.Screen s) => new(s, false, true);
        Assert.Equal(("Titre", "Artiste · Paroles indisponibles"), SceneInfo.Compute(S(new DisplayState.Screen.Unavailable()), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Artiste · Morceau instrumental"), SceneInfo.Compute(S(new DisplayState.Screen.InstrumentalScreen()), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Artiste · Paroles non synchronisées"), SceneInfo.Compute(S(new DisplayState.Screen.Unsynced()), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Artiste · Service de paroles occupé"), SceneInfo.Compute(S(new DisplayState.Screen.Busy(5)), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Artiste · Hors connexion"), SceneInfo.Compute(S(new DisplayState.Screen.Offline()), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Artiste · Recherche des paroles…"), SceneInfo.Compute(S(new DisplayState.Screen.Searching(false)), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Artiste"), SceneInfo.Compute(S(new DisplayState.Screen.SyncedScreen()), track, "Lyra Lyrics"));
        Assert.Equal(("Titre", "Paroles indisponibles"), SceneInfo.Compute(S(new DisplayState.Screen.Unavailable()), track with { Artist = "" }, "Lyra Lyrics"));
        var nothing = SceneInfo.Compute(DisplayState.Initial, null, "Lyra Lyrics");
        Assert.Equal("Rien en lecture", nothing.Title);
        Assert.Equal("Lance un titre dans Spotify : ses paroles apparaîtront ici.", nothing.Sub);
        Assert.Equal("Lyra Lyrics", SceneInfo.Compute(S(new DisplayState.Screen.SyncedScreen()), null, "Lyra Lyrics").Title);
    }

    [Fact]
    public void FrameRateMeter_EstimatesAndResets()
    {
        var m = new FrameRateMeter();
        Assert.Null(m.TakeFps(10));
        for (var i = 0; i <= 600; i++) m.Frame(100 + i / 10.0);           // 601 images en 60 s
        var fps = m.TakeFps(160);
        Assert.NotNull(fps); Assert.InRange(fps!.Value, 9.9, 10.2);
        Assert.Null(m.TakeFps(220));                                        // remis à zéro
    }

    [Fact]
    public void TextLuminance_FollowsTheChosenColourAndCapsAtSeventyPercent()
    {
        Assert.Equal(0.7, SceneBackdrop.TextLuminance(1.0, 0.9, false));
        Assert.Equal(0.4, SceneBackdrop.TextLuminance(0.4, 0.9, false));
        Assert.Equal(0.3, SceneBackdrop.TextLuminance(0.4, 0.3, true));
    }

    [Fact]
    public void SceneFrame_FitSize_And_Roles()
    {
        var f = SceneFrame.Compute(1920, 1080, true);
        Assert.Equal(new[] { 0, 0, 1, 2, 2 }, new[] { -3, 0, 1, 2, 5 }.Select(SceneFrame.Role));
        Assert.Equal(f.MaxLineSize, f.FitSize("Court", 0, (t, s, w) => s * 1.2));
        Assert.True(f.FitSize(new string('x', 400), 0, W6ParityTests.FakeMeasure) < f.MaxLineSize);
        var seules = SceneFrame.Compute(1920, 1080, false);
        Assert.Equal(1920 * 0.70, seules.TextWidth, 9); Assert.Equal(960, seules.TextCenterX, 9);        // 70 % de la largeur
    }

    [Fact]
    public void SceneZoom_Durations()
    {
        Assert.Equal(0.75, SceneZoom.DurationFor(false)); Assert.Equal(0.3, SceneZoom.DurationFor(true));
    }
}
