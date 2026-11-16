namespace LyraLyrics.Core;

/// <summary>Constantes de mise en page (port de LyricsMetrics, adapté : unités = DIP WPF).</summary>
public static class LyricsMetrics
{
    public const double WindowWidth = 460, DefaultHeight = 190;
    public const double PaddingTop = 34, PaddingBottom = 30, PaddingSide = 28;
    public const double MinResizeWidth = 280, MinResizeHeight = 110;
    public const double LineGap = 14, NeighbourRatio = 0.66, LineHeightFactor = 1.22, MinCurrentSize = 14;
    public static double TextWidth(double windowWidth) => Math.Max(120, windowWidth - 2 * PaddingSide);
}

public static class LineLook
{
    public static double Scale(int offset, double ratio) => Math.Abs(offset) switch { 0 => 1, 1 => ratio, _ => ratio * 0.88 };
    public static double Opacity(int offset) => Math.Abs(offset) switch { 0 => 1, 1 => 0.42, _ => 0.22 };
    /// <summary>Facteur d'opacité d'une ligne « atténuée » (indice « Recherche… »), comme le Mac (0,62 sur toutes les lignes atténuées).</summary>
    public const double DimFactor = 0.62;
    public static double Opacity(int offset, bool dim) => Opacity(offset) * (dim ? DimFactor : 1);
    /// <summary>Rayon de flou (points) du Mac : léger. Porté pour la parité ; la fenêtre Windows ne l'applique pas (voir journal W3, décision sur le flou).</summary>
    public static double Blur(int offset) => Math.Abs(offset) switch { 0 => 0, 1 => 0.8, _ => 1.6 };
}

public sealed record LineFit(double CurrentSize, double NeighbourSize, double ContentHeight, double WindowHeight, bool Shrunk, bool ExceedsMaxHeight);

/// <summary>
/// Ajustement du texte à la taille de la fenêtre (port de LineFitter.fit à taille imposée) : la taille effective est la plus grande,
/// entre le plancher (14) et « Taille max », pour laquelle les lignes visibles tiennent en largeur ET en hauteur. La mesure est injectée.
/// </summary>
public sealed class LineFitter
{
    private readonly Func<string, double, double, double> _measure;
    public LineFitter(Func<string, double, double, double> measureHeight) { _measure = measureHeight; }

    public double ContentHeight(IReadOnlyList<string> lines, double currentSize, double ratio, double width)
    {
        var mid = lines.Count / 2;
        var sum = 0.0;
        for (var i = 0; i < lines.Count; i++)
            sum += _measure(lines[i].Length == 0 ? " " : lines[i], currentSize, width) * LineLook.Scale(i - mid, ratio);
        return LyricsMetrics.LineGap * Math.Max(lines.Count - 1, 0) + sum;
    }

    public LineFit Fit(IReadOnlyList<string> lines, double baseSize, double windowWidth, double windowHeight, double ratio, double floor = LyricsMetrics.MinCurrentSize)
    {
        var width = LyricsMetrics.TextWidth(windowWidth);
        var available = windowHeight - LyricsMetrics.PaddingTop - LyricsMetrics.PaddingBottom;
        var texts = lines.Where(t => t.Length > 0).ToList();
        bool SingleLine(double size)
        {
            var one = _measure("M", size, width);
            return texts.All(t => _measure(t, size, width) <= one * 1.4);
        }
        var s = Math.Max(baseSize, floor);
        while (true)
        {
            var content = ContentHeight(lines, s, ratio, width);
            if (s <= floor || (content <= available && SingleLine(s)))
                return new LineFit(s, s * ratio, content, windowHeight, s < baseSize, content > available);
            s = Math.Max(s - 1, floor);
        }
    }
}
