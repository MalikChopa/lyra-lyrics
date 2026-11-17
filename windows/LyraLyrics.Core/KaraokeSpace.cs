namespace LyraLyrics.Core;

/// <summary>
/// espace de dessin du remplissage karaoké (règle pure, testée sans WPF). Le remplissage est un pinceau (DrawingBrush) posé sur le texte ; ses morceaux
/// doivent tomber EXACTEMENT sur les lettres de chaque ligne rendue, dont les rectangles sont mesurés dans le repère du bloc de texte (TextBlock, origine en haut à gauche).
/// Cause du décalage vu sur Windows (non reproduite ici, déduite du code) : avec <c>ViewportUnits = RelativeToBoundingBox</c> le pinceau est étiré sur « la boîte englobante »
/// du texte peint (la documentation Microsoft dit que cette boîte dépend de la propriété qui porte le pinceau :
/// https://learn.microsoft.com/en-us/dotnet/api/system.windows.media.brushmappingmode), qui n'est pas le bloc : pour une ligne centrée elle commence au premier glyphe, pas au bord
/// du bloc. Le remplissage, calculé dans le repère du bloc, partait alors trop tard de la marge gauche de la ligne centrée. Correctif : unités ABSOLUES (« valeurs interprétées
/// directement dans l'espace local », même page), viewbox = viewport = le bloc agrandi d'une marge ; la correspondance bloc → remplissage est alors l'identité.
/// </summary>
public static class KaraokeSpace
{
    public readonly record struct Box(double X, double Y, double Width, double Height)
    {
        public double Right => X + Width;
        public double Bottom => Y + Height;
    }

    /// <summary>Marge (en DIP) autour du bloc : les lettres qui débordent un peu de la boîte (italique, crénage) restent peintes.</summary>
    public const double Margin = 24;

    /// <summary>Cadre du pinceau (viewbox ET viewport, en unités absolues du bloc) : le bloc agrandi de <paramref name="margin"/>.</summary>
    public static Box Frame(double blockWidth, double blockHeight, double margin = Margin) =>
        new(-margin, -margin, Math.Max(0, blockWidth) + 2 * margin, Math.Max(0, blockHeight) + 2 * margin);

    /// <summary>
    /// Rectangle du bloc → rectangle dans le repère du contenu du pinceau (viewbox) pour qu'il soit peint à cet endroit du bloc, sachant que le viewbox est étiré
    /// (Stretch.Fill) sur le viewport (exprimé dans le repère du bloc). Identité quand viewbox = viewport (cas retenu).
    /// </summary>
    public static Box ToFill(Box blockRect, Box viewbox, Box viewport)
    {
        double sx = viewport.Width > 0 ? viewbox.Width / viewport.Width : 1, sy = viewport.Height > 0 ? viewbox.Height / viewport.Height : 1;
        return new Box(viewbox.X + (blockRect.X - viewport.X) * sx, viewbox.Y + (blockRect.Y - viewport.Y) * sy, blockRect.Width * sx, blockRect.Height * sy);
    }

    /// <summary>Le bord de la zone remplie coïncide avec celui de la lettre (tolérance en DIP, 1 par défaut).</summary>
    public static bool EdgeMatches(double fillEdge, double glyphEdge, double tolerance = 1) => Math.Abs(fillEdge - glyphEdge) <= tolerance;

    /// <summary>Boîte englobante de plusieurs rectangles (vide si aucun).</summary>
    public static Box? Union(IEnumerable<Box> boxes)
    {
        double l = double.MaxValue, t = double.MaxValue, r = double.MinValue, b = double.MinValue; var any = false;
        foreach (var x in boxes) { any = true; l = Math.Min(l, x.X); t = Math.Min(t, x.Y); r = Math.Max(r, x.Right); b = Math.Max(b, x.Bottom); }
        return any ? new Box(l, t, r - l, b - t) : null;
    }
}
