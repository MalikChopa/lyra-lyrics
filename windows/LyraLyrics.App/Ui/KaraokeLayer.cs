using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Remplissage karaoké en DEUX COUCHES (comme le Mac) : le texte d'origine reste dans sa couleur atténuée ; par-dessus, un second <see cref="TextBlock"/> identique
/// (même texte, même police, même largeur, donc même retour à la ligne) est peint dans la couleur d'accent et découpé par un <see cref="UIElement.Clip"/>
/// qui grandit de gauche à droite, ligne rendue après ligne rendue (règles pures du Core : <see cref="KaraokeFill"/>).
/// Pourquoi pas un pinceau : le remplissage précédent était un <c>DrawingBrush</c> comme <c>Foreground</c> du texte, animé par des horloges (<c>AnimationClock</c>) posées sur ses
/// géométries ; l'essai de charge en intégration continue a montré un plantage natif (0x80000003) juste après la pose de ce pinceau. Ici : AUCUNE horloge dans un pinceau
/// ou une géométrie, aucun pinceau de dessin sur le texte. Le découpage est refait À LA MAIN, par une seule minuterie de la fenêtre (≈ 30 Hz), qui appelle <see cref="Update"/>.
/// Les rectangles de ligne viennent de <see cref="TextRects.Lines"/> (repère du bloc, là où le <c>Clip</c> est exprimé) : le remplissage part de la première lettre.
/// Non vérifié sur Windows (rendu seulement compilé).
/// </summary>
internal sealed class KaraokeLayer
{
    /// <summary>Marge (DIP) ajoutée aux bords extrêmes d'une ligne pleine : les lettres qui débordent un peu (italique, crénage) restent peintes.</summary>
    public const double Overhang = KaraokeSpace.Margin;

    private readonly List<Rect> _rects;
    private readonly double[] _cumulative;
    private readonly bool _overhang;
    private double _startedAt;
    private double _lastShown = -1;

    /// <summary>La couche d'accent : à poser au-dessus du texte (même place, mêmes transformations) par l'appelant.</summary>
    public TextBlock Accent { get; }
    public double StartFraction { get; private set; }
    public double Duration { get; private set; }
    public bool Playing { get; private set; }

    /// <summary>Rectangles des lignes rendues (repère du bloc), tels que donnés à la construction.</summary>
    public IReadOnlyList<Rect> LineRects => _rects;

    /// <param name="source">Le texte d'origine (couche de base) : la couche d'accent en est la copie conforme.</param>
    /// <param name="lineRects">Un rectangle par ligne rendue ; vide = le bloc entier.</param>
    /// <param name="overhang">Vrai en fonctionnement ; faux pour le contrôle (<see cref="KaraokeProbe"/>), qui mesure le bord exact de la zone.</param>
    public KaraokeLayer(TextBlock source, IReadOnlyList<Rect> lineRects, Color accent, bool overhang = true)
    {
        var w = double.IsNaN(source.Width) ? source.ActualWidth : source.Width; var h = double.IsNaN(source.Height) ? source.ActualHeight : source.Height;
        _rects = lineRects.Count > 0 ? lineRects.ToList() : new List<Rect> { new(0, 0, w, h) };
        _cumulative = KaraokeFill.Cumulative(_rects.Select(r => r.Width).ToList());
        _overhang = overhang;
        Accent = new TextBlock
        {
            Text = source.Text, FontFamily = source.FontFamily, FontWeight = source.FontWeight, FontStyle = source.FontStyle, FontStretch = source.FontStretch,
            FontSize = source.FontSize, TextAlignment = source.TextAlignment, TextWrapping = source.TextWrapping, TextTrimming = source.TextTrimming,
            LineHeight = source.LineHeight, LineStackingStrategy = source.LineStackingStrategy, Padding = source.Padding,
            HorizontalAlignment = source.HorizontalAlignment, VerticalAlignment = source.VerticalAlignment, RenderTransformOrigin = source.RenderTransformOrigin,
            Foreground = new SolidColorBrush(accent), IsHitTestVisible = false,
            Clip = new RectangleGeometry(new Rect(0, 0, 0, 0)),
        };
        if (!double.IsNaN(source.Width)) Accent.Width = source.Width;
        if (!double.IsNaN(source.Height)) Accent.Height = source.Height;
    }

    /// <summary>Lie la couche à son texte : même opacité (par liaison, suit les animations du texte sans horloge propre) et mêmes transformations (objet partagé).</summary>
    public void Follow(TextBlock source)
    {
        Accent.RenderTransform = source.RenderTransform;
        BindingOperations.SetBinding(Accent, UIElement.OpacityProperty, new Binding("Opacity") { Source = source, Mode = BindingMode.OneWay });
    }

    /// <summary>(Re)règle le remplissage : part déjà remplie, durée totale de la ligne, lecture en cours ou figé. Met la zone à jour tout de suite.</summary>
    public void Set(double fraction, double duration, bool playing)
    {
        StartFraction = Math.Min(1, Math.Max(0, fraction)); Duration = duration; Playing = playing; _startedAt = Services.Clock.Seconds();
        _lastShown = -1;
        Update();
    }

    public double Expected() => KaraokeFill.Expected(StartFraction, Duration, Playing, Services.Clock.Seconds() - _startedAt);

    /// <summary>Remet à jour la zone découpée (appelée par la minuterie de la fenêtre) : une seule propriété posée, sans horloge.</summary>
    public void Update()
    {
        var f = Expected();
        if (_lastShown >= 0 && Math.Abs(f - _lastShown) < 0.001) return;
        _lastShown = f;
        var group = new GeometryGroup { FillRule = FillRule.Nonzero };
        for (var i = 0; i < _rects.Count; i++)
        {
            var v = KaraokeFill.Schedule(_cumulative, i, f, Duration, false, false).Start;        // part de CETTE ligne rendue pour la part totale f
            if (v <= 0) continue;
            var r = _rects[i];
            var left = r.X - (_overhang ? Overhang : 0); var right = r.X + r.Width * v + (_overhang && v >= 1 ? Overhang : 0);
            group.Children.Add(new RectangleGeometry(new Rect(left, r.Y, Math.Max(0, right - left), r.Height)));
        }
        Accent.Clip = group.Children.Count > 0 ? group : new RectangleGeometry(new Rect(0, 0, 0, 0));
    }

    /// <summary>Retire la couche de l'arbre visuel et coupe ses liaisons (sortie de la ligne, fermeture, karaoké éteint).</summary>
    public void Dispose()
    {
        BindingOperations.ClearBinding(Accent, UIElement.OpacityProperty);
        Accent.RenderTransform = Transform.Identity;
        if (Accent.Parent is Panel p) p.Children.Remove(Accent);
    }
}
