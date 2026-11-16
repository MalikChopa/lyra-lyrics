using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// W6c+d : finitions de la Scène. Karaoké (S5), passages sans paroles (S6), carte du titre (S14, S19), grain et vignette (S18), attente (S22),
/// barre de commandes, clavier, sortie de ligne mot à mot, pause sur un autre bureau virtuel, écran débranché. Les règles sont dans le Core
/// (<see cref="KaraokeFill"/>, <see cref="SceneGapRule"/>, <see cref="SceneCard"/>, <see cref="SceneBar"/>, <see cref="LineExit"/>, <see cref="SceneGrain"/>,
/// <see cref="SceneScreenFallback"/>), testées sur Mac ; ici seulement du dessin WPF, qu'on ne peut que COMPILER sur la machine de développement.
/// </summary>
internal sealed partial class SceneWindow
{
    // ---- Commandes de lecture (branchées par le contrôleur sur les commandes SMTC)
    public Action<PlaybackCommand>? Playback { get; set; }
    /// <summary>Appelé quand l'écran de la Scène change (débranchement, résolution) : le contrôleur met son écran à jour (zoom de sortie).</summary>
    public Action<ScreenInfo>? ScreenChanged { get; set; }

    // ---- Éléments
    private readonly TextBlock _gapNote = new() { Text = "♪", TextAlignment = TextAlignment.Center, FontFamily = new FontFamily("Segoe UI Symbol, Segoe UI"), RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new ScaleTransform(1, 1), IsHitTestVisible = false };
    private readonly List<Ellipse> _particles = new();
    private readonly Canvas _shimmer = new() { IsHitTestVisible = false, Opacity = 0, Visibility = Visibility.Collapsed };
    private readonly Rectangle _vignette = new() { IsHitTestVisible = false };
    private readonly Rectangle _grain = new() { IsHitTestVisible = false };
    private readonly Grid _barHost = new() { Opacity = 0, IsHitTestVisible = false, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top };
    private readonly Border _barPanel = new() { CornerRadius = new CornerRadius(SceneBar.Corner), Background = new SolidColorBrush(Color.FromArgb(97, 0, 0, 0)), BorderBrush = new SolidColorBrush(Color.FromArgb(66, 255, 255, 255)), BorderThickness = new Thickness(1) };
    private readonly Canvas _barCanvas = new();
    private readonly ClickableBorder _btnPrev = new() { Cursor = Cursors.Hand, CornerRadius = new CornerRadius(22), Background = Brushes.Transparent };
    private readonly ClickableBorder _btnPlay = new() { Cursor = Cursors.Hand, CornerRadius = new CornerRadius(26), Background = Brushes.Transparent };
    private readonly ClickableBorder _btnNext = new() { Cursor = Cursors.Hand, CornerRadius = new CornerRadius(22), Background = Brushes.Transparent };
    private readonly ClickableBorder _btnExit = new() { Cursor = Cursors.Hand, CornerRadius = new CornerRadius(22), Background = Brushes.Transparent };
    private readonly TextBlock _playGlyph = new() { FontFamily = IconFont, FontSize = 26, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly Rectangle _barTrack = new() { RadiusX = 2, RadiusY = 2, Fill = new SolidColorBrush(Color.FromArgb(71, 255, 255, 255)), Height = SceneBar.TrackHeight };
    private readonly Rectangle _barFill = new() { RadiusX = 2, RadiusY = 2, Fill = new SolidColorBrush(Color.FromArgb(235, 255, 255, 255)), Height = SceneBar.TrackHeight, Width = 0 };
    private readonly TextBlock _elapsedText = new() { Text = "0:00", FontSize = 13, FontWeight = FontWeights.Medium, TextAlignment = TextAlignment.Right, Foreground = new SolidColorBrush(Color.FromArgb(217, 255, 255, 255)) };
    private readonly TextBlock _totalText = new() { Text = "-:--", FontSize = 13, FontWeight = FontWeights.Medium, TextAlignment = TextAlignment.Left, Foreground = new SolidColorBrush(Color.FromArgb(217, 255, 255, 255)) };

    // ---- État
    private readonly DispatcherTimer _tick, _cloakTimer, _cardTimer;
    private readonly List<AnimationClock> _fxClocks = new();
    private IReadOnlyList<LyricLineTime> _times = Array.Empty<LyricLineTime>();
    private object? _timesSource;
    private List<SceneMath.Gap> _gaps = new();
    private string _gapsKey = "";
    private bool _gapActive, _gapMotionOn, _controlsVisible, _shimmerOn;
    private bool _cardActive, _cardPending;
    private int _cardStage;
    private Point _lastMouse = new(double.NaN, double.NaN);
    private string _shimmerKey = "";

    private bool FillEnabled => _store.Current.KaraokeFill && SystemPrefs.Current.AnimationsEnabled;

    // ================================================================ Construction

    private void BuildFxTree()
    {
        // grain et vignette (S18)
        EffectsLayer.Children.Add(_vignette); EffectsLayer.Children.Add(_grain);
        _vignette.Fill = new RadialGradientBrush(new GradientStopCollection
        {
            new(Color.FromArgb(0, 0, 0, 0), 0), new(Color.FromArgb(0, 0, 0, 0), SceneGrain.VignetteClearUntil), new(Color.FromArgb((byte)Math.Round(SceneGrain.VignetteAlpha * 255), 0, 0, 0), 1),
        }) { Center = new Point(0.5, 0.5), GradientOrigin = new Point(0.5, 0.5), RadiusX = 0.5, RadiusY = 0.5 };       // ellipse qui touche les milieux des bords ; les coins restent au noir de 34 %
        var tile = SceneGrain.Tile();
        var bmp = BitmapSource.Create(SceneGrain.Side, SceneGrain.Side, 96, 96, PixelFormats.Pbgra32, null, tile, SceneGrain.Side * 4);
        bmp.Freeze();
        var brush = new ImageBrush(bmp) { TileMode = TileMode.Tile, ViewportUnits = BrushMappingMode.Absolute, Stretch = Stretch.Fill };
        RenderOptions.SetBitmapScalingMode(brush, BitmapScalingMode.NearestNeighbor);
        _grain.Fill = brush;

        // attente (S22) et passage sans paroles (S6) vivent dans le contenu : ils s'effacent avec lui pendant la carte du titre
        _content.Children.Add(GapLayer); _content.Children.Add(_shimmer);
        GapLayer.Opacity = 0;
        GapLayer.Children.Add(_gapNote);

        BuildBar();
    }

    private void BuildBar()
    {
        _barPanel.Child = _barCanvas;
        _barHost.Children.Add(_barPanel);
        void Glyph(ClickableBorder b, string glyph, double size, string name)
        {
            b.Child = glyph.Length == 0 ? _playGlyph : new TextBlock { Text = glyph, FontFamily = IconFont, FontSize = size, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            b.MouseEnter += (_, _) => b.Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255));
            b.MouseLeave += (_, _) => b.Background = Brushes.Transparent;
            b.MouseLeftButtonDown += (_, e) => e.Handled = true;                 // pas de double-clic « quitter » depuis un bouton
            A11y.Name(b, name);
            _barCanvas.Children.Add(b);
        }
        Glyph(_btnPrev, "", 20, "Titre précédent");
        Glyph(_btnPlay, "", 26, "Lecture");
        Glyph(_btnNext, "", 20, "Titre suivant");
        Glyph(_btnExit, "", 16, "Quitter le plein écran");
        _btnPrev.Activated = () => Command(PlaybackCommand.Previous); _btnPrev.MouseLeftButtonUp += (_, e) => { Command(PlaybackCommand.Previous); e.Handled = true; };
        _btnPlay.Activated = () => Command(PlaybackCommand.PlayPause); _btnPlay.MouseLeftButtonUp += (_, e) => { Command(PlaybackCommand.PlayPause); e.Handled = true; };
        _btnNext.Activated = () => Command(PlaybackCommand.Next); _btnNext.MouseLeftButtonUp += (_, e) => { Command(PlaybackCommand.Next); e.Handled = true; };
        _btnExit.Activated = () => ExitRequested?.Invoke(); _btnExit.MouseLeftButtonUp += (_, e) => { ExitRequested?.Invoke(); e.Handled = true; };
        _playGlyph.Text = "";
        _barCanvas.Children.Add(_barTrack); _barCanvas.Children.Add(_barFill); _barCanvas.Children.Add(_elapsedText); _barCanvas.Children.Add(_totalText);
        A11y.Name(_barHost, "Commandes de lecture");
        A11y.Name(_elapsedText, "Temps écoulé"); A11y.Name(_totalText, "Durée du titre");
        A11y.Name(_barTrack, "Progression du titre");
        _barHost.MouseLeftButtonDown += (_, e) => e.Handled = true;
    }

