using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// La Scène (plein écran, W6b) : fenêtre sans bordure, au-dessus de tout, qui couvre l'écran choisi. Opaque (donc rendue par le processeur graphique
/// sans copie mémoire) : le zoom depuis la petite fenêtre se fait dans une fenêtre transparente séparée (<see cref="SceneZoomWindow"/>) qui anime
/// une photo de la Scène. Tous les calculs viennent du Core (<see cref="SceneFrame"/>, <see cref="SceneMath"/>, <see cref="SceneMotion"/>, testés sur Mac) ;
/// ici seulement du dessin WPF, qu'on ne peut que COMPILER sur la machine de développement.
///
/// Couches, de l'arrière vers l'avant : dégradé de la palette (qui respire) · pochette floutée (qui dérive) · voile · pochette nette + titre + artiste ·
/// lignes · bloc d'information · [points d'extension W6c+d : <see cref="GapLayer"/>, <see cref="CardLayer"/>, <see cref="EffectsLayer"/>] · bouton de sortie.
/// </summary>
internal sealed partial class SceneWindow : Window
{
    private static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    private readonly AppModel _model;
    private readonly SettingsStore _store;
    private ScreenInfo _screen;
    private IntPtr _hwnd, _powerNotification;
    private bool _closed, _started;

    public Action? ExitRequested { get; set; }

