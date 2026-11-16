namespace LyraLyrics.Core;

// W6c+d : règles pures des finitions de la Scène (karaoké S5, passages sans paroles S6, carte du titre S14/S19, grain et vignette S18,
// barre de commandes, sortie de ligne mot à mot, repli d'écran). Ports des formules de Sources/LyraLyrics/SceneView.swift, SceneExtras.swift,
// FillMask.swift et AppModel.swift (karaokeSpec), qui vivent dans l'app Mac, hors de portée de ses tests : la preuve est
// Fixtures/golden/scene-extras.json (produit par scene-generator.py, lu par C# et par une transcription Swift).
// CONVENTION : ordonnées vers le BAS (haut de l'écran = 0), comme le reste de la géométrie de la Scène.

/// <summary>S5 / S24 : remplissage karaoké de la ligne courante.</summary>
public static class KaraokeFill
{
    public readonly record struct Spec(int Index, double Duration, double Fraction, bool Playing);

    /// <summary>Remplissage demandé (AppModel.karaokeSpec) : null si désactivé, animations réduites, pas de ligne chantée ou ligne « ♪ ».</summary>
    public static Spec? Compute(IReadOnlyList<LyricLineTime> lines, int index, double position, bool playing, bool enabled, bool reduceMotion, string placeholder)
    {
        if (!enabled || reduceMotion || index < 0 || index >= lines.Count) return null;
        var line = lines[index];
        if (line.Text == placeholder) return null;
        var d = SceneMath.FillDuration(lines, index);
        return new Spec(index, d, SceneMath.FillFraction(position, line.Time, d), playing);
    }

    /// <summary>Fin cumulée (0…1) de chaque morceau (un par ligne de texte rendue, pondéré par sa largeur) ; n + 1 valeurs, la dernière vaut 1.</summary>
    public static double[] Cumulative(IReadOnlyList<double> widths)
    {
        var cum = new double[widths.Count + 1];
        if (widths.Count == 0) { cum[0] = 1; return cum; }
        var total = Math.Max(1, widths.Sum());
        double acc = 0;
        for (var i = 0; i < widths.Count; i++) { acc += widths[i] / total; cum[i + 1] = Math.Min(1, acc); }
        cum[^1] = 1;
        return cum;
    }

    /// <summary>Un morceau : part déjà remplie au départ, retard avant son animation, durée de celle-ci (0 et faux = figé à <see cref="Start"/>).</summary>
    public readonly record struct Piece(double Start, double Begin, double Duration, bool Animated);

    /// <summary>Plan du morceau <paramref name="i"/> (FillMask.set) : les lignes suivantes attendent la fin des précédentes, en proportion de leur largeur.</summary>
    public static Piece Schedule(double[] cumulative, int i, double startFraction, double duration, bool playing, bool animated)
    {
        var f0 = Math.Min(1, Math.Max(0, startFraction));
        double c0 = cumulative[i], c1 = cumulative[i + 1];
        var v = c1 > c0 ? Math.Min(1, Math.Max(0, (f0 - c0) / (c1 - c0))) : 1;
        if (animated && playing && v < 1 && duration > 0)
            return new Piece(v, Math.Max(0, c0 - f0) * duration, Math.Max(0.05, (c1 - Math.Max(c0, f0)) * duration), true);
        return new Piece(v, 0, 0, false);
    }

    /// <summary>Part remplie attendue <paramref name="elapsed"/> secondes après le dernier réglage.</summary>
    public static double Expected(double startFraction, double duration, bool playing, double elapsed) =>
        duration > 0 && playing ? Math.Min(1, startFraction + elapsed / duration) : startFraction;

    /// <summary>Le remplissage en cours s'est écarté (pause, reprise, saut) : on le refait.</summary>
    public static bool NeedsResync(bool currentPlaying, double expectedFraction, bool wantPlaying, double wantFraction) =>
        currentPlaying != wantPlaying || Math.Abs(expectedFraction - wantFraction) > 0.18;
}

/// <summary>S6 : règle d'affichage de l'animation calme (note qui respire et particules lentes).</summary>
public static class SceneGapRule
{
    public enum Mode { Synced, Searching, Offline, Busy, Other }

    public const double FadeSeconds = 1.0, FadeQuickSeconds = 0.05, BreathSeconds = 3.6;
    public const double BreathScaleFrom = 0.92, BreathScaleTo = 1.08, BreathOpacityFrom = 0.55, BreathOpacityTo = 0.95;
    public const double NoteSizeFraction = 0.13, NoteTopFraction = 0.33, NoteWidthFraction = 0.2, NoteHeightFraction = 0.17;