    /// <summary>Taille et place de tout ce qui dépend de la taille de l'écran : barre, grain, vignette, note et particules.</summary>
    private void LayoutFx()
    {
        var l = SceneBar.Compute(_w, _h);
        _barHost.Width = l.Width; _barHost.Height = SceneBar.Height; _barHost.Margin = new Thickness(l.Left, l.Top, 0, 0);
        void Place(ClickableBorder b, double cx, double size) { b.Width = b.Height = size; Canvas.SetLeft(b, cx - size / 2); Canvas.SetTop(b, l.RowY - size / 2); }
        Place(_btnPrev, l.PrevX, SceneBar.ButtonSize); Place(_btnPlay, l.PlayX, SceneBar.PlaySize); Place(_btnNext, l.NextX, SceneBar.ButtonSize); Place(_btnExit, l.ExitX, SceneBar.ButtonSize);
        _barTrack.Width = l.TrackWidth; Canvas.SetLeft(_barTrack, l.TrackLeft); Canvas.SetTop(_barTrack, l.TrackTop);
        Canvas.SetLeft(_barFill, l.TrackLeft); Canvas.SetTop(_barFill, l.TrackTop);
        _elapsedText.Width = l.TimeWidth; _totalText.Width = l.TimeWidth;
        Canvas.SetLeft(_elapsedText, l.ElapsedLeft); Canvas.SetTop(_elapsedText, l.TimeTop); Canvas.SetLeft(_totalText, l.TotalLeft); Canvas.SetTop(_totalText, l.TimeTop);

        _vignette.Width = _grain.Width = _w; _vignette.Height = _grain.Height = _h;
        if (_grain.Fill is ImageBrush gb) gb.Viewport = new Rect(0, 0, SceneGrain.Side / _screen.Scale, SceneGrain.Side / _screen.Scale);   // un point du motif = un pixel de l'écran

        LayoutGap();
        if (_shimmerOn) { _shimmerKey = ""; UpdateShimmer(true); }
        UpdateBar();
    }

    // ================================================================ Cycle de vie

    private void FxStart()
    {
        _tick.Start(); _cloakTimer.Start();
        PrepareFill();
        if (_model.Track is not null && SceneCard.Allowed(_frame.WithArtwork)) StartCard("entrée");
    }

    private void FxShutdown()
    {
        _tick.Stop(); _cloakTimer.Stop(); _cardTimer.Stop(); _idleTimer.Stop();
        StopGapMotion();
        StopShimmerMotion();
        foreach (var l in _lines.Values) l.Fill?.Dispose();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
    }

