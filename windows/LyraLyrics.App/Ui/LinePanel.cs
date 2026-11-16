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

    private static double ScaleOf(UIElement e) => e is FrameworkElement { Tag: double s } ? s : 1.0;

    protected override Size MeasureOverride(Size available)
    {
        var width = double.IsInfinity(available.Width) ? 400 : available.Width;
        var total = 0.0;
        foreach (UIElement child in InternalChildren)
        {
            child.Measure(new Size(width, double.PositiveInfinity));
            total += child.DesiredSize.Height * ScaleOf(child);
        }
        if (InternalChildren.Count > 1) total += Gap * (InternalChildren.Count - 1);
        return new Size(width, total);
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        var total = 0.0;
        foreach (UIElement child in InternalChildren) total += child.DesiredSize.Height * ScaleOf(child);
        if (InternalChildren.Count > 1) total += Gap * (InternalChildren.Count - 1);
        var y = Math.Max(0, (finalSize.Height - total) / 2);
        foreach (UIElement child in InternalChildren)
        {
            var full = child.DesiredSize.Height;
            var shown = full * ScaleOf(child);
            child.Arrange(new Rect(0, y - (full - shown) / 2, finalSize.Width, full));
            y += shown + Gap;
        }
        return finalSize;
    }

    /// <summary>Distance entre les centres de deux lignes voisines (pour le défilement).</summary>
    public double CenterDistance(int a, int b)
    {
        if (a < 0 || b < 0 || a >= InternalChildren.Count || b >= InternalChildren.Count) return 0;
        var ea = InternalChildren[a]; var eb = InternalChildren[b];
        return (ea.DesiredSize.Height * ScaleOf(ea) + eb.DesiredSize.Height * ScaleOf(eb)) / 2 + Gap;
    }
}
