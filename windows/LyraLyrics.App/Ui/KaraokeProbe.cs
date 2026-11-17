using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Contrôle des captures : mesure, en PIXELS RENDUS, si la zone remplie du karaoké commence à la première lettre de chaque ligne et finit à la dernière.
/// Le bloc est peint deux fois par un <see cref="VisualBrush"/> (échelle 2) : une fois en blanc uni (l'encre de la ligne), une fois avec un pinceau karaoké dont le fond est
/// transparent et la zone remplie à 100 % (la zone remplie, vue à travers les lettres). Les bords gauche et droit de chaque ligne doivent coïncider à 1 DIP près.
/// Ni texte ni identifiant : seulement des nombres. Non vérifié sur Windows (rendu seulement compilé).
/// </summary>
internal static class KaraokeProbe
{
    private const double Scale = 2;

    public readonly record struct Edges(double Left, double Right);
    public readonly record struct LineResult(Edges Ink, Edges Filled);

    /// <summary>Un résultat par ligne rendue ; liste vide si le rendu échoue ou si le bloc n'a pas de taille.</summary>
    public static List<LineResult> Measure(TextBlock block, IReadOnlyList<Rect> lines)
    {
        var result = new List<LineResult>();
        var w = block.ActualWidth; var h = block.ActualHeight;
        if (w < 1 || h < 1 || lines.Count == 0) return result;
        var original = block.Foreground; var transform = block.RenderTransform; var opacity = block.Opacity; var effect = block.Effect;
        try
        {
            block.RenderTransform = Transform.Identity; block.Opacity = 1; block.Effect = null;       // le bloc est peint seul, à plat
            block.UpdateLayout();
            Probe();
        }
        finally { block.Foreground = original; block.RenderTransform = transform; block.Opacity = opacity; block.Effect = effect; }
        return result;

        void Probe()
        {
            var ink = Render(block, w, h, Brushes.White);
            var probe = new KaraokeBrush(new Size(w, h), lines, Colors.Transparent, Colors.White);
            probe.Set(1, 1, playing: false, animated: false);                 // figé, tout rempli
            var fill = Render(block, w, h, probe.Brush);
            foreach (var r in lines)
            {
                var a = Columns(ink, r); var b = Columns(fill, r);
                if (a is null || b is null) continue;
                result.Add(new LineResult(a.Value, b.Value));
            }
        }
    }

    /// <summary>La première ligne en défaut (bord gauche ou droit écarté de plus de 1 DIP), ou -1 si tout coïncide.</summary>
    public static int FirstMismatch(IReadOnlyList<LineResult> lines)
    {
        for (var i = 0; i < lines.Count; i++)
            if (!KaraokeSpace.EdgeMatches(lines[i].Filled.Left, lines[i].Ink.Left) || !KaraokeSpace.EdgeMatches(lines[i].Filled.Right, lines[i].Ink.Right)) return i;
        return -1;
    }

    private sealed record Pixels(byte[] Data, int Width, int Height, int Stride);

    private static Pixels Render(TextBlock block, double w, double h, Brush foreground)
    {
        block.Foreground = foreground;
        var pw = (int)Math.Ceiling(w * Scale); var ph = (int)Math.Ceiling(h * Scale);
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen()) dc.DrawRectangle(new VisualBrush(block) { Stretch = Stretch.None, AlignmentX = AlignmentX.Left, AlignmentY = AlignmentY.Top }, null, new Rect(0, 0, w, h));
        var rtb = new RenderTargetBitmap(pw, ph, 96 * Scale, 96 * Scale, PixelFormats.Pbgra32);
        visual.Transform = null;
        rtb.Render(visual);
        var stride = pw * 4; var data = new byte[stride * ph];
        rtb.CopyPixels(data, stride, 0);
        return new Pixels(data, pw, ph, stride);
    }

    /// <summary>Colonnes extrêmes (en DIP) des pixels non transparents dans la bande verticale de la ligne.</summary>
    private static Edges? Columns(Pixels p, Rect line)
    {
        var y0 = Math.Max(0, (int)Math.Floor(line.Top * Scale)); var y1 = Math.Min(p.Height - 1, (int)Math.Floor(line.Bottom * Scale) - 1);
        int left = int.MaxValue, right = -1;
        for (var y = y0; y <= y1; y++)
            for (var x = 0; x < p.Width; x++)
                if (p.Data[y * p.Stride + x * 4 + 3] >= 24) { if (x < left) left = x; if (x > right) right = x; }
        return right < 0 ? null : new Edges(left / Scale, (right + 1) / Scale);
    }
}