    private void FxPause(bool paused)
    {
        foreach (var c in _fxClocks) { if (paused) c.Controller?.Pause(); else c.Controller?.Resume(); }
        foreach (var l in _lines.Values) { if (paused) l.Fill?.PauseClocks(); else l.Fill?.ResumeClocks(); }
        if (paused) _tick.Stop();
        else if (_started) { _tick.Start(); PrepareFill(); OnTick(); }
    }

    private readonly List<AnimationClock> _gapClocks = new();
    private void TrackGap(AnimationClock c) { _gapClocks.Add(c); TrackFx(c); }
    private void TrackFx(AnimationClock c) { _fxClocks.Add(c); if (Paused) c.Controller?.Pause(); }

    // ================================================================ Rafraîchissement

    /// <summary>Appelé à la fin de <see cref="Refresh"/> : effets, carte, attente, passage sans paroles.</summary>
    private void RefreshFx(Settings s, bool animated, bool reduce, bool epochChanged, bool layoutChanged)
    {
        // S18 : grain et vignette, fondu de 0,6 s
        var on = s.SceneEffects ? 1.0 : 0.0;
        if (_effectsTarget != on)
        {
            _effectsTarget = on;
            if (reduce || !animated) { EffectsLayer.BeginAnimation(OpacityProperty, null); EffectsLayer.Opacity = on; }
            else EffectsLayer.BeginAnimation(OpacityProperty, SceneAnim.Fade(on, SceneGrain.FadeSeconds));
        }

        // S14 : carte du titre pour chaque nouveau titre (jamais avec la pochette à gauche)
        if (layoutChanged) CancelCard();
        if (epochChanged) { if (_model.Track is not null) ScheduleCard(); else CancelCard(); }
        if (_cardPending && _model.ArtworkBytes is not null && GetArt() is not null) StartCard("pochette");

        // S22 : barres fantômes pendant la recherche
        UpdateShimmer(_model.Display.Current is DisplayState.Screen.Searching);

        // S6 : passage sans paroles
        var want = DesiredGap();
        if (want != _gapActive) { SetGap(want, false); if (HasLines) UpdateLines(animated && !_cardActive, reduce, s); }
        UpdateBar();
    }

    private double? _effectsTarget;

    // ================================================================ Minuterie de 250 ms

    private void OnTick()
    {
        if (_closed || Paused) return;
        try
        {
            var want = DesiredGap();
            if (want != _gapActive)
            {
                SetGap(want, false);
                if (HasLines) UpdateLines(!_cardActive, !SystemPrefs.Current.AnimationsEnabled, _store.Current);
            }
            SyncFill();
            if (_controlsVisible) UpdateBar();
        }
        catch (Exception e) { Log.WriteException("erreur", "scène : minuterie", e); }
    }

    // ================================================================ Karaoké (S5)

    private IReadOnlyList<LyricLineTime> LineTimes()
    {
        var lines = _model.Lyrics?.Lines;
        if (lines is null) return Array.Empty<LyricLineTime>();
        if (!ReferenceEquals(lines, _timesSource))
        {
            _timesSource = lines;
            _times = lines.Select(l => new LyricLineTime(l.Time, l.Text)).ToList();
            _gapsKey = "";
        }
        return _times;
    }

    private Color AccentColor() => _store.Current.ArtworkColors && _model.Palette is { } p ? C(p.Accent) : _textColor;

    private void DetachFill(SceneLine l)
    {
        l.Fill?.Dispose(); l.Fill = null;
        // une ligne qui vient d'être chantée garde la couleur d'accent en partant ; les autres redeviennent unies
        l.Block.Foreground = new SolidColorBrush(l.Index < _model.CurrentIndex ? AccentColor() : _textColor);
    }

    /// <summary>Remplissage de la ligne courante, de gauche à droite sur sa durée estimée (si le réglage est actif et les animations permises).</summary>
    private void PrepareFill()
    {
        try
        {
            var idx = _model.CurrentIndex;
            foreach (var l in _lines.Values) if (l.Index != idx && l.Fill is not null) DetachFill(l);
            if (!HasLines || idx < 0 || !_lines.TryGetValue(idx, out var cur)) return;
            var spec = FillEnabled
                ? KaraokeFill.Compute(LineTimes(), idx, _model.LyricPosition, _model.IsPlaying && !_gapActive, true, !SystemPrefs.Current.AnimationsEnabled, SyncEngine.Placeholder)
                : null;
            if (spec is not { } sp) { if (cur.Fill is not null) DetachFill(cur); return; }
            if (cur.Fill is null)
            {
                var rects = TextRects.Lines(cur.Block);
                var c = _textColor;
                cur.Fill = new KaraokeBrush(new Size(cur.Block.Width, cur.Block.Height), rects, Color.FromArgb(199, c.R, c.G, c.B), AccentColor());   // 0,78 : ligne nette sous le remplissage (SceneFrame.Target)
                cur.Block.Foreground = cur.Fill.Brush;
            }
            cur.Fill.Set(sp.Fraction, sp.Duration, sp.Playing, animated: true);
            if (Paused) cur.Fill.PauseClocks();
        }
        catch (Exception e) { Log.WriteException("erreur", "scène : remplissage", e); }
    }

    private void SyncFill()
    {
        var idx = _model.CurrentIndex;
        if (!HasLines || idx < 0 || !_lines.TryGetValue(idx, out var cur)) return;
        if (cur.Fill is null) { if (FillEnabled) PrepareFill(); return; }
        var spec = KaraokeFill.Compute(LineTimes(), idx, _model.LyricPosition, _model.IsPlaying && !_gapActive, FillEnabled, !SystemPrefs.Current.AnimationsEnabled, SyncEngine.Placeholder);
        if (spec is not { } sp || KaraokeFill.NeedsResync(cur.Fill.Playing, cur.Fill.Expected(), sp.Playing, sp.Fraction)) PrepareFill();
    }