    /// <summary>SceneView.desiredGap : synchronisé = dans un passage et avant le début du fondu de sortie ; recherche, hors connexion, occupé = jamais ; autres états (instrumental, non synchronisé, rien en lecture…) = toujours.</summary>
    public static bool Wanted(Mode mode, bool playingOrPaused, double position, IReadOnlyList<SceneMath.Gap> gaps)
    {
        switch (mode)
        {
            case Mode.Synced:
                if (!playingOrPaused) return false;
                return SceneMath.GapAt(position, gaps) is { } g && position < g.FadeOutAt;
            case Mode.Searching: case Mode.Offline: case Mode.Busy: return false;
            default: return true;
        }
    }
}

/// <summary>Particules lentes de l'animation calme : au plus 30 en même temps (naissance 3,4 / s, vie 8 s = 27).</summary>
public static class GapParticles
{
    public const double BirthRate = 3.4, Lifetime = 8, SpeedMean = 22, SpeedRange = 8, AngleRange = 0.35, ScaleMean = 0.32, ScaleRange = 0.18, DotSide = 32, StartAlpha = 0.55, AlphaSpeed = -0.07;
    public const int Maximum = 30;
    /// <summary>Nombre de particules vivantes en régime établi (arrondi vers le bas : 27,2 → 27).</summary>
    public static int Budget => (int)Math.Floor(BirthRate * Lifetime);

    /// <summary>Une particule : place sur la ligne d'émission (0…1), vitesse horizontale et verticale (px/s, vers le haut = négatif), diamètre (px), retard de naissance (s).</summary>
    public readonly record struct Particle(double XFraction, double Vx, double Vy, double Diameter, double Delay);

    private static double Unit(uint seed, int salt)
    {
        var x = seed * 2654435761u + (uint)salt * 40503u + 0x9E3779B9u;
        x ^= x >> 16; x *= 0x85EBCA6Bu; x ^= x >> 13; x *= 0xC2B2AE35u; x ^= x >> 16;
        return x / 4294967296.0;
    }

    public static Particle At(int index, uint seed = 20261116)
    {
        var s = seed + (uint)index * 7919u;
        var speed = SpeedMean + (Unit(s, 1) - 0.5) * 2 * SpeedRange;
        var angle = (Unit(s, 2) - 0.5) * 2 * AngleRange;                    // 0 = droit vers le haut
        var scale = ScaleMean + (Unit(s, 3) - 0.5) * 2 * ScaleRange;
        return new Particle(Unit(s, 4), speed * Math.Sin(angle), -speed * Math.Cos(angle), DotSide * scale, index / BirthRate);
    }

    /// <summary>Opacité d'une particule <paramref name="age"/> secondes après sa naissance (le canal alpha baisse de 0,07 par seconde).</summary>
    public static double OpacityAt(double age) => Math.Max(0, StartAlpha + AlphaSpeed * Math.Max(0, age));
}

/// <summary>S14 + S19 : carte du titre (pochette, titre, artiste, reflet doux), seulement en mise en page « Paroles seules ».</summary>
public static class SceneCard
{
    public const double Hold = 1.5, In = 0.9, Out = 0.9, ReducedFade = 0.3, StartScale = 0.94, EndScale = 1.03, PendingDelay = 1.2, ReflectionOpacity = 0.26;

    public static double InSeconds(bool reduce) => reduce ? ReducedFade : In;
    public static double OutSeconds(bool reduce) => reduce ? ReducedFade : Out;
    public static double Total(bool reduce) => InSeconds(reduce) + Hold + OutSeconds(reduce);
    /// <summary>La carte n'existe pas avec la pochette (elle reste à gauche).</summary>
    public static bool Allowed(bool withArtwork) => !withArtwork;

    public sealed record Layout(double Side, double ArtLeft, double ArtTop, double ArtCorner, double ReflectionTop, double ReflectionHeight,
        double TitleSize, double ArtistSize, double TextLeft, double TextWidth, double TitleTop, double TitleHeight, double ArtistTop, double ArtistHeight);

    public static Layout Compute(double w, double h)
    {
        var side = Math.Min(h * 0.40, w * 0.30);
        var ts = Math.Max(30, h * 0.058); var ss = Math.Max(18, h * 0.031);
        var rh = side * 0.28;
        return new Layout(side, w / 2 - side / 2, h * 0.5 - side, side * 0.04, h * 0.5 + 2, rh, ts, ss, w * 0.2, w * 0.6,
            h * 0.5 + side * 0.30 + ts * 0.7, ts * 1.3, h * 0.5 + side * 0.30 + ts * 2.0 + ss * 0.3, ss * 1.3);
    }
}

