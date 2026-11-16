using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Rectangles de texte d'un <see cref="TextBlock"/> déjà mis en page : un par ligne rendue (remplissage karaoké) ou un par mot (sortie de ligne mot à mot).
/// Lecture des positions de caractères (<see cref="TextPointer.GetCharacterRect"/>). Non vérifié sur Windows : en cas d'échec, une liste VIDE est renvoyée
/// et l'appelant se rabat sur le rectangle entier du bloc (le karaoké remplit alors toute la ligne d'un seul geste, la sortie fond d'un bloc).
/// </summary>
internal static class TextRects
{
    private readonly record struct Glyph(int Index, Rect Rect);

    private static List<Glyph> Glyphs(TextBlock tb)
    {
        var result = new List<Glyph>();
        try
        {
            var text = tb.Text;
            if (text.Length == 0) return result;
            tb.UpdateLayout();
            var start = tb.ContentStart.GetInsertionPosition(LogicalDirection.Forward);
            for (var i = 0; i < text.Length; i++)
            {
                if (char.IsWhiteSpace(text[i])) continue;
                var p = start.GetPositionAtOffset(i, LogicalDirection.Forward);
                if (p is null) continue;
                var r = p.GetCharacterRect(LogicalDirection.Forward);
                if (r.IsEmpty || double.IsInfinity(r.Width) || r.Height <= 0) continue;
                result.Add(new Glyph(i, r));
            }
        }
        catch (Exception e) when (e is InvalidOperationException or ArgumentException or NullReferenceException) { result.Clear(); }
        return result;
    }

    private static bool SameLine(Rect a, Rect b) => b.Top < a.Top + a.Height * 0.5 && b.Top > a.Top - a.Height * 0.5;

    /// <summary>Un rectangle par ligne rendue, de haut en bas (étendue des lettres, hauteur de la ligne).</summary>
    public static List<Rect> Lines(TextBlock tb)
    {
        var lines = new List<Rect>();
        foreach (var g in Glyphs(tb))
        {
            if (lines.Count > 0 && SameLine(lines[^1], g.Rect)) lines[^1] = Rect.Union(lines[^1], g.Rect);
            else lines.Add(g.Rect);
        }
        return lines;
    }

    /// <summary>Un rectangle par mot (un mot coupé sur deux lignes en donne un par fragment), dans l'ordre du texte.</summary>
    public static List<Rect> Words(TextBlock tb)
    {
        var words = new List<Rect>();
        Rect? current = null; var lastIndex = -2;
        foreach (var g in Glyphs(tb))
        {
            if (current is { } cur && g.Index == lastIndex + 1 && SameLine(cur, g.Rect)) current = Rect.Union(cur, g.Rect);
            else { if (current is { } done) words.Add(done); current = g.Rect; }
            lastIndex = g.Index;
        }
        if (current is { } last) words.Add(last);
        return words;
    }
}