    // ================================================================ Passages sans paroles (S6)

    private bool DesiredGap()
    {
        var mode = _model.Display.Current switch
        {
            DisplayState.Screen.SyncedScreen => SceneGapRule.Mode.Synced,
            DisplayState.Screen.Searching => SceneGapRule.Mode.Searching,
            DisplayState.Screen.Offline => SceneGapRule.Mode.Offline,
            DisplayState.Screen.Busy => SceneGapRule.Mode.Busy,
            _ => SceneGapRule.Mode.Other,
        };
        if (mode == SceneGapRule.Mode.Synced)
        {
            var times = LineTimes();
            var key = $"{_model.TrackEpoch}|{times.Count}|{_model.Track?.Duration ?? 0}";
            if (key != _gapsKey) { _gapsKey = key; _gaps = SceneMath.Gaps(times, SyncEngine.Placeholder, _model.Track?.Duration); }
        }
        return SceneGapRule.Wanted(mode, _model.IsPlaying || _model.IsPaused, _model.LyricPosition, _gaps);
    }

    private void LayoutGap()
    {
        var wasOn = _gapMotionOn;
        StopGapMotion();
        GapLayer.Children.Clear(); _particles.Clear();
        _gapNote.FontSize = _h * SceneGapRule.NoteSizeFraction;
        _gapNote.Width = _h * SceneGapRule.NoteWidthFraction; _gapNote.Height = _h * SceneGapRule.NoteHeightFraction;
        Canvas.SetLeft(_gapNote, _frame.TextCenterX - _h * SceneGapRule.NoteWidthFraction / 2); Canvas.SetTop(_gapNote, _h * SceneGapRule.NoteTopFraction);
        GapLayer.Children.Add(_gapNote);
        var left = _frame.TextCenterX - _frame.TextWidth / 2; var y = _h * 0.88;     // ligne d'émission : 0,12 H depuis le bas
        for (var i = 0; i < GapParticles.Budget; i++)
        {
            var p = GapParticles.At(i);
            var e = new Ellipse { Width = p.Diameter, Height = p.Diameter, Opacity = 0, IsHitTestVisible = false, RenderTransform = new TranslateTransform() };
            Canvas.SetLeft(e, left + p.XFraction * _frame.TextWidth - p.Diameter / 2); Canvas.SetTop(e, y - p.Diameter / 2);
            _particles.Add(e); GapLayer.Children.Add(e);
        }
        if (wasOn || _gapActive) StartGapMotion();
    }

    private void SetGap(bool on, bool immediate)
    {
        if (on == _gapActive && !immediate) return;
        _gapActive = on;
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        var d = immediate || reduce ? SceneGapRule.FadeQuickSeconds : SceneGapRule.FadeSeconds;
        var fade = SceneAnim.Fade(on ? 1 : 0, d);
        if (!on) fade.Completed += (_, _) => { if (!_gapActive) StopGapMotion(); };
        GapLayer.BeginAnimation(OpacityProperty, fade);
        if (on) StartGapMotion();
        else if (immediate || reduce) StopGapMotion();
        PrepareFill();                                  // le remplissage s'arrête (ou reprend) avec le passage
    }

    private void StartGapMotion()
    {
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        _gapNote.Foreground = new SolidColorBrush(AccentColor());
        if (_gapMotionOn) return;
        if (reduce) { _gapNote.Opacity = 0.75; return; }        // animations réduites : note fixe, pas de particules
        _gapMotionOn = true;
        // la note respire : échelle 0,92 → 1,08 et opacité 0,55 → 0,95 en 3,6 s, aller-retour
        var sc = (ScaleTransform)_gapNote.RenderTransform;
        var cx = SceneAnim.PingPong(SceneGapRule.BreathScaleFrom, SceneGapRule.BreathScaleTo, SceneGapRule.BreathSeconds);
        var cy = SceneAnim.PingPong(SceneGapRule.BreathScaleFrom, SceneGapRule.BreathScaleTo, SceneGapRule.BreathSeconds);
        var co = SceneAnim.PingPong(SceneGapRule.BreathOpacityFrom, SceneGapRule.BreathOpacityTo, SceneGapRule.BreathSeconds);
        sc.ApplyAnimationClock(ScaleTransform.ScaleXProperty, cx); sc.ApplyAnimationClock(ScaleTransform.ScaleYProperty, cy); _gapNote.ApplyAnimationClock(OpacityProperty, co);
        TrackGap(cx); TrackGap(cy); TrackGap(co);
        // particules lentes (au plus 30) : montent en s'estompant, naissance 3,4 / s, vie 8 s
        var tint = _store.Current.ArtworkColors && _model.Palette is { } pal ? C(pal.Secondary) : Colors.White;
        for (var i = 0; i < _particles.Count; i++)
        {
            var p = GapParticles.At(i); var e = _particles[i];
            e.Fill = new RadialGradientBrush(tint, Color.FromArgb(0, tint.R, tint.G, tint.B));
            var tr = (TranslateTransform)e.RenderTransform;
            AnimationClock Linear(double from, double to)
            {
                var a = new DoubleAnimation(from, to, TimeSpan.FromSeconds(GapParticles.Lifetime)) { BeginTime = TimeSpan.FromSeconds(p.Delay), RepeatBehavior = RepeatBehavior.Forever };
                Timeline.SetDesiredFrameRate(a, 30);
                var clock = (AnimationClock)a.CreateClock(true); TrackGap(clock); return clock;
            }
            tr.ApplyAnimationClock(TranslateTransform.XProperty, Linear(0, p.Vx * GapParticles.Lifetime));
            tr.ApplyAnimationClock(TranslateTransform.YProperty, Linear(0, p.Vy * GapParticles.Lifetime));
            e.ApplyAnimationClock(OpacityProperty, Linear(GapParticles.StartAlpha, 0));
        }
    }

