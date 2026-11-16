using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Remplissage karaoké (S5 / S24) fait avec le PINCEAU du texte : la ligne est peinte dans sa couleur de base (atténuée) et, par-dessus, dans la couleur
/// d'accent sur une zone qui grandit de gauche à droite, ligne rendue après ligne rendue (largeurs proportionnelles, règle du Core
/// <see cref="KaraokeFill"/>). Aucune copie du texte : un seul <see cref="System.Windows.Controls.TextBlock"/>. Les zones sont animées par des horloges
/// WPF (<see cref="AnimationClock"/>) qu'on peut mettre en pause avec le reste de la Scène.
/// Non vérifié sur Windows (rendu seulement compilé).
/// </summary>
internal sealed class KaraokeBrush
{
    private readonly List<RectangleGeometry> _pieces = new();
    private readonly List<Rect> _rects;
    private readonly double[] _cumulative;
    private readonly List<AnimationClock> _clocks = new();
    public DrawingBrush Brush { get; }
    public double StartFraction { get; private set; }
    public double Duration { get; private set; }
    public bool Playing { get; private set; }
    private double _startedAt;

    /// <param name="size">Taille du bloc de texte (le pinceau est ajusté à cette zone).</param>
    /// <param name="lineRects">Un rectangle par ligne rendue ; vide = le bloc entier.</param>
    public KaraokeBrush(Size size, IReadOnlyList<Rect> lineRects, Color baseColor, Color accent)
    {
        _rects = lineRects.Count > 0 ? lineRects.ToList() : new List<Rect> { new(0, 0, size.Width, size.Height) };
        _cumulative = KaraokeFill.Cumulative(_rects.Select(r => r.Width).ToList());
        var group = new DrawingGroup();
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(baseColor), null, new RectangleGeometry(new Rect(0, 0, size.Width, size.Height))));
        var geo = new GeometryGroup();
        foreach (var r in _rects) { var g = new RectangleGeometry(new Rect(r.X, r.Y, 0, r.Height)); _pieces.Add(g); geo.Children.Add(g); }
        group.Children.Add(new GeometryDrawing(new SolidColorBrush(accent), null, geo));
        Brush = new DrawingBrush(group)
        {
            Stretch = Stretch.Fill, ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, size.Width, size.Height),
            ViewportUnits = BrushMappingMode.RelativeToBoundingBox, Viewport = new Rect(0, 0, 1, 1),
        };
    }

    /// <summary>(Re)lance le remplissage : part déjà remplie, durée totale de la ligne, lecture en cours ou figé.</summary>
    public void Set(double fraction, double duration, bool playing, bool animated)
    {
        DetachClocks();
        StartFraction = Math.Min(1, Math.Max(0, fraction)); Duration = duration; Playing = playing; _startedAt = Services.Clock.Seconds();
        for (var i = 0; i < _pieces.Count; i++)
        {
            var r = _rects[i];
            var p = KaraokeFill.Schedule(_cumulative, i, StartFraction, duration, playing, animated);
            var from = new Rect(r.X, r.Y, r.Width * p.Start, r.Height);
            _pieces[i].Rect = from;
            if (!p.Animated) continue;
            var anim = new RectAnimation(from, new Rect(r.X, r.Y, r.Width, r.Height), TimeSpan.FromSeconds(p.Duration))
            { BeginTime = TimeSpan.FromSeconds(p.Begin), FillBehavior = FillBehavior.HoldEnd };
            Timeline.SetDesiredFrameRate(anim, 30);
            var clock = (AnimationClock)anim.CreateClock(true);
            _pieces[i].ApplyAnimationClock(RectangleGeometry.RectProperty, clock);
            _clocks.Add(clock);
        }
    }

    public double Expected() => KaraokeFill.Expected(StartFraction, Duration, Playing, Services.Clock.Seconds() - _startedAt);
    public void PauseClocks() { foreach (var c in _clocks) c.Controller?.Pause(); }
    public void ResumeClocks() { foreach (var c in _clocks) c.Controller?.Resume(); }

    private void DetachClocks()
    {
        foreach (var g in _pieces) g.ApplyAnimationClock(RectangleGeometry.RectProperty, null);
        _clocks.Clear();
    }

    /// <summary>Fige le remplissage tel quel (sortie de la ligne, fermeture).</summary>
    public void Dispose() => DetachClocks();
}