/// <summary>S18 : grain léger et vignette.</summary>
public static class SceneGrain
{
    public const int Side = 256;
    public const double VignetteAlpha = 0.34, VignetteClearUntil = 0.55, FadeSeconds = 0.6;
    public const int MaxAlpha = 10;                        // sur 255 : moins de 4 %

    /// <summary>Motif de grain (BGRA prémultiplié) : chaque point est clair ou sombre, d'opacité 0 à 10/255.</summary>
    public static byte[] Tile(int side = Side, uint seed = 7)
    {
        var px = new byte[side * side * 4];
        uint state = seed * 2891336453u + 1;
        uint Next() { state ^= state << 13; state ^= state >> 17; state ^= state << 5; return state; }
        for (var i = 0; i < side * side; i++)
        {
            var light = (Next() & 1) == 1;
            var a = (byte)(Next() % (MaxAlpha + 1));
            var v = (byte)((light ? 255 : 0) * a / 255);
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = a;
        }
        return px;
    }
}

/// <summary>Barre de commandes du bas : précédent, lecture/pause, suivant, progression fine, temps, sortie.</summary>
public static class SceneBar
{
    public const double Height = 96, BottomMargin = 46, MaxWidth = 720, WidthFraction = 0.56, Corner = 22, HideDelay = 3.0, FadeIn = 0.2, FadeOut = 0.6;
    public const double PlaySize = 52, ButtonSize = 44, TrackHeight = 4;

    public static string Format(double seconds)
    {
        var s = double.IsFinite(seconds) ? (long)Math.Max(0, Math.Floor(seconds)) : 0;
        return $"{s / 60}:{s % 60:00}";
    }
    public static string Total(double? duration) => duration is double d ? Format(d) : "-:--";
    public static double Fraction(double position, double? duration) => duration is double d && d > 0 ? Math.Min(1, Math.Max(0, position / d)) : 0;

    public sealed record Layout(double Width, double Left, double Top, double PrevX, double PlayX, double NextX, double ExitX, double RowY,
        double TrackLeft, double TrackWidth, double TrackTop, double ElapsedLeft, double TotalLeft, double TimeTop, double TimeWidth, double TimeHeight);

    /// <summary>Position des éléments, relative à la barre pour les x et y des boutons (centres), absolue pour Left et Top.</summary>
    public static Layout Compute(double w, double h)
    {
        var bw = Math.Min(w * WidthFraction, MaxWidth);
        return new Layout(bw, (w - bw) / 2, h - BottomMargin - Height, bw / 2 - 74, bw / 2, bw / 2 + 74, bw - 40, Height - 66,
            84, bw - 2 * 84, Height - 24, 14, bw - 76, Height - 30, 62, 18);
    }
}

/// <summary>Sortie de la ligne qui part : elle monte, rétrécit un peu et s'efface mot à mot (décalage ~40 ms, ~0,6 s).</summary>
public static class LineExit
{
    public const double Duration = 0.6, Step = 0.040, Scale = 0.92, RiseFraction = 0.05, MaxSpread = 0.32, MinWord = 0.3;
    public readonly record struct Plan(int Words, double Step, double WordDuration, double Total);

    public static Plan For(int words)
    {
        var step = words > 1 ? Math.Min(Step, MaxSpread / (words - 1)) : 0;
        var wordDuration = Math.Max(MinWord, Duration - Math.Max(0, words - 1) * step);
        return new Plan(words, step, wordDuration, Math.Max(0, words - 1) * step + wordDuration);
    }
}

public static class SceneScreenFallback
{
    public readonly record struct Bounds(string Name, int X, int Y, int Width, int Height);

    /// <summary>
    /// Écran à utiliser après un changement d'écrans (branchement, débranchement, résolution) : le même (nom et rectangle) s'il existe encore ;
    /// sinon le même nom (résolution changée) ; sinon l'écran principal. Jamais d'exception : liste vide → -1.
    /// </summary>
    public static int Reconcile(IReadOnlyList<Bounds> screens, int mainIndex, Bounds current)
    {
        if (screens.Count == 0) return -1;
        for (var i = 0; i < screens.Count; i++) if (screens[i] == current) return i;
        for (var i = 0; i < screens.Count; i++) if (string.Equals(screens[i].Name, current.Name, StringComparison.Ordinal)) return i;
        return Math.Min(Math.Max(mainIndex, 0), screens.Count - 1);
    }
}