    private void StopGapMotion()
    {
        if (!_gapMotionOn && _gapClocks.Count == 0) return;
        _gapMotionOn = false;
        var sc = (ScaleTransform)_gapNote.RenderTransform;
        sc.ApplyAnimationClock(ScaleTransform.ScaleXProperty, null); sc.ApplyAnimationClock(ScaleTransform.ScaleYProperty, null); _gapNote.ApplyAnimationClock(OpacityProperty, null);
        sc.ScaleX = sc.ScaleY = 1; _gapNote.Opacity = 0.75;
        foreach (var e in _particles)
        {
            var tr = (TranslateTransform)e.RenderTransform;
            tr.ApplyAnimationClock(TranslateTransform.XProperty, null); tr.ApplyAnimationClock(TranslateTransform.YProperty, null); e.ApplyAnimationClock(OpacityProperty, null);
            e.Opacity = 0;
        }
        foreach (var c in _gapClocks) _fxClocks.Remove(c);
        _gapClocks.Clear();
    }

    // ================================================================ Attente (S22)

    private void UpdateShimmer(bool searching)
    {
        if (!searching)
        {
            if (!_shimmerOn) return;
            _shimmerOn = false; _shimmerKey = "";
            StopShimmerMotion();
            _shimmer.BeginAnimation(OpacityProperty, null); _shimmer.Opacity = 0; _shimmer.Visibility = Visibility.Collapsed;
            return;
        }
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        var key = $"{_w:0}x{_h:0}|{_frame.WithArtwork}|{reduce}";
        if (_shimmerOn && key == _shimmerKey) return;
        var first = !_shimmerOn;
        _shimmerOn = true; _shimmerKey = key;
        BuildShimmer(reduce);
        _shimmer.Visibility = Visibility.Visible;
        if (first)
        {
            // apparition après 0,45 s (une recherche rapide ne montre rien), fondu de 0,6 s
            _shimmer.Opacity = 0;
            _shimmer.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(reduce ? 0.01 : ShimmerLayout.FadeSeconds)) { BeginTime = TimeSpan.FromSeconds(ShimmerLayout.DelaySeconds), FillBehavior = FillBehavior.HoldEnd });
        }
    }

    private void StopShimmerMotion()
    {
        foreach (var c in _shimmerClocks) _fxClocks.Remove(c);
        _shimmerClocks.Clear();
        if (_sweepShift is not null) _sweepShift.ApplyAnimationClock(TranslateTransform.XProperty, null);
    }

    private readonly List<AnimationClock> _shimmerClocks = new();
    private TranslateTransform? _sweepShift;

    private void BuildShimmer(bool reduce)
    {
        StopShimmerMotion();
        _shimmer.Children.Clear();
        double width = _frame.TextWidth, height = _h * 0.30, barH = _h * 0.018, spacing = _h * 0.03;
        double[] fractions = { 0.8, 0.95, 0.62 };
        _shimmer.Width = width; _shimmer.Height = height;
        Canvas.SetLeft(_shimmer, _frame.TextCenterX - width / 2); Canvas.SetTop(_shimmer, _h * 0.5 - height / 2);
        var top = (height - (fractions.Length * barH + (fractions.Length - 1) * spacing)) / 2;
        var barBrush = new SolidColorBrush(Color.FromArgb(28, 255, 255, 255));
        var mask = new DrawingGroup();
        mask.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, width, height))));
        var bars = new Canvas { Width = width, Height = height };
        for (var i = 0; i < fractions.Length; i++)
        {
            var w = width * fractions[i]; var x = (width - w) / 2; var y = top + i * (barH + spacing);
            var r = new Rectangle { Width = w, Height = barH, RadiusX = barH / 2, RadiusY = barH / 2, Fill = barBrush };
            Canvas.SetLeft(r, x); Canvas.SetTop(r, y); bars.Children.Add(r);
            mask.Children.Add(new GeometryDrawing(Brushes.White, null, new RectangleGeometry(new Rect(x, y, w, barH), barH / 2, barH / 2)));
        }
        _shimmer.Children.Add(bars);
        if (reduce) return;
        // le reflet (bande dégradée qui traverse en 1,9 s) n'est visible que sur les barres : le masque est leur forme
        var band = width * ShimmerLayout.BandFraction;
        _sweepShift = new TranslateTransform();
        var sweep = new Rectangle
        {
            Width = band, Height = height, RenderTransform = _sweepShift,
            Fill = new LinearGradientBrush(new GradientStopCollection { new(Color.FromArgb(0, 255, 255, 255), 0), new(Color.FromArgb(61, 255, 255, 255), 0.5), new(Color.FromArgb(0, 255, 255, 255), 1) }, new Point(0, 0.5), new Point(1, 0.5)),
        };
        var host = new Canvas
        {
            Width = width, Height = height, ClipToBounds = true, IsHitTestVisible = false,
            OpacityMask = new DrawingBrush(mask) { Stretch = Stretch.Fill, ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, width, height) },
        };
        host.Children.Add(sweep);
        _shimmer.Children.Add(host);
        var a = new DoubleAnimation(-band, width, TimeSpan.FromSeconds(ShimmerLayout.SweepSeconds)) { RepeatBehavior = RepeatBehavior.Forever };
        Timeline.SetDesiredFrameRate(a, 30);
        var clock = (AnimationClock)a.CreateClock(true);
        _sweepShift.ApplyAnimationClock(TranslateTransform.XProperty, clock);
        _shimmerClocks.Add(clock); TrackFx(clock);
    }

    // ================================================================ Carte du titre (S14, S19)

    private void ScheduleCard()
    {
        if (!SceneCard.Allowed(_frame.WithArtwork)) return;
        _cardPending = true;
        _cardStage = 0;
        _cardTimer.Stop(); _cardTimer.Interval = TimeSpan.FromSeconds(SceneCard.PendingDelay); _cardTimer.Start();   // la pochette peut mettre un instant à arriver
    }

    private void CancelCard()
    {
        _cardPending = false; _cardTimer.Stop();
        if (_cardActive) EndCard(immediate: true);
    }

    private void OnCardTimer()
    {
        _cardTimer.Stop();
        switch (_cardStage)
        {
            case 0: if (_cardPending) StartCard("délai"); break;
            case 1: FadeCardOut(); break;
            case 2: EndCard(immediate: false); break;
        }
    }

    private void StartCard(string why)
    {
        if (_closed || _model.Track is not { } track || !SceneCard.Allowed(_frame.WithArtwork)) return;
        Log.Write("scene", "carte du titre (" + why + ")");              // jamais le titre ni l'artiste
        _cardPending = false; _cardTimer.Stop();
        _cardActive = true;
        BuildCard(track);
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        var inD = SceneCard.InSeconds(reduce);
        var scale = (ScaleTransform)CardLayer.RenderTransform;
        CardLayer.BeginAnimation(OpacityProperty, null); CardLayer.Opacity = 0;
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, null); scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
        scale.ScaleX = scale.ScaleY = reduce ? 1 : SceneCard.StartScale;
        CardLayer.BeginAnimation(OpacityProperty, SceneAnim.Fade(1, inD));
        if (!reduce) { scale.BeginAnimation(ScaleTransform.ScaleXProperty, SceneAnim.To(1, inD)); scale.BeginAnimation(ScaleTransform.ScaleYProperty, SceneAnim.To(1, inD)); }
        _content.BeginAnimation(OpacityProperty, SceneAnim.Fade(0, inD));
        _cardStage = 1; _cardTimer.Interval = TimeSpan.FromSeconds(inD + SceneCard.Hold); _cardTimer.Start();
    }

    private void FadeCardOut()
    {
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        var outD = SceneCard.OutSeconds(reduce);
        var scale = (ScaleTransform)CardLayer.RenderTransform;
        CardLayer.BeginAnimation(OpacityProperty, SceneAnim.Fade(0, outD));
        if (!reduce) { scale.BeginAnimation(ScaleTransform.ScaleXProperty, SceneAnim.To(SceneCard.EndScale, outD)); scale.BeginAnimation(ScaleTransform.ScaleYProperty, SceneAnim.To(SceneCard.EndScale, outD)); }
        _content.BeginAnimation(OpacityProperty, SceneAnim.Fade(1, outD));
        _cardStage = 2; _cardTimer.Interval = TimeSpan.FromSeconds(outD); _cardTimer.Start();
    }

    private void EndCard(bool immediate)
    {
        _cardTimer.Stop(); _cardStage = 0;
        _cardActive = false;
        if (immediate)
        {
            CardLayer.BeginAnimation(OpacityProperty, null); CardLayer.Opacity = 0;
            _content.BeginAnimation(OpacityProperty, null); _content.Opacity = 1;
        }
        CardLayer.Children.Clear();
        _linesKey = ""; Refresh(false);                    // les lignes reprennent leur place sans animation (Mac : lastIndex = Int.min puis refresh)
    }

    private void BuildCard(TrackInfo track)
    {
        CardLayer.Children.Clear();
        var l = SceneCard.Compute(_w, _h);
        var art = GetArt();
        var tile = new Border { Width = l.Side, Height = l.Side, CornerRadius = new CornerRadius(l.ArtCorner), BorderThickness = new Thickness(1), BorderBrush = new SolidColorBrush(Color.FromArgb(31, 255, 255, 255)), IsHitTestVisible = false };
        Canvas.SetLeft(tile, l.ArtLeft); Canvas.SetTop(tile, l.ArtTop);
        if (art is not null)
        {
            tile.Background = new ImageBrush(art.Panel) { Stretch = Stretch.UniformToFill };
            CardLayer.Children.Add(tile);
            // S19 : reflet sous la pochette (bas de l'image, retourné, fondu doux, faible opacité)
            var refl = new Rectangle
            {
                Width = l.Side, Height = l.ReflectionHeight, Opacity = SceneCard.ReflectionOpacity, IsHitTestVisible = false,
                Fill = new ImageBrush(art.Panel) { Stretch = Stretch.Fill, ViewboxUnits = BrushMappingMode.RelativeToBoundingBox, Viewbox = new Rect(0, 0.72, 1, 0.28) },
                RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new ScaleTransform(1, -1),
                OpacityMask = new LinearGradientBrush(Color.FromArgb(0, 0, 0, 0), Colors.Black, new Point(0.5, 0), new Point(0.5, 1)),     // après le retournement : opaque contre la pochette, transparent vers le bas
            };
            Canvas.SetLeft(refl, l.ArtLeft); Canvas.SetTop(refl, l.ReflectionTop);
            CardLayer.Children.Add(refl);
        }
        else
        {
            tile.Background = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255));
            tile.Child = new TextBlock { Text = "♪", FontSize = l.Side * 0.42, Foreground = new SolidColorBrush(Color.FromArgb(140, 255, 255, 255)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, FontFamily = new FontFamily("Segoe UI Symbol, Segoe UI") };
            CardLayer.Children.Add(tile);
        }
        TextBlock Label(string text, double size, FontWeight weight, byte alpha, double top, double height)
        {
            var t = new TextBlock { Text = text, Width = l.TextWidth, Height = height, TextAlignment = TextAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, FontFamily = _typeface.FontFamily, FontWeight = weight, FontSize = size, Foreground = new SolidColorBrush(Color.FromArgb(alpha, 255, 255, 255)), IsHitTestVisible = false };
            Canvas.SetLeft(t, l.TextLeft); Canvas.SetTop(t, top);
            return t;
        }
        CardLayer.Children.Add(Label(track.Title, l.TitleSize, FontWeights.Bold, 255, l.TitleTop, l.TitleHeight));
        CardLayer.Children.Add(Label(track.Artist, l.ArtistSize, FontWeights.Normal, 209, l.ArtistTop, l.ArtistHeight));
    }

    // ================================================================ Barre de commandes et clavier

    private void Command(PlaybackCommand cmd)
    {
        Playback?.Invoke(cmd);
        ShowControls();
    }

    private void OnPointerMoved(object sender, MouseEventArgs e)
    {
        var p = e.GetPosition(this);
        // WPF envoie parfois un mouvement « synthétique » sans que la souris ait bougé : on ne réveille la barre que pour un vrai déplacement
        if (!double.IsNaN(_lastMouse.X) && Math.Abs(p.X - _lastMouse.X) < 1 && Math.Abs(p.Y - _lastMouse.Y) < 1) return;
        _lastMouse = p;
        ShowControls();
    }

    private void ShowControls()
    {
        if (_closed) return;
        Cursor = null;
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        var wasHidden = !_controlsVisible;
        _controlsVisible = true;
        _exitButton.IsHitTestVisible = true; _barHost.IsHitTestVisible = true;
        _exitButton.BeginAnimation(OpacityProperty, SceneAnim.Fade(1, reduce ? 0.01 : SceneBar.FadeIn));
        _barHost.BeginAnimation(OpacityProperty, SceneAnim.Fade(1, reduce ? 0.01 : SceneBar.FadeIn));
        if (wasHidden) UpdateBar();
        _idleTimer.Stop(); _idleTimer.Start();
    }

    private void HideControls()
    {
        if (_closed) return;
        // le pointeur posé sur la barre ou sur le bouton de sortie les garde affichés
        if (_exitButton.IsMouseOver || _barHost.IsMouseOver) { _idleTimer.Stop(); _idleTimer.Start(); return; }
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        _controlsVisible = false;
        _exitButton.IsHitTestVisible = false; _barHost.IsHitTestVisible = false;
        _exitButton.BeginAnimation(OpacityProperty, SceneAnim.Fade(0, reduce ? 0.01 : SceneBar.FadeOut));
        _barHost.BeginAnimation(OpacityProperty, SceneAnim.Fade(0, reduce ? 0.01 : SceneBar.FadeOut));
        Cursor = Cursors.None;                                                     // le curseur disparaît avec la barre, revient au premier mouvement
    }

    /// <summary>Temps écoulé, durée, progression et icône de lecture (toutes les 250 ms, seulement quand la barre est visible).</summary>
    private void UpdateBar()
    {
        if (_closed) return;
        var playing = _model.IsPlaying;
        var glyph = playing ? "" : "";
        if (_playGlyph.Text != glyph) { _playGlyph.Text = glyph; A11y.Name(_btnPlay, playing ? "Pause" : "Lecture"); }
        var duration = _model.Track?.Duration;
        var position = _model.Position;
        _elapsedText.Text = SceneBar.Format(position);
        _totalText.Text = SceneBar.Total(duration);
        _barFill.Width = _barTrack.Width * SceneBar.Fraction(position, duration);
    }

    /// <summary>Espace = lecture / pause, flèches = précédent / suivant, Échap = quitter.</summary>
    private bool HandleKey(Key key)
    {
        switch (key)
        {
            case Key.Escape: ExitRequested?.Invoke(); return true;
            case Key.Space: Command(PlaybackCommand.PlayPause); return true;
            case Key.Left: Command(PlaybackCommand.Previous); return true;
            case Key.Right: Command(PlaybackCommand.Next); return true;
            default: return false;
        }
    }

    // ================================================================ Sortie de ligne mot à mot (W6d)

    /// <summary>La ligne qui vient d'être chantée monte doucement, rétrécit un peu (0,92) et s'efface mot à mot (~40 ms de décalage, ~0,6 s) ; un léger flou l'accompagne.</summary>
    private void Leave(SceneLine l)
    {
        l.Leaving = true;
        var c = l.Block;
        try
        {
            l.Move.BeginAnimation(TranslateTransform.YProperty, SceneAnim.To(l.Move.Y - _h * LineExit.RiseFraction, LineExit.Duration));
            l.Scale.BeginAnimation(ScaleTransform.ScaleXProperty, SceneAnim.To(LineExit.Scale, LineExit.Duration));
            l.Scale.BeginAnimation(ScaleTransform.ScaleYProperty, SceneAnim.To(LineExit.Scale, LineExit.Duration));
            c.BeginAnimation(OpacityProperty, SceneAnim.To(0, LineExit.Duration * 0.5, LineExit.Duration * 0.5));
            var blur = new BlurEffect { Radius = 0, KernelType = KernelType.Gaussian, RenderingBias = RenderingBias.Performance };
            c.Effect = blur;
            blur.BeginAnimation(BlurEffect.RadiusProperty, SceneAnim.To(Math.Clamp(c.FontSize * 0.05, 3, 8), LineExit.Duration));
            // mot à mot : un masque dont chaque rectangle de mot s'éteint à son tour
            var words = TextRects.Words(c);
            if (words.Count == 0) words.Add(new Rect(0, 0, c.Width, c.Height));
            var plan = LineExit.For(words.Count);
            var canvas = new Canvas { Width = c.Width, Height = c.Height };
            for (var k = 0; k < words.Count; k++)
            {
                var r = words[k];
                var rect = new Rectangle { Width = r.Width + 10, Height = r.Height + 8, Fill = Brushes.Black };
                Canvas.SetLeft(rect, r.X - 5); Canvas.SetTop(rect, r.Y - 4);
                rect.BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromSeconds(plan.WordDuration))
                { BeginTime = TimeSpan.FromSeconds(k * plan.Step), EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut }, FillBehavior = FillBehavior.HoldEnd });
                canvas.Children.Add(rect);
            }
            canvas.Measure(new Size(c.Width, c.Height)); canvas.Arrange(new Rect(0, 0, c.Width, c.Height));
            c.OpacityMask = new VisualBrush(canvas) { Stretch = Stretch.None, AlignmentX = AlignmentX.Left, AlignmentY = AlignmentY.Top, ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, c.Width, c.Height), ViewportUnits = BrushMappingMode.Absolute, Viewport = new Rect(0, 0, c.Width, c.Height) };
        }
        catch (Exception e) { Log.WriteException("erreur", "scène : sortie de ligne", e); c.OpacityMask = null; c.BeginAnimation(OpacityProperty, SceneAnim.To(0, 0.6)); }
    }

    /// <summary>Une ligne qui partait redevient courante (retour en arrière dans le titre) : elle reprend l'état d'une ligne normale.</summary>
    private void Restore(SceneLine l, Settings s)
    {
        l.Leaving = false;
        l.Block.OpacityMask = null;
        l.Block.Effect = s.Glow && l.Role == 0 ? Glow(l.Block.FontSize) : null;
        l.Block.BeginAnimation(OpacityProperty, null);
    }

    private DropShadowEffect Glow(double size) => new() { Color = _textColor, BlurRadius = Math.Max(8, size / 4), ShadowDepth = 0, Opacity = 0.65 };

    // ================================================================ Autres bureaux virtuels, écrans débranchés

    private void OnCloakTimer()
    {
        if (_closed || _hwnd == IntPtr.Zero) return;
        SetPauseReason("autre bureau virtuel", Native.IsCloaked(_hwnd));
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(ReconcileScreen);

    /// <summary>Écrans branchés ou débranchés pendant la Scène : on garde le même écran s'il existe, sinon on se replie sur l'écran principal, sans exception.</summary>
    private void ReconcileScreen()
    {
        if (_closed) return;
        try
        {
            var screens = ScreenCatalog.List();
            var bounds = screens.Select(s => new SceneScreenFallback.Bounds(s.Name, s.X, s.Y, s.Width, s.Height)).ToList();
            var i = SceneScreenFallback.Reconcile(bounds, ScreenCatalog.PrimaryIndex(screens), new SceneScreenFallback.Bounds(_screen.Name, _screen.X, _screen.Y, _screen.Width, _screen.Height));
            if (i < 0) { Log.Write("scene", "écrans modifiés : aucun écran trouvé, la Scène reste en place"); return; }
            var next = screens[i];
            if (next == _screen) return;
            Log.Write("scene", $"écrans modifiés : repli sur l'écran {i + 1} sur {screens.Count} ({next.Width}x{next.Height}, échelle {next.Scale:0.##})");
            _screen = next;
            Left = next.X / next.Scale; Top = next.Y / next.Scale; Width = _w = next.DipWidth; Height = _h = next.DipHeight;
            ApplyBounds();
            _backgroundKey = ""; _layoutKey = "";
            Refresh(false);
            ScreenChanged?.Invoke(next);
        }
        catch (Exception e) { Log.WriteException("erreur", "scène : changement d'écrans", e); }
    }

    // ================================================================ Captures (--snapshot) : états forcés, sans minuterie ni animation

    public enum DemoKind { Normal, Card, Gap, Controls }

    /// <summary>Mode captures : met la Scène dans l'état voulu, immédiatement (aucune animation, aucune minuterie).</summary>
    public void ApplyDemo(DemoKind kind)
    {
        switch (kind)
        {
            case DemoKind.Card:
                if (_model.Track is { } t)
                {
                    _cardActive = true; BuildCard(t);
                    CardLayer.BeginAnimation(OpacityProperty, null); CardLayer.Opacity = 1; _content.Opacity = 0;
                }
                break;
            case DemoKind.Gap:
                _gapActive = true; _linesKey = ""; Refresh(false);
                GapLayer.Opacity = 1; _gapNote.Foreground = new SolidColorBrush(AccentColor()); _gapNote.Opacity = 0.8;
                var tint = _store.Current.ArtworkColors && _model.Palette is { } pal ? C(pal.Secondary) : Colors.White;
                for (var i = 0; i < _particles.Count; i++)           // particules figées à des âges répartis sur leur vie
                {
                    var p = GapParticles.At(i); var age = GapParticles.Lifetime * (i + 0.5) / _particles.Count; var e = _particles[i];
                    e.Fill = new RadialGradientBrush(tint, Color.FromArgb(0, tint.R, tint.G, tint.B));
                    var tr = (TranslateTransform)e.RenderTransform; tr.X = p.Vx * age; tr.Y = p.Vy * age; e.Opacity = GapParticles.OpacityAt(age);
                }
                break;
            case DemoKind.Controls:
                _controlsVisible = true; _barHost.Opacity = 1; _exitButton.Opacity = 1; UpdateBar();
                break;
        }
    }
}
