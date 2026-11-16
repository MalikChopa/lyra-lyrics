namespace LyraLyrics.Core;

// W6a : géométrie et mouvements purs de la Scène. Port des formules de Sources/LyraLyrics/SceneView.swift, SceneController.swift et
// SceneExtras.swift (qui vivent dans l'app Mac, hors de portée des tests Swift : la preuve est Fixtures/golden/scene-layout.json,
// calculée par un script indépendant, lue par C# et par une transcription de ces formules dans Tests/AppSupportTests/SceneFixtureTests.swift).
// CONVENTION : ordonnées vers le BAS (haut de l'écran = 0), comme WPF. Le Mac compte vers le haut : y_C# = H - y_Mac.

public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double MidX => X + Width / 2;
    public double MidY => Y + Height / 2;
    /// <summary>Recouvrement d'aire non nulle (des bords qui se touchent ne comptent pas, comme CGRect.intersects).</summary>
    public bool Intersects(RectD o) => X < o.X + o.Width && o.X < X + Width && Y < o.Y + o.Height && o.Y < Y + Height && Width > 0 && Height > 0 && o.Width > 0 && o.Height > 0;
}

/// <summary>Mise en page de la Scène pour un écran de W × H (unités indépendantes de l'appareil).</summary>
public sealed record SceneFrame(
    double Width, double Height, bool WithArtwork,
    double ArtSide, double ArtLeft, double ColumnLeft, double TextWidth, double TextCenterX,
    double CenterY, double ArtTop, double ArtCorner,
    double TitleSize, double ArtistSize, double TitleTop, double ArtistTop,
    double MaxLineSize, double InfoTitleSize, double InfoSubSize, double InfoTitleTop, double InfoSubTop)
{
    /// <summary>« Avec la pochette » : pochette nette à gauche (un tiers), paroles à droite ; « Paroles seules » : paroles centrées sur 70 % de la largeur.</summary>
    public static SceneFrame Compute(double w, double h, bool withArtwork)
    {
        var artSide = Math.Min(w * 0.34, h * 0.56);
        var artLeft = w * 0.05;
        var columnLeft = artLeft + artSide + w * 0.04;
        var textWidth = withArtwork ? (w * 0.95 - columnLeft) * 0.96 : w * 0.70;
        var textCenterX = withArtwork ? (columnLeft + w * 0.95) / 2 : w / 2;
        var centerY = h * 0.44;                                  // Mac : 0,56 H depuis le bas
        var artTop = centerY - artSide / 2;
        var artBottom = centerY + artSide / 2;
        var ts = Math.Max(18, h * 0.028); var ss = Math.Max(14, h * 0.02);
        var its = Math.Max(30, h * 0.06); var iss = Math.Max(16, h * 0.03);
        return new SceneFrame(w, h, withArtwork, artSide, artLeft, columnLeft, textWidth, textCenterX,
            centerY, artTop, artSide * 0.045,
            ts, ss, artBottom + ts * 0.3, artBottom + ts * 1.7 + ss * 0.1,
            Math.Min(Math.Max(h * 0.085, 44), 124), its, iss, h - (h * 0.40 + its * 2.4), h - (h * 0.30 + iss * 2.6));
    }

    /// <summary>Échelle d'affichage selon le rôle de la ligne (0 courante, 1 suivante, 2 d'après).</summary>
    public static double DisplayScale(int role) => role == 0 ? 1 : (role == 1 ? 0.5 : 0.42);
    public static int Role(int offset) => offset <= 0 ? 0 : Math.Min(offset, 2);

    /// <summary>Largeur de mise en page : une fois réduite à l'échelle du rôle, la ligne occupe la même largeur utile que la courante.</summary>
    public double LayoutWidth(int role) => TextWidth / DisplayScale(role);
    /// <summary>Hauteur maximale de mise en page du texte d'une ligne de ce rôle.</summary>
    public double FitMaxHeight(int role) => Height * 0.27 / DisplayScale(role);

    /// <summary>Taille d'une ligne : la plus grande (≤ taille maximale) qui tient dans la largeur et la hauteur du rôle.</summary>
    public double FitSize(string text, int role, Func<string, double, double, double> measure) =>
        SceneMath.FitSize(text, LayoutWidth(role), FitMaxHeight(role), MaxLineSize, measure);

    public readonly record struct LineTarget(double Y, double Scale, double Opacity, double Sharp, double Soft);

    /// <summary>
    /// Place d'une ligne (centre vertical, échelle, opacités des trois bitmaps). <paramref name="hCur"/> = hauteur de mise en page de la ligne courante
    /// (H × 0,1 s'il n'y en a pas), <paramref name="hNext"/> = celle de la suivante, <paramref name="hSelf"/> = celle de la ligne elle-même.
    /// Décalage 1 et 2 : en dessous de la courante ; −1 : la ligne qui vient de partir (elle monte et s'efface) ; au-delà : hors scène.
    /// </summary>
    public LineTarget Target(int offset, double hCur, double hNext, double hSelf, bool fillEnabled)
    {
        var h = Height;
        var yCur = CenterY;
        switch (offset)
        {
            case 0: return new LineTarget(yCur, 1, 1, fillEnabled ? 0.78 : 0, 0);
            case 1: return new LineTarget(yCur + hCur / 2 + h * 0.05 + hSelf * 0.5 / 2, 0.5, 0.76, 1, 0);
            case 2:
            {
                var h1 = hNext * 0.5;
                return new LineTarget(yCur + hCur / 2 + h * 0.05 + h1 + h * 0.035 + hSelf * 0.42 / 2, 0.42, 0.72, 1, 0);
            }
            case -1: return new LineTarget(yCur - hCur / 2 - h * 0.13, 0.82, 0, 0.2, 0.7);
            default: return new LineTarget(yCur + h * 0.4, 0.4, 0, 1, 0);
        }
    }
}

