using System.Windows;
using System.Windows.Controls;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Pile de lignes de paroles : chaque ligne est mesurée à la MÊME taille puis réduite par une échelle (<see cref="FrameworkElement.Tag"/> = échelle cible),
/// comme sur le Mac ; la mise en page tient compte de la hauteur réduite. Les échelles sont animées par <c>ScaleTransform</c> (GPU).
/// </summary>
internal sealed class LinePanel : Panel
{
    public double Gap { get; set; } = 14;

    /// <summary>
    /// Calque superposé : un enfant qui porte cette propriété n'entre pas dans la pile ; il est mesuré à la même largeur et rangé EXACTEMENT sur le rectangle de la ligne
    /// donnée (même texte, mêmes lettres : karaoké en deux couches, voir <see cref="KaraokeLayer"/>). Il doit être ajouté APRÈS toutes les lignes.
    /// </summary>
    public static readonly DependencyProperty OverlayOfProperty = DependencyProperty.RegisterAttached("OverlayOf", typeof(UIElement), typeof(LinePanel));
    public static void SetOverlayOf(UIElement e, UIElement? target) => e.SetValue(OverlayOfProperty, target);
    public static UIElement? GetOverlayOf(UIElement e) => (UIElement?)e.GetValue(OverlayOfProperty);

    private static double ScaleOf(UIElement e) => e is FrameworkElement { Tag: double s } ? s : 1.0;

    protected override Size MeasureOverride(Size available)
    {
        var width = double.IsInfinity(available.Width) ? 400 : available.Width;
        var total = 0.0;
        var flow = 0;
        foreach (UIElement child in InternalChildren)
        {
            child.Measure(new Size(width, double.PositiveInfinity));
            if (GetOverlayOf(child) is not null) continue;
            total += child.DesiredSize.Height * ScaleOf(child); flow++;
        }
        if (flow > 1) total += Gap * (flow - 1);
        return new Size(width, total);
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        var total = 0.0; var flow = 0;
        foreach (UIElement child in InternalChildren) { if (GetOverlayOf(child) is not null) continue; total += child.DesiredSize.Height * ScaleOf(child); flow++; }
        if (flow > 1) total += Gap * (flow - 1);
        var y = Math.Max(0, (finalSize.Height - total) / 2);
        var placed = new Dictionary<UIElement, Rect>();
        foreach (UIElement child in InternalChildren)
        {
            if (GetOverlayOf(child) is not null) continue;
            var full = child.DesiredSize.Height;
            var shown = full * ScaleOf(child);
            var rect = new Rect(0, y - (full - shown) / 2, finalSize.Width, full);
            child.Arrange(rect); placed[child] = rect;
            y += shown + Gap;
        }
        foreach (UIElement child in InternalChildren)
            if (GetOverlayOf(child) is { } target) child.Arrange(placed.TryGetValue(target, out var r) ? r : new Rect(0, 0, 0, 0));
        return finalSize;
    }

    /// <summary>Distance entre les centres de deux lignes voisines (pour le défilement).</summary>
    public double CenterDistance(int a, int b)
    {
        if (a < 0 || b < 0 || a >= InternalChildren.Count || b >= InternalChildren.Count || GetOverlayOf(InternalChildren[a]) is not null || GetOverlayOf(InternalChildren[b]) is not null) return 0;
        var ea = InternalChildren[a]; var eb = InternalChildren[b];
        return (ea.DesiredSize.Height * ScaleOf(ea) + eb.DesiredSize.Height * ScaleOf(eb)) / 2 + Gap;
    }
}
