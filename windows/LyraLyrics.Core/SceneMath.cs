using System.Globalization;

namespace LyraLyrics.Core;

// W6a : calculs purs de la Scène (plein écran), port de Sources/AppSupport/Features110.swift (SceneScreenChoice, SceneMath).
// Preuve : Fixtures/golden/scene-math.json et scene-screen.json, lus par les deux suites de tests.

/// <summary>Ligne horodatée sans dépendance au reste du cœur (comme LyricLineTime côté Mac).</summary>
public readonly record struct LyricLineTime(double Time, string Text);

/// <summary>S10 : choix de l'écran de la Scène.</summary>
public static class SceneScreenChoice
{
    public const string Window = "window", Main = "main";
    public static string Named(string name) => "name:" + name;

    /// <summary>Indice de l'écran à utiliser. Écran introuvable (débranché) → écran de la fenêtre.</summary>
    public static int Pick(string setting, IReadOnlyList<string> names, int mainIndex, int windowIndex)
    {
        if (names.Count == 0) return 0;
        var w = Math.Min(Math.Max(windowIndex, 0), names.Count - 1);
        if (setting == Main) return Math.Min(Math.Max(mainIndex, 0), names.Count - 1);
        if (setting.StartsWith("name:", StringComparison.Ordinal))
        {
            var wanted = setting.Substring(5);
            for (var i = 0; i < names.Count; i++) if (string.Equals(names[i], wanted, StringComparison.Ordinal)) return i;
            return w;
        }
        return w;
    }
}

public static class SceneMath
{
    // S5 : remplissage progressif
    public const double FillCap = 7.0, FillMin = 0.8, LastLineDuration = 4.0;

    /// <summary>Durée estimée du chant d'une ligne : temps jusqu'à la ligne suivante, moins un souffle, bornée (7 s au plus).</summary>
    public static double FillDuration(IReadOnlyList<LyricLineTime> lines, int index)
    {
        if (index < 0 || index >= lines.Count) return FillMin;
        var gap = index + 1 < lines.Count ? lines[index + 1].Time - lines[index].Time : LastLineDuration;
        return Math.Min(FillCap, Math.Max(FillMin, gap * 0.92));
    }

    /// <summary>Part remplie (0…1) à la position (déjà corrigée du décalage) pour une ligne qui commence à <paramref name="start"/>.</summary>
    public static double FillFraction(double position, double start, double duration)
    {
        if (!(duration > 0)) return 1;
        return Math.Min(1, Math.Max(0, (position - start) / duration));
    }

    // S6 : passages sans paroles
    public const double GapThreshold = 6.0, GapFadeOut = 1.0;

    /// <summary>Nombre de caractères au sens de Swift (grappes de graphèmes), pas d'unités UTF-16.</summary>
    public static int CharacterCount(string text) => new StringInfo(text).LengthInTextElements;

    /// <summary>Durée estimée du chant d'une ligne de texte (pour repérer les trous).</summary>
    public static double SungDuration(string text) => Math.Min(6, 1.2 + 0.06 * CharacterCount(text));

    public readonly record struct Gap(double Start, double End)
    {
        /// <summary>Fin de l'animation : 1 s avant la ligne suivante.</summary>
        public double FadeOutAt => Math.Max(Start, End - GapFadeOut);
    }

    /// <summary>
    /// Passages sans paroles : avant la première ligne (&gt; 6 s), entre deux lignes (&gt; 6 s après le chant estimé de la première, ou
    /// ligne vide « ♪ » de 3 s au moins), et après la dernière (&gt; 6 s avant la fin du titre, si la durée est connue).
    /// </summary>
    public static List<Gap> Gaps(IReadOnlyList<LyricLineTime> lines, string placeholder, double? duration)
    {
        var output = new List<Gap>();
        if (lines.Count == 0) return output;
        var first = lines[0];
        if (first.Time > GapThreshold && first.Text != placeholder) output.Add(new Gap(0, first.Time));
        for (var i = 0; i < lines.Count; i++)
        {
            var l = lines[i];
            double? next = i + 1 < lines.Count ? lines[i + 1].Time : duration;
            if (next is not double end) continue;
            if (l.Text == placeholder)
            {
                if (end - l.Time >= 3) output.Add(new Gap(l.Time, end));
            }
            else
            {
                var sungUntil = l.Time + SungDuration(l.Text);
                if (end - sungUntil > GapThreshold) output.Add(new Gap(sungUntil, end));
            }
        }
        return output;
    }