/// <summary>S25 : zoom entre la petite fenêtre et le plein écran.</summary>
public static class SceneZoom
{
    public const double Duration = 0.75, ReducedDuration = 0.3, SmallCorner = 24;
    public static double DurationFor(bool reduceMotion) => reduceMotion ? ReducedDuration : Duration;

    /// <summary>Rectangle de la petite fenêtre en coordonnées de l'écran de la Scène ; ailleurs (autre écran), un rectangle centré (27 % de la largeur, rapport 0,42).</summary>
    public static RectD LocalRect(RectD small, RectD screen)
    {
        if (screen.Intersects(small)) return new RectD(small.X - screen.X, small.Y - screen.Y, small.Width, small.Height);
        var w = screen.Width * 0.27; var h = w * 0.42;
        return new RectD((screen.Width - w) / 2, (screen.Height - h) / 2, w, h);
    }

    /// <summary>Échelle de la scène au départ du zoom (jamais sous 5 %).</summary>
    public static double StartScale(RectD local, double screenWidth) => Math.Max(0.05, local.Width / Math.Max(1, screenWidth));
}

/// <summary>S1 : couleurs du dégradé de fond (palette de la pochette ou dégradé neutre) et luminance servant au réglage du voile.</summary>
public static class SceneBackdrop
{
    public static readonly Rgb[] DefaultColors = { new(0.10, 0.13, 0.24), new(0.05, 0.06, 0.12), new(0.14, 0.08, 0.20) };
    public const double DefaultLuminance = 0.02;

    static Rgb Scaled(Rgb c, double k) => new(c.R * k, c.G * k, c.B * k);

    /// <summary>Trois couleurs (haut-gauche → bas-droite) : dominante × 0,62, teinte, secondaire × 0,45 ; sans palette, le dégradé neutre.</summary>
    public static Rgb[] GradientColors(ArtworkPalette? palette) =>
        palette is null ? DefaultColors : new[] { Scaled(palette.Dominant, 0.62), palette.Tint, Scaled(palette.Secondary, 0.45) };

    /// <summary>Luminance du dégradé (pour <see cref="SceneMath.Background"/>).</summary>
    public static double GradientLuminance(ArtworkPalette? palette) =>
        palette is null ? DefaultLuminance : Math.Max(Math.Max(palette.Dominant.Luminance * 0.4, palette.Secondary.Luminance * 0.25), palette.Tint.Luminance);

    /// <summary>Luminance du texte retenue pour régler le fond : la couleur choisie (et l'accent du remplissage s'il est actif), plafonnée à 0,7.</summary>
    public static double TextLuminance(double lineLuminance, double accentLuminance, bool fillEnabled) =>
        Math.Min(fillEnabled ? Math.Min(lineLuminance, accentLuminance) : lineLuminance, 0.7);
}

/// <summary>Mouvements lents du fond en fonction du temps (Mac : animations Core Animation, courbe easeInEaseOut = Bézier 0,42 · 0 · 0,58 · 1).</summary>
public static class SceneMotion
{
    public const double DriftLeg = 48, BreathLeg = 26;               // durée d'un aller ; le retour est automatique (période = 2 allers)
    public const double DriftScaleTo = 1.2;
    public const double EaseX1 = 0.42, EaseY1 = 0, EaseX2 = 0.58, EaseY2 = 1;
    public const double BreathMidFrom = 0.5, BreathMidTo = 0.3, BreathEndFrom = 1.0, BreathEndTo = 0.76;