    // ---- Couches
    private readonly Grid _root = new() { Background = Brushes.Black, ClipToBounds = true };
    private readonly Rectangle _gradientRect = new() { IsHitTestVisible = false };
    private readonly GradientStop _stop0 = new(), _stop1 = new() { Offset = SceneMotion.BreathMidFrom }, _stop2 = new() { Offset = SceneMotion.BreathEndFrom };
    private readonly Canvas _artHolder = new() { IsHitTestVisible = false, ClipToBounds = true };
    private readonly Rectangle _scrim = new() { Fill = Brushes.Black, Opacity = 0.4, IsHitTestVisible = false };
    private readonly Canvas _content = new() { IsHitTestVisible = false };
    private readonly Canvas _panelLayer = new();
    private readonly Border _panelTile = new() { Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)) };
    private readonly TextBlock _panelNote = new() { Text = "♪", Foreground = new SolidColorBrush(Color.FromArgb(140, 255, 255, 255)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock _panelTitle = new() { TextTrimming = TextTrimming.CharacterEllipsis, Foreground = new SolidColorBrush(Color.FromArgb(235, 255, 255, 255)) };
    private readonly TextBlock _panelArtist = new() { TextTrimming = TextTrimming.CharacterEllipsis, Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)) };
    private readonly Canvas _linesLayer = new();
    private readonly Canvas _infoLayer = new() { Opacity = 0 };
    private readonly TextBlock _infoTitle = new() { TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Foreground = Brushes.White };
    private readonly TextBlock _infoSub = new() { TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Foreground = new SolidColorBrush(Color.FromArgb(200, 255, 255, 255)) };
    private readonly ClickableBorder _exitButton = new() { Width = 46, Height = 46, CornerRadius = new CornerRadius(23), Background = new SolidColorBrush(Color.FromArgb(110, 0, 0, 0)), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 28, 28, 0), Opacity = 0, Cursor = Cursors.Hand };

    /// <summary>Extension W6c : passages sans paroles (note ♪ et particules, S6).</summary>
    public Canvas GapLayer { get; } = new() { IsHitTestVisible = false };
    /// <summary>Extension W6c : carte du titre (S14, S19).</summary>
    public Canvas CardLayer { get; } = new() { IsHitTestVisible = false, Opacity = 0, RenderTransformOrigin = new Point(0.5, 0.5), RenderTransform = new ScaleTransform(1, 1) };
    /// <summary>Extension W6c : vignette et grain (S18, réglage « Effets de la Scène »).</summary>
    public Canvas EffectsLayer { get; } = new() { IsHitTestVisible = false };

    // ---- État
    private double _w, _h;
    private SceneFrame _frame = SceneFrame.Compute(1920, 1080, true);
    private string _layoutKey = "", _styleKey = "", _linesKey = "", _infoKey = "", _backgroundKey = "", _panelKey = "";
    private int _lastEpoch = -1;
    private Typeface _typeface = new("Segoe UI");
    private Color _textColor = Colors.White;
    private readonly Dictionary<int, SceneLine> _lines = new();
    private DriftImage? _drift;
    private SceneArt? _art;
    private int _artRevision = -1;
    private readonly List<AnimationClock> _motionClocks = new();
    private readonly HashSet<string> _pauseReasons = new();
    private readonly DispatcherTimer _idleTimer, _fpsTimer;
    private readonly FrameRateMeter _meter = new();
    private bool _rendering;

    public bool Paused => _pauseReasons.Count > 0;
    public IntPtr Hwnd => _hwnd;

    public SceneWindow(AppModel model, SettingsStore store, ScreenInfo screen)
    {
        _model = model; _store = store; _screen = screen;
        Title = AppIdentity.DisplayName;
        Icon = LyraLyrics.App.Services.AppIcon.Wpf;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        AllowsTransparency = false;
        Background = Brushes.Black;
        WindowStartupLocation = WindowStartupLocation.Manual;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        Left = screen.X / screen.Scale; Top = screen.Y / screen.Scale;
        Width = _w = screen.DipWidth; Height = _h = screen.DipHeight;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
        TextOptions.SetTextRenderingMode(this, TextRenderingMode.Grayscale);
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        A11y.Name(this, AppIdentity.DisplayName + " : Scène plein écran", "Échap ou double-clic pour quitter");
        BuildVisualTree();

        _idleTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher) { Interval = TimeSpan.FromSeconds(SceneBar.HideDelay) };
        _idleTimer.Tick += (_, _) => { _idleTimer.Stop(); HideControls(); };
        _tick = new DispatcherTimer(DispatcherPriority.Background, Dispatcher) { Interval = TimeSpan.FromMilliseconds(250) };
        _tick.Tick += (_, _) => OnTick();
        _cloakTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher) { Interval = TimeSpan.FromSeconds(1.5) };
        _cloakTimer.Tick += (_, _) => OnCloakTimer();
        _cardTimer = new DispatcherTimer(DispatcherPriority.Normal, Dispatcher);
        _cardTimer.Tick += (_, _) => OnCardTimer();
        _fpsTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher) { Interval = TimeSpan.FromSeconds(60) };
        _fpsTimer.Tick += (_, _) => LogFrameRate();

        SourceInitialized += OnSourceInitialized;
        SizeChanged += (_, e) => { if (e.NewSize.Width < 10 || e.NewSize.Height < 10) return; _w = e.NewSize.Width; _h = e.NewSize.Height; Refresh(false); };
        IsVisibleChanged += (_, _) => SetPauseReason("fenêtre masquée", !IsVisible);
        StateChanged += (_, _) => SetPauseReason("fenêtre réduite", WindowState == WindowState.Minimized);
        MouseMove += OnPointerMoved;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
        _model.Changed += OnModelChanged;
        _store.Changed += OnSettingsChanged;
        SystemPrefs.Changed += OnPrefsChanged;
        Microsoft.Win32.SystemEvents.SessionSwitch += OnSessionSwitch;
        Microsoft.Win32.SystemEvents.PowerModeChanged += OnPowerMode;
    }

    // ================================================================ Construction

    private void BuildVisualTree()
    {
        _gradientRect.Fill = new LinearGradientBrush(new GradientStopCollection { _stop0, _stop1, _stop2 }, new Point(0, 0), new Point(1, 1));   // haut-gauche vers bas-droite, comme le Mac
        var d = SceneBackdrop.DefaultColors;
        _stop0.Color = C(d[0]); _stop1.Color = C(d[1]); _stop2.Color = C(d[2]);
        _panelTile.Child = _panelNote;
        _panelTile.Effect = new DropShadowEffect { Color = Colors.Black, Opacity = 0.5, BlurRadius = 46, ShadowDepth = 12, Direction = 270 };
        _panelTile.CacheMode = new BitmapCache();                                  // une seule fois : ni ombre ni image recalculées à chaque image
        _panelLayer.Children.Add(_panelTile); _panelLayer.Children.Add(_panelTitle); _panelLayer.Children.Add(_panelArtist);
        _infoLayer.Children.Add(_infoTitle); _infoLayer.Children.Add(_infoSub);
        _content.Children.Add(_panelLayer); _content.Children.Add(_linesLayer); _content.Children.Add(_infoLayer);
        BuildFxTree();

        var glyph = new TextBlock { Text = "\uE711", FontFamily = IconFont, FontSize = 18, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        _exitButton.Child = glyph;
        _exitButton.IsHitTestVisible = false;
        _exitButton.Activated = () => ExitRequested?.Invoke();
        _exitButton.MouseLeftButtonDown += (_, e) => { e.Handled = true; ExitRequested?.Invoke(); };
        A11y.Name(_exitButton, "Quitter la Scène", "Ferme le plein écran (Échap)");

        _root.Children.Add(_gradientRect);
        _root.Children.Add(_artHolder);
        _root.Children.Add(_scrim);
        _root.Children.Add(_content);
        _root.Children.Add(CardLayer);
        _root.Children.Add(EffectsLayer);
        _root.Children.Add(_barHost);
        _root.Children.Add(_exitButton);
        Content = _root;
    }

    private static Color C(Rgb c) => Color.FromRgb((byte)Math.Round(Math.Clamp(c.R, 0, 1) * 255), (byte)Math.Round(Math.Clamp(c.G, 0, 1) * 255), (byte)Math.Round(Math.Clamp(c.B, 0, 1) * 255));
    private static FontWeight WeightOf(LyricWeight w) => w switch { LyricWeight.Light => FontWeights.Light, LyricWeight.Regular => FontWeights.Normal, LyricWeight.Semibold => FontWeights.SemiBold, _ => FontWeights.Bold };

    // ================================================================ Fenêtre Win32

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        ApplyBounds();
        if (HwndSource.FromHwnd(_hwnd) is { } src)
        {
            src.AddHook(WndProc);
            var guid = Native.GuidConsoleDisplayState;
            _powerNotification = Native.RegisterPowerSettingNotification(_hwnd, ref guid, Native.DEVICE_NOTIFY_WINDOW_HANDLE);
            if (_powerNotification == IntPtr.Zero) Log.Write("scene", "notification de veille de l'écran indisponible (la pause suit seulement le verrouillage et la mise en veille du PC)");
        }
    }

    /// <summary>Positionne la fenêtre sur l'écran, EN PIXELS (les dimensions WPF en unités logiques dépendent de l'écran où la fenêtre se trouve).</summary>
    private void ApplyBounds()
    {
        if (_hwnd == IntPtr.Zero) return;
        if (!Native.SetWindowPos(_hwnd, Native.HWND_TOPMOST, _screen.X, _screen.Y, _screen.Width, _screen.Height, 0))
            Log.Write("scene", "SetWindowPos refusé, code " + System.Runtime.InteropServices.Marshal.GetLastWin32Error());
    }

    protected override void OnDpiChanged(DpiScale oldDpi, DpiScale newDpi)
    {
        base.OnDpiChanged(oldDpi, newDpi);
        Dispatcher.BeginInvoke(ApplyBounds);                                       // WPF a pu redimensionner la fenêtre à son idée : on remet l'écran entier
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_POWERBROADCAST && wParam.ToInt64() == Native.PBT_POWERSETTINGCHANGE && lParam != IntPtr.Zero)
        {
            try
            {
                var setting = System.Runtime.InteropServices.Marshal.PtrToStructure<Native.POWERBROADCAST_SETTING>(lParam);
                if (setting.PowerSetting == Native.GuidConsoleDisplayState && setting.DataLength >= 1)
                    Dispatcher.BeginInvoke(() => SetPauseReason("écran éteint", setting.Data == 0));     // 0 éteint, 1 allumé, 2 atténué
            }
            catch (Exception ex) { Log.Write("scene", "lecture de l'état de l'écran impossible : " + ex.GetType().Name); }
        }
        return IntPtr.Zero;
    }

    private void OnSessionSwitch(object? sender, Microsoft.Win32.SessionSwitchEventArgs e)
    {
        if (e.Reason == Microsoft.Win32.SessionSwitchReason.SessionLock) Dispatcher.BeginInvoke(() => SetPauseReason("session verrouillée", true));
        else if (e.Reason == Microsoft.Win32.SessionSwitchReason.SessionUnlock) Dispatcher.BeginInvoke(() => SetPauseReason("session verrouillée", false));
    }

    private void OnPowerMode(object? sender, Microsoft.Win32.PowerModeChangedEventArgs e)
    {
        if (e.Mode == Microsoft.Win32.PowerModes.Suspend) Dispatcher.BeginInvoke(() => SetPauseReason("mise en veille", true));
        else if (e.Mode == Microsoft.Win32.PowerModes.Resume) Dispatcher.BeginInvoke(() => { SetPauseReason("mise en veille", false); Native.BringToTopmost(_hwnd); });
    }

    // ================================================================ Entrées clavier et souris

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.IsRepeat) { e.Handled = true; return; }                  // une touche maintenue n'envoie qu'une commande
        if (HandleKey(e.Key)) e.Handled = true;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnMouseLeftButtonDown(e);
        ShowControls();
        if (e.ClickCount >= 2) { e.Handled = true; ExitRequested?.Invoke(); }
    }

    // ================================================================ Cycle de vie

    /// <summary>Met la Scène en route : mouvements du fond, mesure de la cadence. Appelé par le contrôleur quand elle est affichée.</summary>
    public void Start()
    {
        if (_started || _closed) return;
        _started = true;
        _meter.TakeFps(LyraLyrics.App.Services.Clock.Seconds());
        UpdateMotion();
        if (!Paused) StartRendering();
        _fpsTimer.Start();
        ShowControls();
        FxStart();
        Activate(); Focus();
    }

    /// <summary>Calcule la mise en page à la taille de l'écran sans afficher la fenêtre (pour la photo du zoom).</summary>
    public void Prepare()
    {
        _w = _screen.DipWidth; _h = _screen.DipHeight;
        Refresh(false);
        _root.Measure(new Size(_w, _h));
        _root.Arrange(new Rect(0, 0, _w, _h));
        _root.UpdateLayout();
    }

    /// <summary>
    /// Photo de la Scène à la résolution de l'écran (en pixels). La mise en page est TOUJOURS refaite avant le rendu : <see cref="RenderTargetBitmap"/> ne la lance pas, et
    /// ajouter des enfants à un Canvas ne marque pas la racine comme invalide (<c>IsArrangeValid</c> reste vrai) ; l'ancien test « seulement si invalide » sautait donc la
    /// mise en page des enfants ajoutés après <see cref="Prepare"/> (cause de la carte du titre absente sur les captures de la CI 1.3.0).
    /// </summary>
    public BitmapSource Snapshot()
    {
        var pw = Math.Max(1, (int)Math.Round(_w * _screen.Scale)); var ph = Math.Max(1, (int)Math.Round(_h * _screen.Scale));
        InvalidateTree(_root);
        _root.Measure(new Size(_w, _h));
        _root.Arrange(new Rect(0, 0, _w, _h));
        _root.UpdateLayout();
        var rtb = new RenderTargetBitmap(pw, ph, 96 * _screen.Scale, 96 * _screen.Scale, PixelFormats.Pbgra32);
        rtb.Render(_root);
        rtb.Freeze();
        return rtb;
    }

    private static void InvalidateTree(DependencyObject node)
    {
        if (node is UIElement ui) { ui.InvalidateMeasure(); ui.InvalidateArrange(); }
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++) InvalidateTree(VisualTreeHelper.GetChild(node, i));
    }

    /// <summary>Contrôle des captures : nombre d'éléments réellement visibles (taille mise en page non nulle, visibilité, opacité cumulée) dans la carte et dans les lignes. Aucun texte.</summary>
    public readonly record struct SnapshotStats(int CardVisible, int CardTotal, int LinesVisible, int CurrentLinesVisible);

    public SnapshotStats Inspect()
    {
        bool Shown(UIElement e)
        {
            if (e.RenderSize.Width < 1 || e.RenderSize.Height < 1) return false;
            double op = 1;
            for (DependencyObject? n = e; n is not null && !ReferenceEquals(n, _root); n = VisualTreeHelper.GetParent(n))
                if (n is UIElement u) { if (u.Visibility != Visibility.Visible) return false; op *= u.Opacity; }
            return op * _root.Opacity > 0.05;
        }
        var shownCard = CardLayer.Children.OfType<UIElement>().Count(e => Shown(CardLayer) && Shown(e));
        var lines = _lines.Values.Where(l => Shown(l.Block)).ToList();
        return new SnapshotStats(shownCard, CardLayer.Children.Count, lines.Count, lines.Count(l => l.Role == 0));
    }

    public void Shutdown()
    {
        if (_closed) return;
        _closed = true;
        _model.Changed -= OnModelChanged;
        _store.Changed -= OnSettingsChanged;
        SystemPrefs.Changed -= OnPrefsChanged;
        Microsoft.Win32.SystemEvents.SessionSwitch -= OnSessionSwitch;
        Microsoft.Win32.SystemEvents.PowerModeChanged -= OnPowerMode;
        StopRendering();
        _fpsTimer.Stop();
        FxShutdown();
        StopMotion();
        if (_powerNotification != IntPtr.Zero) { Native.UnregisterPowerSettingNotification(_powerNotification); _powerNotification = IntPtr.Zero; }
        if (_hwnd != IntPtr.Zero && HwndSource.FromHwnd(_hwnd) is { } src) src.RemoveHook(WndProc);
        Close();
    }

    // ---- Pause des animations (fenêtre masquée ou réduite, écran éteint, session verrouillée, mise en veille)

    private void SetPauseReason(string reason, bool on)
    {
        if (_closed) return;
        var was = Paused;
        if (on) _pauseReasons.Add(reason); else _pauseReasons.Remove(reason);
        if (Paused == was) return;
        foreach (var c in _motionClocks) { if (Paused) c.Controller?.Pause(); else c.Controller?.Resume(); }
        FxPause(Paused);
        if (Paused) { StopRendering(); _fpsTimer.Stop(); }
        else if (_started) { StartRendering(); _fpsTimer.Start(); _meter.TakeFps(LyraLyrics.App.Services.Clock.Seconds()); }
        Log.Write("scene", Paused ? "animations en pause (" + reason + ")" : "animations reprises");
    }

    private void StartRendering() { if (_rendering) return; _rendering = true; CompositionTarget.Rendering += OnRendering; }
    private void StopRendering() { if (!_rendering) return; _rendering = false; CompositionTarget.Rendering -= OnRendering; }
    private void OnRendering(object? sender, EventArgs e) => _meter.Frame(LyraLyrics.App.Services.Clock.Seconds());

    private void LogFrameRate()
    {
        if (_meter.TakeFps(LyraLyrics.App.Services.Clock.Seconds()) is { } fps)
            Log.Write("scene", $"cadence ≈ {fps:0.0} images/s (événements de rendu WPF en 60 s ; le fond bouge à 30 images/s au plus)");
    }

    // ================================================================ Rafraîchissement

    private void OnModelChanged() { if (!_closed) Refresh(true); }
    private void OnSettingsChanged() { if (!_closed) Refresh(false); }
    private void OnPrefsChanged() { if (_closed) return; _backgroundKey = ""; Refresh(false); }

    private bool HasLines => _model.Display.Current is DisplayState.Screen.SyncedScreen && _model.Lyrics is { IsSynced: true, Lines.Count: > 0 };

    /// <summary>Remet la Scène d'aplomb avec l'état du modèle ; ne refait que ce qui a changé.</summary>
    public void Refresh(bool animated)
    {
        if (_closed || _w < 10 || _h < 10) return;
        var s = _store.Current;
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        var withArt = s.SceneLayout == SceneLayoutMode.WithArtwork;

        var layoutKey = $"{_w:0.##}x{_h:0.##}|{withArt}";
        var layoutChanged = layoutKey != _layoutKey;
        if (layoutChanged)
        {
            _layoutKey = layoutKey;
            _frame = SceneFrame.Compute(_w, _h, withArt);
            ClearLines(); _linesKey = ""; _backgroundKey = ""; _infoKey = ""; _panelKey = "";
            animated = false;
        }
        var color = (Color)ColorConverter.ConvertFromString(LineColorRule.TextHex(s.ColorHex, s.ArtworkColors, _model.Palette?.Accent.Hex));
        var styleKey = $"{color}|{s.Font}|{s.FontWeight}|{s.Glow}|{FillEnabled}|{AccentColor()}";
        var styleChanged = styleKey != _styleKey;
        if (styleChanged)
        {
            _styleKey = styleKey; _textColor = color;
            _typeface = new Typeface(new FontFamily(s.Font.Family()), FontStyles.Normal, WeightOf(s.FontWeight), FontStretches.Normal);
            ClearLines(); _linesKey = ""; _infoKey = ""; _panelKey = ""; _backgroundKey = "";
            animated = false;
        }
        if (layoutChanged || styleChanged) ApplyStaticLayout();
        var epochChanged = _model.TrackEpoch != _lastEpoch;
        if (epochChanged) { _lastEpoch = _model.TrackEpoch; ClearLines(); _linesKey = ""; }

        UpdateArtPanel(animated && !reduce, withArt);
        UpdateBackground(animated, reduce, s);
        var searching = _model.Display.Current is DisplayState.Screen.Searching;
        if (HasLines) { UpdateLines(animated && !_cardActive, reduce, s); SetInfoVisible(false, animated && !reduce); }
        else { ClearLines(); _linesKey = ""; UpdateInfo(); SetInfoVisible(!searching, animated && !reduce); }   // recherche : barres fantômes (S22), pas de texte
        UpdateMotion();
        RefreshFx(s, animated, reduce, epochChanged, layoutChanged);
    }

    /// <summary>Position et taille des éléments qui ne dépendent que de la mise en page : pochette, titre, artiste, bloc d'information.</summary>
    private void ApplyStaticLayout()
    {
        var f = _frame;
        _panelLayer.Visibility = f.WithArtwork ? Visibility.Visible : Visibility.Collapsed;
        _panelTile.Width = _panelTile.Height = f.ArtSide; _panelTile.CornerRadius = new CornerRadius(f.ArtCorner);
        Canvas.SetLeft(_panelTile, f.ArtLeft); Canvas.SetTop(_panelTile, f.ArtTop);
        _panelNote.FontSize = f.ArtSide * 0.4;
        _panelTitle.Width = _panelArtist.Width = f.ArtSide;
        _panelTitle.FontFamily = _panelArtist.FontFamily = _typeface.FontFamily;
        _panelTitle.FontWeight = _typeface.Weight; _panelArtist.FontWeight = FontWeights.Normal;
        _panelTitle.FontSize = f.TitleSize; _panelArtist.FontSize = f.ArtistSize;
        Canvas.SetLeft(_panelTitle, f.ArtLeft); Canvas.SetTop(_panelTitle, f.TitleTop);
        Canvas.SetLeft(_panelArtist, f.ArtLeft); Canvas.SetTop(_panelArtist, f.ArtistTop);

        _infoTitle.Width = _infoSub.Width = f.TextWidth;
        _infoTitle.FontFamily = _typeface.FontFamily; _infoTitle.FontWeight = _typeface.Weight; _infoTitle.FontSize = f.InfoTitleSize;
        _infoSub.FontFamily = _typeface.FontFamily; _infoSub.FontWeight = FontWeights.Normal; _infoSub.FontSize = f.InfoSubSize;
        Canvas.SetLeft(_infoTitle, f.TextCenterX - f.TextWidth / 2); Canvas.SetTop(_infoTitle, f.InfoTitleTop);
        Canvas.SetLeft(_infoSub, f.TextCenterX - f.TextWidth / 2); Canvas.SetTop(_infoSub, f.InfoSubTop);
        LayoutFx();
    }

    // ---------------------------------------------------------------- Pochette nette, titre, artiste

    private void UpdateArtPanel(bool animated, bool withArt)
    {
        if (!withArt) return;
        var track = _model.Track;
        _panelTitle.Text = track?.Title ?? "";
        _panelArtist.Text = track?.Artist ?? "";
        var art = GetArt();
        var key = $"{_model.TrackEpoch}|{_model.ArtworkRevision}|{art is not null}";
        if (key == _panelKey) return;
        _panelKey = key;
        if (art is null) { _panelTile.Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)); _panelNote.Visibility = Visibility.Visible; return; }
        _panelTile.Background = new ImageBrush(art.Panel) { Stretch = Stretch.UniformToFill };
        _panelNote.Visibility = Visibility.Collapsed;
        if (animated) _panelTile.BeginAnimation(OpacityProperty, SceneAnim.Fade(1, 0.8, 0));
    }

    // ---------------------------------------------------------------- Fond (S1)

    /// <summary>Pochette décodée (en mémoire seulement), refaite quand une nouvelle pochette arrive ; null sans pochette pour le titre en cours.</summary>
    private SceneArt? GetArt()
    {
        var bytes = _model.ArtworkBytes;
        if (bytes is null) { _art = null; _artRevision = -1; return null; }
        if (_artRevision == _model.ArtworkRevision && _art is not null) return _art;
        _artRevision = _model.ArtworkRevision;
        try { _art = SceneArt.Decode(bytes); }
        catch (Exception e) { Log.Write("scene", "pochette illisible : " + e.GetType().Name); _art = null; }
        return _art;
    }

    private void UpdateBackground(bool animated, bool reduce, Settings s)
    {
        var prefs = SystemPrefs.Current;
        var palette = s.ArtworkColors ? _model.Palette : null;
        var art = s.ArtworkColors && prefs.TransparencyEnabled ? GetArt() : null;     // « Réduire la transparence » : fond plein, sans image
        var key = $"{_model.TrackEpoch}|{_model.ArtworkRevision}|{palette?.Dominant.Hex}|{art is not null}|{_textColor}|{reduce}|{_layoutKey}";
        if (key == _backgroundKey) return;
        var firstTime = _backgroundKey.Length == 0;
        _backgroundKey = key;
        var smooth = animated && !reduce && !firstTime;

        // dégradé de la palette (ou neutre)
        var colors = SceneBackdrop.GradientColors(palette);
        foreach (var (stop, rgb) in new[] { (_stop0, colors[0]), (_stop1, colors[1]), (_stop2, colors[2]) })
        {
            if (smooth) stop.BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(C(rgb), TimeSpan.FromSeconds(1.4)) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut } });
            else { stop.BeginAnimation(GradientStop.ColorProperty, null); stop.Color = C(rgb); }
        }

        // pochette floutée : fondu enchaîné avec la précédente
        if (art is not null) SwapArtImage(art, smooth, reduce);
        else if (_drift is { } old)
        {
            _drift = null;
            FadeOutAndRemove(old, smooth ? 1.0 : 0.01);
        }

        // fond effectif réglé pour que le texte garde 4,5 : 1 au moins (Core : SceneMath.Background, prouvé par les fixtures)
        var textLum = SceneBackdrop.TextLuminance(new Rgb(_textColor.R / 255.0, _textColor.G / 255.0, _textColor.B / 255.0).Luminance, 1, false);
        var balance = SceneMath.Background(art?.Luminance ?? 0, SceneBackdrop.GradientLuminance(palette), textLum);
        var dur = smooth ? 1.0 : 0;
        if (dur > 0) _scrim.BeginAnimation(OpacityProperty, SceneAnim.Fade(balance.Scrim, dur));
        else { _scrim.BeginAnimation(OpacityProperty, null); _scrim.Opacity = balance.Scrim; }
        if (_drift is { } d)
        {
            d.TargetOpacity = art is null ? 0 : balance.ArtOpacity;
            if (dur > 0) d.Image.BeginAnimation(OpacityProperty, SceneAnim.Fade(d.TargetOpacity, 1.4));
            else { d.Image.BeginAnimation(OpacityProperty, null); d.Image.Opacity = d.TargetOpacity; }
        }
    }

    private void SwapArtImage(SceneArt art, bool smooth, bool reduce)
    {
        var old = _drift;
        var image = new Image { Source = art.Blurred, Stretch = Stretch.UniformToFill, Width = _w * 1.45, Height = _h * 1.45, Opacity = 0, IsHitTestVisible = false, RenderTransformOrigin = new Point(0.5, 0.5) };
        var scale = new ScaleTransform(1, 1); var move = new TranslateTransform();
        image.RenderTransform = new TransformGroup { Children = { scale, move } };
        Canvas.SetLeft(image, _w / 2 - _w * 1.45 / 2); Canvas.SetTop(image, _h / 2 - _h * 1.45 / 2);
        _artHolder.Children.Add(image);
        _drift = new DriftImage(image, scale, move);
        if (old is not null) FadeOutAndRemove(old, smooth ? 1.4 : 0.01);
        StartDrift(_drift);
        // le fondu d'entrée est lancé par UpdateBackground (opacité cible = réglage du voile)
    }

    private void FadeOutAndRemove(DriftImage d, double seconds)
    {
        foreach (var c in d.Clocks) _motionClocks.Remove(c);
        var anim = SceneAnim.Fade(0, seconds);
        anim.Completed += (_, _) => _artHolder.Children.Remove(d.Image);
        d.Image.BeginAnimation(OpacityProperty, anim);
    }

    // ---- Mouvements lents : dérive de la pochette, respiration du dégradé (valeurs de SceneMotion, prouvées par fixture)

    private void UpdateMotion()
    {
        var reduce = !SystemPrefs.Current.AnimationsEnabled;
        if (reduce || _closed) { StopMotion(); return; }
        if (_motionClocks.Count == 0 && _started) { StartBreath(); if (_drift is { } d && d.Clocks.Count == 0) StartDrift(d); }
    }

    private void StartBreath()
    {
        var a = SceneMotion.BreathAt(0); var b = SceneMotion.BreathAt(SceneMotion.BreathLeg);
        var c1 = SceneAnim.PingPong(a.Mid, b.Mid, SceneMotion.BreathLeg); var c2 = SceneAnim.PingPong(a.End, b.End, SceneMotion.BreathLeg);
        _stop1.ApplyAnimationClock(GradientStop.OffsetProperty, c1); _stop2.ApplyAnimationClock(GradientStop.OffsetProperty, c2);
        Track(c1); Track(c2);
    }

    private void StartDrift(DriftImage d)
    {
        if (!_started || !SystemPrefs.Current.AnimationsEnabled) return;
        var a = SceneMotion.DriftAt(0, _w, _h); var b = SceneMotion.DriftAt(SceneMotion.DriftLeg, _w, _h);
        d.Clocks.Clear();
        var sx = SceneAnim.PingPong(a.Scale, b.Scale, SceneMotion.DriftLeg); var sy = SceneAnim.PingPong(a.Scale, b.Scale, SceneMotion.DriftLeg);
        var mx = SceneAnim.PingPong(a.Dx, b.Dx, SceneMotion.DriftLeg); var my = SceneAnim.PingPong(a.Dy, b.Dy, SceneMotion.DriftLeg);
        d.Scale.ApplyAnimationClock(ScaleTransform.ScaleXProperty, sx); d.Scale.ApplyAnimationClock(ScaleTransform.ScaleYProperty, sy);
        d.Move.ApplyAnimationClock(TranslateTransform.XProperty, mx); d.Move.ApplyAnimationClock(TranslateTransform.YProperty, my);
        foreach (var c in new[] { sx, sy, mx, my }) { d.Clocks.Add(c); Track(c); }
    }

    private void Track(AnimationClock c) { _motionClocks.Add(c); if (Paused) c.Controller?.Pause(); }

    private void StopMotion()
    {
        if (_motionClocks.Count == 0) return;
        _stop1.ApplyAnimationClock(GradientStop.OffsetProperty, null); _stop2.ApplyAnimationClock(GradientStop.OffsetProperty, null);
        _stop1.Offset = SceneMotion.BreathMidFrom; _stop2.Offset = SceneMotion.BreathEndFrom;
        if (_drift is { } d)
        {
            d.Scale.ApplyAnimationClock(ScaleTransform.ScaleXProperty, null); d.Scale.ApplyAnimationClock(ScaleTransform.ScaleYProperty, null);
            d.Move.ApplyAnimationClock(TranslateTransform.XProperty, null); d.Move.ApplyAnimationClock(TranslateTransform.YProperty, null);
            d.Clocks.Clear();
        }
        _motionClocks.Clear();
    }

    // ---------------------------------------------------------------- Lignes (S4)

    private sealed class SceneLine
    {
        public int Index, Role;
        public double LayoutHeight;
        public TextBlock Block = null!;
        public ScaleTransform Scale = new(1, 1);
        public TranslateTransform Move = new();
        public bool Leaving;
        public KaraokeBrush? Fill;
    }

    private double MeasureHeight(string text, double size, double width)
    {
        var ft = new FormattedText(text.Length == 0 ? " " : text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, _typeface, size, Brushes.White,
            VisualTreeHelper.GetDpi(this).PixelsPerDip) { MaxTextWidth = Math.Max(1, width), TextAlignment = TextAlignment.Center };
        return ft.Height;
    }

    private SceneLine MakeLine(int index, int role, string text, Settings s)
    {
        var width = _frame.LayoutWidth(role);
        var size = _frame.FitSize(text, role, MeasureHeight);
        var h = MeasureHeight(text, size, width);
        var line = new SceneLine { Index = index, Role = role, LayoutHeight = h };
        line.Block = new TextBlock
        {
            Text = text, Width = width, Height = h, TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center,
            FontFamily = _typeface.FontFamily, FontWeight = _typeface.Weight, FontSize = size, Foreground = new SolidColorBrush(_textColor),
            RenderTransformOrigin = new Point(0.5, 0.5), IsHitTestVisible = false, Opacity = 0,
            RenderTransform = new TransformGroup { Children = { line.Scale, line.Move } },
        };
        if (s.Glow && role == 0 && !FillEnabled) line.Block.Effect = Glow(size);     // pendant le remplissage la lettre est nette, sans lueur (Mac)
        Canvas.SetLeft(line.Block, _frame.TextCenterX - width / 2);
        Canvas.SetTop(line.Block, -h / 2);                 // le centre de la ligne est à l'ordonnée 0 : la place vient de la translation verticale
        _linesLayer.Children.Add(line.Block);
        return line;
    }

    private void ClearLines()
    {
        foreach (var l in _lines.Values) { l.Fill?.Dispose(); l.Block.BeginAnimation(OpacityProperty, null); _linesLayer.Children.Remove(l.Block); }
        _lines.Clear();
        _linesLayer.Children.Clear();
    }

    private static void SetNow(IAnimatable target, DependencyProperty p, double value)
    {
        target.BeginAnimation(p, null);
        ((DependencyObject)target).SetValue(p, value);
    }

    private void Place(SceneLine l, SceneFrame.LineTarget t, bool animated, bool reduce)
    {
        var dur = reduce ? 0.3 : 0.9;
        if (!animated)
        {
            SetNow(l.Move, TranslateTransform.YProperty, t.Y);
            SetNow(l.Scale, ScaleTransform.ScaleXProperty, t.Scale); SetNow(l.Scale, ScaleTransform.ScaleYProperty, t.Scale);
            SetNow(l.Block, OpacityProperty, t.Opacity);
            return;
        }
        if (reduce)       // « Réduire les animations » : la ligne fond sur place, sans mouvement
        {
            SetNow(l.Move, TranslateTransform.YProperty, t.Y);
            SetNow(l.Scale, ScaleTransform.ScaleXProperty, t.Scale); SetNow(l.Scale, ScaleTransform.ScaleYProperty, t.Scale);
        }
        else
        {
            l.Move.BeginAnimation(TranslateTransform.YProperty, SceneAnim.To(t.Y, dur));
            l.Scale.BeginAnimation(ScaleTransform.ScaleXProperty, SceneAnim.To(t.Scale, dur));
            l.Scale.BeginAnimation(ScaleTransform.ScaleYProperty, SceneAnim.To(t.Scale, dur));
        }
        l.Block.BeginAnimation(OpacityProperty, SceneAnim.To(t.Opacity, dur));
    }

    private void UpdateLines(bool animated, bool reduce, Settings s)
    {
        var lines = _model.Lyrics!.Lines;
        var idx = _model.CurrentIndex;
        var key = $"{_model.TrackEpoch}|{idx}|{lines.Count}|{_layoutKey}|{_styleKey}|{reduce}|{_gapActive}";
        if (key == _linesKey) return;
        _linesKey = key;
        var wanted = Enumerable.Range(idx - 1, 4).Where(i => i >= 0 && i < lines.Count).ToHashSet();

        // lignes qui sortent de la fenêtre de 4 lignes : elles s'effacent (la ligne qui vient de partir a déjà quitté la scène mot à mot, voir Leave)
        foreach (var i in _lines.Keys.Where(i => !wanted.Contains(i)).ToList())
        {
            var l = _lines[i]; _lines.Remove(i);
            RetireLine(l, animated);
        }

        var starts = new Dictionary<int, (double Y, double Scale)>();
        var ghosts = new List<(SceneLine Ghost, int Index)>();
        foreach (var i in wanted.OrderBy(i => i))
        {
            var off = i - idx; var role = SceneFrame.Role(off);
            if (_lines.TryGetValue(i, out var old))
            {
                if (off < 0 || old.Role == role) continue;
                // la ligne change de rôle (suivante -> courante...) : nouvelle mise en page, fondu enchaîné avec l'ancienne qui rejoint la même place
                var nl = MakeLine(i, role, lines[i].Text, s);
                SetNow(nl.Move, TranslateTransform.YProperty, old.Move.Y);
                SetNow(nl.Scale, ScaleTransform.ScaleXProperty, old.Scale.ScaleX); SetNow(nl.Scale, ScaleTransform.ScaleYProperty, old.Scale.ScaleX);
                SetNow(nl.Block, OpacityProperty, 0);
                _lines[i] = nl;
                ghosts.Add((old, i));
            }
            else
            {
                var nl = MakeLine(i, role, lines[i].Text, s);
                _lines[i] = nl;
                starts[i] = (0, 0);              // arrivée : un peu plus bas, transparente (placée plus loin, une fois les hauteurs connues)
            }
        }

        // places (les hauteurs de mise en page sont connues)
        var hCur = idx >= 0 && _lines.TryGetValue(idx, out var cur) ? cur.LayoutHeight : _h * 0.1;
        var hNext = _lines.TryGetValue(idx + 1, out var nx) ? nx.LayoutHeight : 0;
        var leavers = new List<SceneLine>();
        foreach (var (i, l) in _lines)
        {
            var off = i - idx;
            // la ligne qui vient d'être chantée part mot à mot (W6d) ; pas pendant la carte du titre ni avec « Réduire les animations »
            if (off == -1 && l.Role == 0 && !l.Leaving && animated && !reduce && !_cardActive && l.Block.Opacity > 0.5) { leavers.Add(l); continue; }
            if (off == -1 && l.Leaving) continue;                          // déjà en train de partir
            if (off != -1 && l.Leaving) Restore(l, s);                     // redevenue courante (retour en arrière) : remise en place
            var t = _frame.Target(off, hCur, hNext, l.LayoutHeight, FillEnabled);
            if (off == 0 && _gapActive) t = t with { Opacity = 0 };        // pendant un passage sans paroles la courante s'efface (S6)
            if (starts.ContainsKey(i))
            {
                SetNow(l.Move, TranslateTransform.YProperty, t.Y + _h * 0.04);
                SetNow(l.Scale, ScaleTransform.ScaleXProperty, t.Scale); SetNow(l.Scale, ScaleTransform.ScaleYProperty, t.Scale);
                SetNow(l.Block, OpacityProperty, 0);
            }
            Place(l, t, animated, reduce);
        }
        foreach (var (g, i) in ghosts)
        {
            var nl = _lines[i];
            Place(g, _frame.Target(i - idx, hCur, hNext, nl.LayoutHeight, FillEnabled), animated, reduce);
            RetireLine(g, animated);
        }
        foreach (var l in leavers) Leave(l);
        PrepareFill();
    }

    private void RetireLine(SceneLine l, bool animated)
    {
        if (!animated) { l.Block.BeginAnimation(OpacityProperty, null); _linesLayer.Children.Remove(l.Block); return; }
        var fade = SceneAnim.To(0, 0.6);
        fade.Completed += (_, _) => _linesLayer.Children.Remove(l.Block);
        l.Block.BeginAnimation(OpacityProperty, fade);
    }

    // ---------------------------------------------------------------- États sans lignes (recherche, indisponible, rien en lecture...)

    private void UpdateInfo()
    {
        var (title, sub) = SceneInfo.Compute(_model.Display, _model.Track, AppIdentity.DisplayName);
        var key = title + "\u001F" + sub + "|" + _layoutKey + "|" + _styleKey;
        if (key == _infoKey) return;
        _infoKey = key;
        _infoTitle.Text = title; _infoSub.Text = sub;
    }

    private void SetInfoVisible(bool visible, bool animated)
    {
        var target = visible ? 1.0 : 0.0;
        if (animated) _infoLayer.BeginAnimation(OpacityProperty, SceneAnim.Fade(target, 0.4));
        else { _infoLayer.BeginAnimation(OpacityProperty, null); _infoLayer.Opacity = target; }
    }

    // ================================================================ Types internes

    private sealed class DriftImage
    {
        public readonly Image Image; public readonly ScaleTransform Scale; public readonly TranslateTransform Move;
        public readonly List<AnimationClock> Clocks = new();
        public double TargetOpacity;
        public DriftImage(Image image, ScaleTransform scale, TranslateTransform move) { Image = image; Scale = scale; Move = move; }
    }
}