    /// <summary>Passage en cours à <paramref name="position"/> (début inclus, fin exclue).</summary>
    public static Gap? GapAt(double position, IReadOnlyList<Gap> gaps)
    {
        foreach (var g in gaps) if (position >= g.Start && position < g.End) return g;
        return null;
    }

    // S4 : taille du texte courant

    /// <summary>Plus grande taille (≤ <paramref name="maxSize"/>) pour laquelle le texte, renvoyé à la ligne dans <paramref name="width"/>, tient dans <paramref name="maxHeight"/>.</summary>
    public static double FitSize(string text, double width, double maxHeight, double maxSize, Func<string, double, double, double> measure, double minSize = 28)
    {
        var size = maxSize;
        while (size > minSize && measure(text, size, width) > maxHeight) size = Math.Max(minSize, Math.Floor(size * 0.94));
        return size;
    }

    // Contraste du texte sur le fond de la Scène

    /// <summary>Luminance relative maximale admise sous le texte pour qu'un texte de luminance <paramref name="textLuminance"/> garde 4,5 : 1.</summary>
    public static double MaxBackgroundLuminance(double textLuminance, double ratio = 4.5) => Math.Max(0, (textLuminance + 0.05) / ratio - 0.05);

    /// <summary>Opacité du voile noir à poser sur un fond de luminance maximale <paramref name="background"/> pour garder 4,5 : 1 (au moins 0,30 : ambiance).</summary>
    public static double ScrimAlpha(double backgroundLuminance, double textLuminance, double minimum = 0.30)
    {
        var allowed = MaxBackgroundLuminance(textLuminance);
        if (!(backgroundLuminance > 0)) return minimum;
        return Math.Min(0.92, Math.Max(minimum, 1 - allowed / backgroundLuminance));
    }

    public readonly record struct BackgroundBalance(double ArtOpacity, double Scrim, double Contrast);

    /// <summary>
    /// Réglage du fond de la Scène : opacité de la pochette floutée et voile noir qui gardent <paramref name="textLuminance"/> à ≥ 4,5 : 1.
    /// Fond effectif = (L_pochette × a + L_dégradé × (1 − a)) × (1 − voile). Voile de 0,30 au moins ; la pochette s'efface d'abord
    /// (a de 0,92 vers 0) tant que le contraste n'y est pas ; si le dégradé seul ne suffit pas, le voile monte.
    /// </summary>
    public static BackgroundBalance Background(double artLuminance, double gradientLuminance, double textLuminance)
    {
        double Effective(double a, double s) => (artLuminance * a + gradientLuminance * (1 - a)) * (1 - s);
        double Ratio(double a, double s) => Contrast(textLuminance, Effective(a, s), 0);
        var scrim = 0.30;
        while (scrim <= 0.95)
        {
            var a = 0.92;
            while (a >= 0)
            {
                if (Ratio(a, scrim) >= 4.5) return new BackgroundBalance(a, scrim, Ratio(a, scrim));
                a -= 0.04;
            }
            scrim += 0.05;
        }
        return new BackgroundBalance(0, 0.95, Ratio(0, 0.95));
    }

    /// <summary>Contraste obtenu pour ce fond voilé.</summary>
    public static double Contrast(double textLuminance, double backgroundLuminance, double scrim)
    {
        var bg = backgroundLuminance * (1 - scrim);
        return (Math.Max(textLuminance, bg) + 0.05) / (Math.Min(textLuminance, bg) + 0.05);
    }
}
