using System.Globalization;

namespace LyraLyrics.Core;

/// <summary>Couleur sRGB 0…1 (port d'ArtworkPalette.swift).</summary>
public readonly record struct Rgb(double R, double G, double B)
{
    public string Hex
    {
        get
        {
            static int C(double v) => (int)Math.Round(Math.Clamp(v, 0, 1) * 255, MidpointRounding.AwayFromZero);
            return string.Create(CultureInfo.InvariantCulture, $"#{C(R):x2}{C(G):x2}{C(B):x2}");
        }
    }

    /// <summary>Luminance relative WCAG 2.x.</summary>
    public double Luminance
    {
        get
        {
            static double Lin(double v) => v <= 0.03928 ? v / 12.92 : Math.Pow((v + 0.055) / 1.055, 2.4);
            return 0.2126 * Lin(R) + 0.7152 * Lin(G) + 0.0722 * Lin(B);
        }
    }

    public static double Contrast(Rgb a, Rgb b)
    {
        var la = a.Luminance; var lb = b.Luminance;
        return (Math.Max(la, lb) + 0.05) / (Math.Min(la, lb) + 0.05);
    }

    public Rgb Mixed(Rgb other, double t) => new(R + (other.R - R) * t, G + (other.G - G) * t, B + (other.B - B) * t);

    public (double H, double S, double V) Hsb
    {
        get
        {
            var mx = Math.Max(R, Math.Max(G, B)); var mn = Math.Min(R, Math.Min(G, B)); var d = mx - mn;
            var h = 0.0;
            if (d > 0)
            {
                if (mx == R) h = ((G - B) / d) % 6;
                else if (mx == G) h = (B - R) / d + 2;
                else h = (R - G) / d + 4;
                h /= 6;
                if (h < 0) h += 1;
            }
            return (h, mx == 0 ? 0 : d / mx, mx);
        }
    }

    public static Rgb FromHsb(double h, double s, double v)
    {
        var hh = (h - Math.Floor(h)) * 6; var c = v * s; var x = c * (1 - Math.Abs(hh % 2 - 1)); var m = v - c;
        var (r, g, b) = (int)hh switch
        {
            0 => (c, x, 0.0), 1 => (x, c, 0.0), 2 => (0.0, c, x), 3 => (0.0, x, c), 4 => (x, 0.0, c), _ => (c, 0.0, x),
        };
        return new Rgb(r + m, g + m, b + m);
    }

    internal double Distance(Rgb o) => Math.Sqrt((R - o.R) * (R - o.R) + (G - o.G) * (G - o.G) + (B - o.B) * (B - o.B));
}

/// <summary>Couleurs tirées de la pochette : dominante, secondaire, teinte de fond (sombre) et accent de la ligne courante (contraste ≥ 4,5 : 1).</summary>
public sealed class ArtworkPalette
{
    public const double MinContrast = 4.5;
    public const double MaxTintValue = 0.30;

    public Rgb Dominant { get; }
    public Rgb Secondary { get; }
    public Rgb Tint { get; }
    public Rgb Accent { get; }
    public double AccentContrast => Rgb.Contrast(Accent, Tint);

    public ArtworkPalette(Rgb dominant, Rgb secondary)
    {
        Dominant = dominant; Secondary = secondary;
        var (h, s, v) = dominant.Hsb;
        var tintV = Math.Min(Math.Max(v * 0.5, 0.14), MaxTintValue);
        Tint = Rgb.FromHsb(h, Math.Min(s, 0.75), tintV);
        var baseColor = secondary.Hsb.S >= 0.15 ? secondary : dominant;
        var (bh, bs, _) = baseColor.Hsb;
        var accent = Rgb.FromHsb(bh, Math.Min(bs, 0.55), 0.97);
        var step = 0;
        while (Rgb.Contrast(accent, Tint) < MinContrast && step < 20) { accent = accent.Mixed(new Rgb(1, 1, 1), 0.15); step++; }
        if (Rgb.Contrast(accent, Tint) < MinContrast) accent = new Rgb(1, 1, 1);
        Accent = accent;
    }

    /// <summary>Palette depuis des pixels RGBA 8 bits (non prémultipliés). Null si l'image est vide.</summary>
    public static ArtworkPalette? FromRgba(byte[] rgba, int width, int height)
    {
        if (width <= 0 || height <= 0 || rgba.Length < width * height * 4) return null;
        var count = new double[4096];
        var sum = new (double R, double G, double B)[4096];
        var total = 0.0;
        for (var i = 0; i < width * height; i++)
        {
            if (rgba[i * 4 + 3] < 32) continue;
            double r = rgba[i * 4] / 255.0, g = rgba[i * 4 + 1] / 255.0, b = rgba[i * 4 + 2] / 255.0;
            var bin = ((rgba[i * 4] >> 4) << 8) | ((rgba[i * 4 + 1] >> 4) << 4) | (rgba[i * 4 + 2] >> 4);
            count[bin]++; total++;
            sum[bin].R += r; sum[bin].G += g; sum[bin].B += b;
        }
        if (total <= 0) return null;
        var candidates = new List<(Rgb Color, double Score)>();
        for (var bin = 0; bin < 4096; bin++)
        {
            if (count[bin] <= 0) continue;
            var n = count[bin];
            var c = new Rgb(sum[bin].R / n, sum[bin].G / n, sum[bin].B / n);
            var (_, s, v) = c.Hsb;
            var weight = 0.25 + 1.75 * s;
            if (v < 0.12) weight *= 0.2;
            if (v > 0.92 && s < 0.12) weight *= 0.35;
            candidates.Add((c, n / total * weight));
        }
        // Tri stable décroissant (comme `sort` côté Swift pour des scores distincts ; égalités départagées par l'ordre des cases).
        candidates = candidates.Select((c, i) => (c, i)).OrderByDescending(x => x.c.Score).ThenBy(x => x.i).Select(x => x.c).ToList();
        var groups = new List<(Rgb Color, double Score)>();
        foreach (var c in candidates)
        {
            var k = groups.FindIndex(g => g.Color.Distance(c.Color) < 0.12);
            if (k >= 0) groups[k] = (groups[k].Color, groups[k].Score + c.Score);
            else groups.Add(c);
        }
        groups = groups.Select((c, i) => (c, i)).OrderByDescending(x => x.c.Score).ThenBy(x => x.i).Select(x => x.c).ToList();
        if (groups.Count == 0) return null;
        var dominant = groups[0].Color;
        Rgb secondary;
        var second = groups.Skip(1).Where(g => g.Color.Distance(dominant) > 0.25).Select(g => (Rgb?)g.Color).FirstOrDefault();
        if (second is { } sc) secondary = sc;
        else { var (h, s, v) = dominant.Hsb; secondary = Rgb.FromHsb(h + 0.08, Math.Min(1, s * 0.9), Math.Min(1, Math.Max(v, 0.6))); }
        return new ArtworkPalette(dominant, secondary);
    }
}
