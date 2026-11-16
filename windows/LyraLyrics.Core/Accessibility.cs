namespace LyraLyrics.Core;

/// <summary>
/// Préférences d'accessibilité du système, lues une fois au démarrage et à chaque événement de réglage (jamais à chaque image) :
/// « Afficher les animations » (SystemParameters.ClientAreaAnimation) et « Effets de transparence » (registre EnableTransparency).
/// Décisions pures ici (testées sur Mac) ; la lecture de Windows est dans l'app.
/// </summary>
public readonly record struct AccessibilityPrefs(bool AnimationsEnabled, bool TransparencyEnabled)
{
    public static readonly AccessibilityPrefs Default = new(true, true);

    /// <summary>Valeur du registre EnableTransparency (DWORD) : seule la valeur 0 désactive la transparence ; absente ou illisible = activée.</summary>
    public static bool TransparencyFromRegistry(object? value) => !(value is int v && v == 0);

    /// <summary>Transparence désactivée : tout style translucide (Verre, Transparent) retombe sur Uni, comme « Réduire la transparence » du Mac.</summary>
    public BackgroundStyle EffectiveStyle(BackgroundStyle style) => !TransparencyEnabled && style != BackgroundStyle.Solid ? BackgroundStyle.Solid : style;
}

/// <summary>
/// Barres fantômes de l'attente S22 (mêmes proportions que Shimmer.swift : trois barres de 78 %, 92 % et 60 % de la largeur, hauteur 11,
/// espacement 12, centrées dans la zone ; le reflet traverse en 1,9 s, bande de 45 % de la largeur, apparition après 0,45 s en 0,6 s).
/// </summary>
public static class ShimmerLayout
{
    public static readonly double[] BarFractions = { 0.78, 0.92, 0.6 };
    public const double BarHeight = 11, Spacing = 12, SweepSeconds = 1.9, BandFraction = 0.45, DelaySeconds = 0.45, FadeSeconds = 0.6, WidthFraction = 0.9, AreaHeight = 70;
    /// <summary>Décalage vertical de la zone quand l'indice « Recherche des paroles… » est affiché au centre (46).</summary>
    public const double HintOffset = 46;

    /// <summary>Rectangles (x, y, largeur, hauteur) des barres, de haut en bas, dans une zone <paramref name="width"/> × <paramref name="height"/>.</summary>
    public static IReadOnlyList<(double X, double Y, double W, double H)> Bars(double width, double height)
    {
        var n = BarFractions.Length;
        var top = (height - (n * BarHeight + (n - 1) * Spacing)) / 2;
        var list = new List<(double, double, double, double)>(n);
        for (var i = 0; i < n; i++)
        {
            var w = width * BarFractions[i];
            list.Add(((width - w) / 2, top + i * (BarHeight + Spacing), w, BarHeight));
        }
        return list;
    }
}
