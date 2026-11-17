using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// S24 : versions réduites des effets de la Scène dans la petite fenêtre, désactivées par défaut (réglages « Fond animé » et « Remplissage karaoké »).
/// Fond animé : la pochette très floue dérive lentement derrière les paroles (cycle de 60 s), son opacité est réglée pour que le texte garde 4,5 : 1
/// (<see cref="SceneMath.MaxBackgroundLuminance"/>) ; « Réduire les animations » : image fixe ; « Réduire la transparence » : pas d'image.
/// Karaoké : la ligne courante se remplit de gauche à droite (règles du Core, <see cref="KaraokeFill"/>), aux couleurs d'accent de la pochette.
/// Le rendu n'a été que compilé : tout est « non vérifié (Windows) » (journal W6c+d).
/// </summary>
internal sealed partial class LyricsWindow
{
    private readonly Grid _driftHost = new() { IsHitTestVisible = false, Visibility = Visibility.Collapsed };
    private readonly Image _driftImage = new() { Stretch = Stretch.UniformToFill, IsHitTestVisible = false, RenderTransformOrigin = new Point(0.5, 0.5) };
    private readonly ScaleTransform _driftScale = new(1, 1);
    private readonly TranslateTransform _driftMove = new();
    private readonly List<AnimationClock> _driftClocks = new();
    private SceneArt? _driftArt;
    private int _driftArtRevision = -1;
    private string _driftKey = "";

    private KaraokeLayer? _fill;
    private SolidColorBrush? _fillBase;                  // couleur atténuée de la couche de base pendant le remplissage
    private TextBlock? _fillSlot;
    private DispatcherTimer? _fillFrame;                 // minuterie unique (≈ 30 Hz) qui met à jour À LA MAIN le découpage de la couche d'accent
    private string _fillKey = "";
    private DispatcherTimer? _fillTimer;

    private void BuildDrift()
    {
        _driftImage.RenderTransform = new TransformGroup { Children = { _driftScale, _driftMove } };
        _driftHost.Children.Add(_driftImage);
        _driftImage.HorizontalAlignment = HorizontalAlignment.Center; _driftImage.VerticalAlignment = VerticalAlignment.Center;
        _driftHost.SizeChanged += (_, _) => _driftHost.Clip = new RectangleGeometry(new Rect(0, 0, _driftHost.ActualWidth, _driftHost.ActualHeight), SystemBackdropActive ? 8 : 24, SystemBackdropActive ? 8 : 24);
    }

    private void RefreshEffects()
    {
        try { UpdateDrift(); UpdateKaraoke(); }
        catch (Exception e) { Log.WriteException("erreur", "petite fenêtre : effets", e); }
    }

    // ---- Fond animé

    private void UpdateDrift()
    {
        var s = _store.Current;
        var prefs = SystemPrefs.Current;
        var bytes = _model.ArtworkBytes;
        var wanted = s.AnimatedBackground && s.ArtworkColors && prefs.TransparencyEnabled && bytes is not null && IsVisible;
        if (!wanted) { StopDrift(); _driftHost.Visibility = Visibility.Collapsed; _driftKey = ""; return; }
        if (_driftArt is null || _driftArtRevision != _model.ArtworkRevision)
        {
            _driftArtRevision = _model.ArtworkRevision;
            try { _driftArt = SceneArt.Decode(bytes!); }
            catch (Exception e) { Log.Write("window", "pochette illisible (fond animé) : " + e.GetType().Name); _driftArt = null; _driftHost.Visibility = Visibility.Collapsed; return; }
        }
        var w = ActualWidth > 0 ? ActualWidth : Width; var h = ActualHeight > 0 ? ActualHeight : Height;
        var animate = prefs.AnimationsEnabled;
        var key = $"{_driftArtRevision}|{w:0}x{h:0}|{animate}";
        _driftHost.Visibility = Visibility.Visible;
        // opacité : le fond effectif reste assez sombre pour un texte de luminance 0,7 (blanc à ~ 70 %)
        _driftImage.Opacity = Math.Min(0.6, SceneMath.MaxBackgroundLuminance(0.7) / Math.Max(_driftArt.Luminance, 0.01));
        if (key == _driftKey) return;
        _driftKey = key;
        _driftImage.Source = _driftArt.Blurred;
        _driftImage.Width = w * 1.5; _driftImage.Height = h * 1.5;
        StopDrift();
        if (!animate) return;                                       // « Réduire les animations » : image fixe
        // dérive : échelle 1 → 1,14 et décalage ± 5 % de la largeur, aller-retour de 60 s (courbe easeInEaseOut)
        var sx = SceneAnim.PingPong(1.0, 1.14, 60); var sy = SceneAnim.PingPong(1.0, 1.14, 60); var mx = SceneAnim.PingPong(-w * 0.05, w * 0.05, 60);
        _driftScale.ApplyAnimationClock(ScaleTransform.ScaleXProperty, sx); _driftScale.ApplyAnimationClock(ScaleTransform.ScaleYProperty, sy);
        _driftMove.ApplyAnimationClock(TranslateTransform.XProperty, mx);
        _driftClocks.Add(sx); _driftClocks.Add(sy); _driftClocks.Add(mx);
    }