    /// <summary>Courbe easeInEaseOut : progression (0…1) pour une avancée linéaire <paramref name="x"/> (0…1).</summary>
    public static double Ease(double x)
    {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        // Bézier cubique (0,0) (x1,y1) (x2,y2) (1,1) : on cherche s tel que bx(s) = x (dichotomie), puis on renvoie by(s).
        double lo = 0, hi = 1, s = x;
        for (var i = 0; i < 60; i++)
        {
            s = (lo + hi) / 2;
            var bx = 3 * (1 - s) * (1 - s) * s * EaseX1 + 3 * (1 - s) * s * s * EaseX2 + s * s * s;
            if (bx < x) lo = s; else hi = s;
        }
        return 3 * (1 - s) * (1 - s) * s * EaseY1 + 3 * (1 - s) * s * s * EaseY2 + s * s * s;
    }

    /// <summary>Avancée linéaire 0…1…0 d'une animation aller-retour de demi-période <paramref name="leg"/> (t ≥ 0).</summary>
    public static double PingPong(double t, double leg)
    {
        if (t <= 0) return 0;
        var phase = (t % (2 * leg)) / leg;
        return phase <= 1 ? phase : 2 - phase;
    }

    public readonly record struct Drift(double Scale, double Dx, double Dy);

    /// <summary>Dérive de la pochette floutée à l'instant <paramref name="t"/> (s) : échelle 1 → 1,2 et décalage du centre (px, ordonnées vers le bas).</summary>
    public static Drift DriftAt(double t, double width, double height)
    {
        var p = Ease(PingPong(t, DriftLeg));
        return new Drift(1 + (DriftScaleTo - 1) * p,
            -width * 0.055 + (width * 0.055 * 2) * p,
            height * 0.035 + (-height * 0.04 - height * 0.035) * p);
    }

    /// <summary>Respiration du dégradé : positions des deux derniers arrêts (le premier reste à 0).</summary>
    public static (double Mid, double End) BreathAt(double t)
    {
        var p = Ease(PingPong(t, BreathLeg));
        return (BreathMidFrom + (BreathMidTo - BreathMidFrom) * p, BreathEndFrom + (BreathEndTo - BreathEndFrom) * p);
    }
}

/// <summary>Textes des états sans lignes dans la Scène (mêmes mots que le Mac, « Spotify » seul).</summary>
public static class SceneInfo
{
    /// <summary>Titre (gros) et sous-titre de l'écran d'information : titre en cours + « artiste · état », ou le texte de l'état seul s'il n'y a pas de titre.</summary>
    public static (string Title, string Sub) Compute(DisplayState display, TrackInfo? track, string appName)
    {
        var text = display.StateText;
        string status = display.Current switch
        {
            DisplayState.Screen.Unsynced => "Paroles non synchronisées",
            DisplayState.Screen.InstrumentalScreen => "Morceau instrumental",
            DisplayState.Screen.Unavailable => "Paroles indisponibles",
            DisplayState.Screen.Busy => "Service de paroles occupé",
            DisplayState.Screen.Offline => "Hors connexion",
            DisplayState.Screen.Nothing => text?.Body ?? "",
            DisplayState.Screen.Searching => "Recherche des paroles…",
            _ => text?.Title ?? "",
        };
        if (track is not null)
            return (track.Title, string.Join(" · ", new[] { track.Artist, status }.Where(s => s.Length > 0)));
        return (text?.Title ?? appName, text?.Body ?? "");
    }
}

/// <summary>Estimation de la cadence d'images (journal : toutes les 60 s pendant que la Scène est affichée). Pur : le temps est fourni.</summary>
public sealed class FrameRateMeter
{
    private double _start = double.NaN;
    private int _frames;
    public void Frame(double now) { if (double.IsNaN(_start)) _start = now; _frames++; }
    /// <summary>Images par seconde depuis la dernière lecture (null s'il n'y a rien à mesurer) ; repart de zéro.</summary>
    public double? TakeFps(double now)
    {
        double? fps = null;
        if (!double.IsNaN(_start) && now - _start > 0.5 && _frames > 0) fps = _frames / (now - _start);
        _start = double.NaN; _frames = 0;
        return fps;
    }
}
