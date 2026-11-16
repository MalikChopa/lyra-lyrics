namespace LyraLyrics.Core;

/// <summary>
/// Pochette de fond de la Scène : floutée UNE fois par titre sur une petite image (160 px), affichée ensuite agrandie par le processeur graphique
/// (comme le Mac : SceneArtwork.blurred). Le flou gaussien est approché par trois passes de flou « boîte » (écart-type voisin de 14).
/// Fonctions pures sur des pixels RGBA 8 bits (non prémultipliés, opaques une fois le fond posé).
/// </summary>
public static class SceneArtworkMath
{
    public const int Side = 160;
    public const int BoxRadius = 13;      // 3 passes de largeur 27 : écart-type ≈ sqrt(3 × (27² − 1) / 12) ≈ 13,5, proche du rayon 14 du Mac
    public const int Passes = 3;
    public const int LuminanceGrid = 12;

    /// <summary>Pixels de <paramref name="rgba"/> (largeur × hauteur) recadrés « aspect fill » dans un carré de <paramref name="side"/> px (échantillonnage bilinéaire).</summary>
    public static byte[] AspectFillSquare(byte[] rgba, int width, int height, int side = Side)
    {
        var output = new byte[side * side * 4];
        if (width <= 0 || height <= 0 || rgba.Length < width * height * 4) return output;
        var crop = Math.Min(width, height);                       // carré central de la source
        double ox = (width - crop) / 2.0, oy = (height - crop) / 2.0;
        for (var y = 0; y < side; y++)
            for (var x = 0; x < side; x++)
            {
                var sx = ox + (x + 0.5) * crop / side - 0.5; var sy = oy + (y + 0.5) * crop / side - 0.5;
                int x0 = (int)Math.Floor(sx), y0 = (int)Math.Floor(sy);
                var fx = sx - x0; var fy = sy - y0;
                for (var c = 0; c < 4; c++)
                {
                    double P(int px, int py) => rgba[(Math.Clamp(py, 0, height - 1) * width + Math.Clamp(px, 0, width - 1)) * 4 + c];
                    var v = P(x0, y0) * (1 - fx) * (1 - fy) + P(x0 + 1, y0) * fx * (1 - fy) + P(x0, y0 + 1) * (1 - fx) * fy + P(x0 + 1, y0 + 1) * fx * fy;
                    output[(y * side + x) * 4 + c] = (byte)Math.Clamp((int)Math.Round(v), 0, 255);
                }
            }
        return output;
    }

    /// <summary>Flou (trois passes de flou boîte, bords prolongés) d'une image carrée <paramref name="side"/> × <paramref name="side"/>. Renvoie une copie.</summary>
    public static byte[] Blur(byte[] rgba, int side = Side, int radius = BoxRadius, int passes = Passes)
    {
        var a = (byte[])rgba.Clone();
        var b = new byte[a.Length];
        for (var p = 0; p < passes; p++)
        {
            BoxPass(a, b, side, radius, horizontal: true);
            BoxPass(b, a, side, radius, horizontal: false);
        }
        return a;
    }

    private static void BoxPass(byte[] src, byte[] dst, int side, int radius, bool horizontal)
    {
        var window = 2 * radius + 1;
        for (var line = 0; line < side; line++)
            for (var c = 0; c < 4; c++)
            {
                int Idx(int i) => (horizontal ? line * side + Math.Clamp(i, 0, side - 1) : Math.Clamp(i, 0, side - 1) * side + line) * 4 + c;
                long sum = 0;
                for (var i = -radius; i <= radius; i++) sum += src[Idx(i)];
                for (var i = 0; i < side; i++)
                {
                    dst[(horizontal ? line * side + i : i * side + line) * 4 + c] = (byte)((sum + window / 2) / window);
                    sum += src[Idx(i + radius + 1)] - src[Idx(i - radius)];
                }
            }
    }

    /// <summary>Luminance relative maximale (WCAG) sur une grille 12 × 12 de cases moyennées : sert à régler le voile qui garde le texte à ≥ 4,5 : 1.</summary>
    public static double MaxLuminance(byte[] rgba, int width, int height, int n = LuminanceGrid)
    {
        if (width <= 0 || height <= 0 || rgba.Length < width * height * 4) return 1;
        var best = 0.0;
        for (var cy = 0; cy < n; cy++)
            for (var cx = 0; cx < n; cx++)
            {
                int x0 = cx * width / n, x1 = Math.Max(x0 + 1, (cx + 1) * width / n), y0 = cy * height / n, y1 = Math.Max(y0 + 1, (cy + 1) * height / n);
                double r = 0, g = 0, b = 0; var count = 0;
                for (var y = y0; y < Math.Min(y1, height); y++)
                    for (var x = x0; x < Math.Min(x1, width); x++) { var i = (y * width + x) * 4; r += rgba[i]; g += rgba[i + 1]; b += rgba[i + 2]; count++; }
                if (count == 0) continue;
                best = Math.Max(best, new Rgb(r / count / 255, g / count / 255, b / count / 255).Luminance);
            }
        return best;
    }
}