    private void StopDrift()
    {
        if (_driftClocks.Count == 0) return;
        _driftScale.ApplyAnimationClock(ScaleTransform.ScaleXProperty, null); _driftScale.ApplyAnimationClock(ScaleTransform.ScaleYProperty, null);
        _driftMove.ApplyAnimationClock(TranslateTransform.XProperty, null);
        _driftScale.ScaleX = _driftScale.ScaleY = 1; _driftMove.X = 0;
        _driftClocks.Clear();
    }

    // ---- Karaoké

    private void ClearFill()
    {
        _fillTimer?.Stop(); _fillFrame?.Stop();
        if (_fill is null) return;
        _fill.Dispose(); _fill = null; _fillBase = null;
        if (_fillSlot is { } slot) slot.Foreground = new SolidColorBrush(LineColor());   // la ligne reprend sa couleur unie
        _fillSlot = null; _fillKey = "";
    }

    private void UpdateKaraoke(bool snapshot = false)
    {
        var s = _store.Current;
        var animate = SystemPrefs.Current.AnimationsEnabled || snapshot;          // captures : dessiné même si le système réduit les animations
        if (!s.KaraokeFill || !animate || (!IsVisible && !snapshot) || _linesHost.Visibility != Visibility.Visible || _model.Display.Current is not DisplayState.Screen.SyncedScreen || _model.Lyrics is not { } lyrics)
        { ClearFill(); return; }
        var items = _model.LineItems(s.LineCountValue);
        var at = items.ToList().FindIndex(i => i.Offset == 0);
        if (at < 0 || at >= _slots.Count || items[at].Dim || items[at].Text.Length == 0) { ClearFill(); return; }
        var slot = _slots[at];
        var times = lyrics.Lines.Select(l => new LyricLineTime(l.Time, l.Text)).ToList();
        var spec = KaraokeFill.Compute(times, _model.CurrentIndex, _model.LyricPosition, _model.IsPlaying, true, !animate, SyncEngine.Placeholder);
        if (spec is not { } sp) { ClearFill(); return; }
        var accent = s.ArtworkColors && _model.Palette is { } p ? C(p.Accent) : LineColor();
        var key = $"{_model.TrackEpoch}|{_model.CurrentIndex}|{slot.Text}|{slot.FontSize}|{slot.ActualWidth:0}x{slot.ActualHeight:0}|{accent}|{LineColor()}";
        var rebuilt = false;
        if (_fill is null || !ReferenceEquals(slot, _fillSlot) || key != _fillKey || !ReferenceEquals(slot.Foreground, _fillBase) || !ReferenceEquals(_fill.Accent.Parent, _lines))
        {
            ClearFill();
            if (slot.ActualWidth < 1 || slot.ActualHeight < 1) return;           // pas encore mise en page : la prochaine mise à jour réessaie
            var c = LineColor();
            var rects = TextRects.Lines(slot);
            _fill = new KaraokeLayer(slot, rects, accent);
            _fillBase = new SolidColorBrush(Color.FromArgb(140, c.R, c.G, c.B));       // 0,55 : texte non rempli, comme le Mac
            slot.Foreground = _fillBase; _fillSlot = slot; _fillKey = key; rebuilt = true;
            _fill.Follow(slot);
            LinePanel.SetOverlayOf(_fill.Accent, slot);
            _lines.Children.Add(_fill.Accent);                                         // après toutes les lignes : rangé sur le rectangle de la ligne
            _lines.InvalidateMeasure();
        }
        if (rebuilt || KaraokeFill.NeedsResync(_fill.Playing, _fill.Expected(), sp.Playing, sp.Fraction)) _fill.Set(sp.Fraction, sp.Duration, snapshot ? false : sp.Playing);
        if (snapshot) return;                                                      // pas de minuterie en mode captures
        if (_fillFrame is null)
        {
            _fillFrame = new DispatcherTimer(DispatcherPriority.Render, Dispatcher) { Interval = TimeSpan.FromMilliseconds(33) };
            _fillFrame.Tick += (_, _) => { try { if (!IsVisible || _fill is null) _fillFrame?.Stop(); else _fill.Update(); } catch (Exception e) { Log.WriteException("erreur", "petite fenêtre : remplissage (minuterie)", e); _fillFrame?.Stop(); } };
        }
        if (!_fillFrame.IsEnabled) _fillFrame.Start();
        if (_fillTimer is null) { _fillTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher) { Interval = TimeSpan.FromMilliseconds(250) }; _fillTimer.Tick += (_, _) => RefreshEffects(); }
        if (!_fillTimer.IsEnabled) _fillTimer.Start();
    }

    private void StopEffects()
    {
        StopDrift();
        ClearFill();
    }

    // ---- Captures (--snapshot) : état forcé, sans minuterie

    /// <summary>Contrôle du karaoké : bords de l'encre et de la zone remplie par ligne rendue de la ligne courante (vide si pas de remplissage). À appeler après <see cref="RenderForSnapshot"/>.</summary>
    public List<KaraokeProbe.LineResult> InspectKaraoke() => _fill is { } f && _fillSlot is { } slot ? KaraokeProbe.Measure(slot, f.LineRects) : new();

    /// <summary>Mode captures : rend la fenêtre telle qu'elle est (sans l'afficher) sur un faux bureau de <paramref name="pixelWidth"/> × <paramref name="pixelHeight"/> pixels, à l'échelle <paramref name="scale"/> (1 = 96 ppp).</summary>
    public System.Windows.Media.Imaging.BitmapSource RenderForSnapshot(int pixelWidth, int pixelHeight, double scale, Color desktopTop, Color desktopBottom)
    {
        var w = Width; var h = Height;
        ApplyStyleTo();
        var root = (FrameworkElement)Content;
        for (var pass = 0; pass < 2; pass++)                        // deuxième passe : les lignes connaissent alors leur largeur
        {
            Refresh(force: true);
            root.Measure(new Size(w, h)); root.Arrange(new Rect(0, 0, w, h)); root.UpdateLayout();
        }
        if (_store.Current.KaraokeFill)                              // karaoké demandé : zone remplie figée à la part chantée, une fois les lignes mises en page
        {
            ClearFill();
            UpdateKaraoke(snapshot: true);
            root.Measure(new Size(w, h)); root.Arrange(new Rect(0, 0, w, h)); root.UpdateLayout();
        }
        var dipW = pixelWidth / scale; var dipH = pixelHeight / scale;
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            // faux bureau : dégradé et quelques formes, pour que le verre et la transparence se voient
            dc.DrawRectangle(new LinearGradientBrush(desktopTop, desktopBottom, 60), null, new Rect(0, 0, dipW, dipH));
            dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(70, 255, 200, 120)), null, new Point(dipW * 0.25, dipH * 0.55), dipH * 0.22, dipH * 0.22);
            dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(60, 120, 200, 255)), null, new Rect(dipW * 0.55, dipH * 0.50, dipW * 0.25, dipH * 0.12));
            dc.PushTransform(new TranslateTransform((dipW - w) / 2, dipH * 0.55));
            dc.DrawRectangle(new VisualBrush(root), null, new Rect(0, 0, w, h));
            dc.Pop();
        }
        var rtb = new System.Windows.Media.Imaging.RenderTargetBitmap(pixelWidth, pixelHeight, 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        rtb.Render(visual);
        rtb.Freeze();
        return rtb;
    }
}
