using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shell;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Fenêtre flottante de paroles : sans bordure, toujours au-dessus, jamais activée. Deux modes de rendu choisis à la création :
/// « compatible » (AllowsTransparency, fonctionne partout) ou « flou du système » (fond acrylique DWM, Windows 11 ≥ 22621, expérimental).
/// Aucune de ces API ne peut être exécutée sur la machine de développement : tout le comportement visuel est à vérifier sur le PC.
/// </summary>
internal sealed partial class LyricsWindow : Window
{
    private static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    private readonly AppModel _model;
    private readonly SettingsStore _store;
    private readonly bool _systemBackdrop;
    private IntPtr _hwnd;
    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;

    // vue
    private readonly Border _background = new() { CornerRadius = new CornerRadius(24), SnapsToDevicePixels = true };
    private readonly Border _glassSheen = new() { CornerRadius = new CornerRadius(24), IsHitTestVisible = false };
    private readonly Grid _content = new();
    private readonly Grid _linesHost = new() { ClipToBounds = false };
    private readonly LinePanel _lines = new() { RenderTransform = new TranslateTransform() };
    private readonly StackPanel _statePanel = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    private readonly TextBlock _stateTitle = new() { FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.White };
    private readonly TextBlock _stateBody = new() { TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) };
    private readonly ClickableBorder _stateAction = new() { CornerRadius = new CornerRadius(9), Padding = new Thickness(16, 6, 16, 6), Margin = new Thickness(0, 12, 0, 0), Cursor = Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    /// <summary>« Chercher une version » (B1, ligne 22) à côté de « Réessayer » dans Paroles indisponibles et Service occupé.</summary>
    private readonly ClickableBorder _stateSecondary = new() { CornerRadius = new CornerRadius(9), Padding = new Thickness(16, 6, 16, 6), Margin = new Thickness(10, 12, 0, 0), Cursor = Cursors.Hand, HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    private readonly TextBlock _stateSecondaryText = new() { Foreground = Brushes.White, FontWeight = FontWeights.SemiBold, FontSize = 13 };
    private readonly StackPanel _stateButtons = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock _stateActionText = new() { Foreground = Brushes.White, FontWeight = FontWeights.SemiBold, FontSize = 13 };
    private readonly Grid _unsyncedHost = new() { ClipToBounds = true, Visibility = Visibility.Collapsed };
    private readonly TextBlock _unsyncedText = new() { TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, RenderTransform = new TranslateTransform(), VerticalAlignment = VerticalAlignment.Top };
    private readonly TextBlock _unsyncedLabel = new() { Text = "Paroles non synchronisées", FontSize = 11, Foreground = new SolidColorBrush(Color.FromArgb(150, 255, 255, 255)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -20, 0, 0), Visibility = Visibility.Collapsed };
    private readonly Grid _bar = new() { Opacity = 0, VerticalAlignment = VerticalAlignment.Top, Height = 36 };
    private readonly TextBlock _barTitle = new() { FontWeight = FontWeights.SemiBold, FontSize = 12, Foreground = Brushes.White, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock _barArtist = new() { FontSize = 12, Foreground = new SolidColorBrush(Color.FromArgb(170, 255, 255, 255)), TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock _playGlyph = new() { FontFamily = IconFont, FontSize = 13, Foreground = Brushes.White };
    private readonly Border _noticePill = new() { CornerRadius = new CornerRadius(12), Padding = new Thickness(12, 5, 12, 5), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 40, 0, 0), Visibility = Visibility.Collapsed, Background = new SolidColorBrush(Color.FromArgb(215, 30, 30, 36)), IsHitTestVisible = false };
    private readonly TextBlock _noticeText = new() { Foreground = Brushes.White, FontSize = 12, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap };
    private readonly ClickableText _attribution = new() { Text = "Paroles : LRCLIB · À propos et droits", FontSize = 10.5, Foreground = new SolidColorBrush(Color.FromArgb(150, 255, 255, 255)), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 7), Cursor = Cursors.Hand, Opacity = 0 };
    // S22 : barres fantômes de l'attente (cachées hors recherche)
    private readonly Grid _shimmer = new() { IsHitTestVisible = false, Visibility = Visibility.Collapsed, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Opacity = 0, RenderTransform = new TranslateTransform() };
    private readonly TranslateTransform _sweepShift = new();
    private bool _shimmerOn;
    private double _shimmerWidth;
    private bool _shimmerAnimated;
    // D1 : le bloc non synchronisé défile par UNE animation ; mesure refaite seulement quand la mise en page change
    private string _unsyncedLayoutKey = "";
    private int _unsyncedPlanStamp = -1;
    private double _unsyncedOverflow, _unsyncedMargin;
    private double _unsyncedArmedAt;
    private readonly List<TextBlock> _slots = new();
    private readonly List<(string Key, double Scale, double Opacity)> _previous = new();
    private string _signature = "";
    private string _headSignature = "";
    private int _lastEpoch = -1;
    private LineFit? _fit;
    private DispatcherTimer? _topmostTimer;
    private DispatcherTimer? _geometryTimer;
    private bool _hovering;
    private Typeface _typeface = new("Segoe UI");

    public Action? OpenSettings { get; set; }
    public Action? OpenAbout { get; set; }
    public Action? OpenManualSearch { get; set; }
    /// <summary>Double-clic sur la fenêtre et bouton « Scène plein écran » de la barre (comme le Mac 1.1.0).</summary>
    public Action? OpenScene { get; set; }
    public Action<PlaybackCommand>? Playback { get; set; }

    public IntPtr Hwnd => _hwnd;
    /// <summary>Mode de rendu choisi à la création : vrai = flou du système (fenêtre non en couches), faux = compatible (AllowsTransparency).</summary>
    public bool SystemBackdropMode => _systemBackdrop;
    public bool SystemBackdropActive { get; private set; }
    public bool ClickThroughActive { get; private set; }

    public LyricsWindow(AppModel model, SettingsStore store, bool systemBackdrop)
    {
        Icon = LyraLyrics.App.Services.AppIcon.Wpf;
        _model = model; _store = store;
        _systemBackdrop = systemBackdrop && Native.SupportsSystemBackdrop;
        Title = AppIdentity.DisplayName;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.CanResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        AllowsTransparency = !_systemBackdrop;
        Background = _systemBackdrop ? Brushes.Transparent : null;
        UseLayoutRounding = true;
        SnapsToDevicePixels = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Ideal);
        TextOptions.SetTextRenderingMode(this, TextRenderingMode.Grayscale);
        WindowChrome.SetWindowChrome(this, new WindowChrome
        {
            CaptionHeight = 0, ResizeBorderThickness = new Thickness(7), GlassFrameThickness = _systemBackdrop ? new Thickness(-1) : new Thickness(0),
            CornerRadius = new CornerRadius(0), UseAeroCaptionButtons = false, NonClientFrameEdges = NonClientFrameEdges.None,
        });
        MinWidth = LyricsMetrics.MinResizeWidth; MinHeight = LyricsMetrics.MinResizeHeight;
        var work = SystemParameters.WorkArea;
        MaxWidth = Math.Max(MinWidth, work.Width * 0.9); MaxHeight = Math.Max(MinHeight, work.Height * 0.9);
        var s = _store.Current;
        Width = Math.Clamp(s.WindowWidth ?? LyricsMetrics.WindowWidth, MinWidth, MaxWidth);
        Height = Math.Clamp(s.WindowHeight ?? LyricsMetrics.DefaultHeight, MinHeight, MaxHeight);
        RestorePosition();
        BuildVisualTree();
        Loaded += (_, _) => { ApplyStyleTo(); Refresh(force: true); };
        SourceInitialized += OnSourceInitialized;
        SizeChanged += (_, _) => { _model.RefreshUnsyncedScroll(); Refresh(force: true); ScheduleGeometrySave(); };
        LocationChanged += (_, _) => ScheduleGeometrySave();
        MouseEnter += (_, _) => SetHover(true);
        MouseLeave += (_, _) => SetHover(false);
        MouseLeftButtonDown += OnDrag;
        _model.Changed += OnModelChanged;
        _store.Changed += OnSettingsChanged;
        SystemPrefs.Changed += OnSystemPrefsChanged;
        IsVisibleChanged += (_, _) => RefreshEffects();             // fond et remplissage s'arrêtent avec la fenêtre masquée
    }

    // ---- Construction

    private void BuildVisualTree()
    {
        _stateActionText.Margin = new Thickness(0);
        _stateAction.Child = _stateActionText;
        _stateAction.MouseLeftButtonDown += (_, e) => e.Handled = true;       // pas de déplacement de la fenêtre depuis un bouton
        _stateAction.Activated = () => _model.RetryLookup();
        _stateAction.MouseLeftButtonUp += (_, e) => { _model.RetryLookup(); e.Handled = true; };
        _statePanel.Children.Add(_stateTitle);
        _statePanel.Children.Add(_stateBody);
        _stateSecondary.Child = _stateSecondaryText;
        _stateSecondary.MouseLeftButtonDown += (_, e) => e.Handled = true;
        _stateSecondary.Activated = () => OpenManualSearch?.Invoke();
        _stateSecondary.MouseLeftButtonUp += (_, e) => { OpenManualSearch?.Invoke(); e.Handled = true; };
        _stateButtons.Children.Add(_stateAction);
        _stateButtons.Children.Add(_stateSecondary);
        _statePanel.Children.Add(_stateButtons);

        _linesHost.Children.Add(_lines);
        _unsyncedHost.Children.Add(_unsyncedText);
        _unsyncedHost.OpacityMask = new LinearGradientBrush(new GradientStopCollection
        {
            new(Color.FromArgb(0, 0, 0, 0), 0), new(Colors.Black, 0.12), new(Colors.Black, 0.88), new(Color.FromArgb(0, 0, 0, 0), 1),
        }, new Point(0, 0), new Point(0, 1));

        _content.Margin = new Thickness(LyricsMetrics.PaddingSide, LyricsMetrics.PaddingTop, LyricsMetrics.PaddingSide, LyricsMetrics.PaddingBottom);
        _content.Children.Add(_linesHost);
        _content.Children.Add(_unsyncedHost);
        _content.Children.Add(_statePanel);
        _content.Children.Add(_shimmer);

        BuildDrift();
        BuildBar();
        _noticePill.Child = _noticeText;
        _attribution.MouseLeftButtonDown += (_, e) => e.Handled = true;
        _attribution.Activated = () => OpenAbout?.Invoke();
        _attribution.MouseLeftButtonUp += (_, e) => { OpenAbout?.Invoke(); e.Handled = true; };
        A11y.Name(_attribution, "À propos et droits", "Ouvre la fenêtre À propos : source des paroles et droits");
        A11y.Name(_stateAction, "Réessayer", "Relance la recherche des paroles de ce titre");
        A11y.Name(_stateSecondary, "Chercher une autre version des paroles", "Ouvre la recherche manuelle sur LRCLIB");
        A11y.Name(this, AppIdentity.DisplayName + " : paroles du titre en cours");
        A11y.Name(_unsyncedText, "Paroles non synchronisées");
        A11y.Name(_noticeText, "Avis");
        _bar.IsHitTestVisible = false; _attribution.IsHitTestVisible = false;

        var root = new Grid { Background = Brushes.Transparent };
        root.Children.Add(_background);
        root.Children.Add(_driftHost);
        root.Children.Add(_glassSheen);
        root.Children.Add(_content);
        root.Children.Add(_bar);
        root.Children.Add(_attribution);
        root.Children.Add(_noticePill);
        Content = root;
    }

    private ClickableBorder IconButton(string glyph, string tip, Action click, TextBlock? glyphBlock = null)
    {
        var g = glyphBlock ?? new TextBlock { FontFamily = IconFont, FontSize = 13, Foreground = Brushes.White };
        if (glyphBlock is null) g.Text = glyph;
        g.HorizontalAlignment = HorizontalAlignment.Center; g.VerticalAlignment = VerticalAlignment.Center;
        var b = new ClickableBorder { Width = 30, Height = 26, CornerRadius = new CornerRadius(7), Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tip, Child = g, Activated = click };
        b.MouseEnter += (_, _) => b.Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255));
        b.MouseLeave += (_, _) => b.Background = Brushes.Transparent;
        b.MouseLeftButtonDown += (_, e) => e.Handled = true;       // pas de déplacement de la fenêtre depuis un bouton
        b.MouseLeftButtonUp += (_, e) => { click(); e.Handled = true; };
        A11y.Name(b, tip);
        return b;
    }

    private void BuildBar()
    {
        _bar.Background = new LinearGradientBrush(Color.FromArgb(120, 0, 0, 0), Color.FromArgb(0, 0, 0, 0), 90);
        _bar.Margin = new Thickness(4, 4, 4, 0);
        _bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _bar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var info = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 8, 0) };
        info.Children.Add(_barTitle);
        info.Children.Add(new TextBlock { Text = "  ·  ", FontSize = 12, Foreground = new SolidColorBrush(Color.FromArgb(120, 255, 255, 255)) });
        info.Children.Add(_barArtist);
        Grid.SetColumn(info, 0);
        _bar.Children.Add(info);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
        buttons.Children.Add(IconButton("", "Titre précédent", () => Playback?.Invoke(PlaybackCommand.Previous)));
        buttons.Children.Add(IconButton("", "Lecture / pause", () => Playback?.Invoke(PlaybackCommand.PlayPause), _playGlyph));
        buttons.Children.Add(IconButton("", "Titre suivant", () => Playback?.Invoke(PlaybackCommand.Next)));
        buttons.Children.Add(IconButton("", "Style du fond (uni, verre, transparent)", CycleStyle));
        buttons.Children.Add(IconButton("\uE740", "Scène plein écran", () => OpenScene?.Invoke()));
        buttons.Children.Add(IconButton("", "Réglages", () => OpenSettings?.Invoke()));
        Grid.SetColumn(buttons, 1);
        _bar.Children.Add(buttons);
    }

    private void CycleStyle()
    {
        _store.Update(s => s.Style = s.Style.Next());
        _model.ShowNotice("Style : " + _store.Current.Style.Label(), 1.5);
    }

    // ---- Fenêtre Win32

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _hwnd = new WindowInteropHelper(this).Handle;
        Native.SetExStyle(_hwnd, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOPMOST);
        if (_systemBackdrop && HwndSource.FromHwnd(_hwnd) is { } src)
        {
            src.CompositionTarget.BackgroundColor = Colors.Transparent;
            SystemBackdropActive = Native.SetDwmInt(_hwnd, Native.DWMWA_WINDOW_CORNER_PREFERENCE, Native.DWMWCP_ROUND);
            Native.SetDwmInt(_hwnd, Native.DWMWA_USE_IMMERSIVE_DARK_MODE, 1);
            var margins = new Native.MARGINS { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            Native.DwmExtendFrameIntoClientArea(_hwnd, ref margins);
            Log.Write("window", "mode flou du système demandé (build " + Environment.OSVersion.Version.Build + ")");
        }
        ApplyStyleTo();
        SetClickThrough(_store.Current.ClickThrough);
        _topmostTimer = new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = TimeSpan.FromSeconds(2) };
        _topmostTimer.Tick += (_, _) => { if (IsVisible && _hwnd != IntPtr.Zero) Native.BringToTopmost(_hwnd); };
        _topmostTimer.Start();
        Microsoft.Win32.SystemEvents.PowerModeChanged += OnPowerModeChanged;
    }

    private void OnPowerModeChanged(object? sender, Microsoft.Win32.PowerModeChangedEventArgs a)
    {
        if (a.Mode == Microsoft.Win32.PowerModes.Resume) _dispatcher.BeginInvoke(() => { if (IsVisible && _hwnd != IntPtr.Zero) Native.BringToTopmost(_hwnd); });
    }

    /// <summary>
    /// Clic-à-travers. Doc Microsoft (SetLayeredWindowAttributes, Remarks) : « once SetLayeredWindowAttributes has been called for a layered
    /// window, subsequent UpdateLayeredWindow calls will fail until the layering style bit is cleared and set again »
    /// (https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setlayeredwindowattributes). Or, en mode compatible
    /// (AllowsTransparency), WPF dessine par UpdateLayeredWindow et pose lui-même WS_EX_LAYERED : on ne pose donc QUE WS_EX_TRANSPARENT
    /// et on n'appelle jamais SetLayeredWindowAttributes. En mode « flou du système » la fenêtre n'est pas en couches : WS_EX_LAYERED
    /// (+ attributs, alpha 255 = opaque) est ajouté pour que WS_EX_TRANSPARENT rende la fenêtre traversable
    /// (https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles), puis RETIRÉ à la sortie.
    /// Chaque appel est journalisé avec le code d'erreur Win32 et le style relu.
    /// </summary>
    public void SetClickThrough(bool on)
    {
        ClickThroughActive = on;
        if (_hwnd == IntPtr.Zero) return;
        var mode = _systemBackdrop ? "flou du système" : "compatible";
        var before = Native.GetExStyle(_hwnd);
        if (on)
        {
            if (_systemBackdrop)
            {
                var wasLayered = (before & Native.WS_EX_LAYERED) != 0;
                var e1 = Native.SetExStyle(_hwnd, Native.WS_EX_LAYERED | Native.WS_EX_TRANSPARENT);
                var ok = Native.SetLayeredWindowAttributes(_hwnd, 0, 255, Native.LWA_ALPHA);
                var e2 = ok ? 0 : System.Runtime.InteropServices.Marshal.GetLastWin32Error();
                _layeredAddedByUs = !wasLayered;
                Log.Write("window", $"clic-à-travers activé (mode {mode}) : SetExStyle err={e1}, SetLayeredWindowAttributes ok={ok} err={e2}");
            }
            else
            {
                var e1 = Native.SetExStyle(_hwnd, Native.WS_EX_TRANSPARENT);
                Log.Write("window", $"clic-à-travers activé (mode {mode}) : SetExStyle err={e1}, SetLayeredWindowAttributes non appelé");
                if ((Native.GetExStyle(_hwnd) & Native.WS_EX_LAYERED) == 0) Log.Write("window", "ATTENTION : WS_EX_LAYERED absent en mode compatible (WPF devrait l'avoir posé)");
            }
            SetHover(false);
        }
        else
        {
            var e1 = Native.SetExStyle(_hwnd, 0, Native.WS_EX_TRANSPARENT | (_systemBackdrop && _layeredAddedByUs ? Native.WS_EX_LAYERED : 0));
            _layeredAddedByUs = false;
            Log.Write("window", $"clic-à-travers désactivé (mode {mode}) : SetExStyle err={e1}");
        }
        Log.Write("window", "style étendu : " + Native.DescribeExStyle(before) + " -> " + Native.DescribeExStyle(Native.GetExStyle(_hwnd)));
    }
    private bool _layeredAddedByUs;

    public void ShowFloating()
    {
        if (!IsVisible) Show();
        if (_hwnd != IntPtr.Zero) Native.BringToTopmost(_hwnd);
        _model.SetWindowVisible(true);
        Refresh(force: true);
    }

    public void HideFloating()
    {
        Hide();
        StopUnsyncedAnimation();                                  // fenêtre cachée : plus d'animation ; la réapparition demande un nouveau plan au modèle
        _model.SetWindowVisible(false);
    }

    private void OnDrag(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState != MouseButtonState.Pressed || ClickThroughActive) return;
        if (e.ClickCount >= 2) { e.Handled = true; OpenScene?.Invoke(); return; }       // double-clic : la Scène (comme le Mac)
        try { DragMove(); } catch (InvalidOperationException) { }
    }

    private void RestorePosition()
    {
        var work = SystemParameters.WorkArea;
        var p = _store.Current.Position;
        double left, top;
        if (p is not null && p.Left > SystemParameters.VirtualScreenLeft - Width + 80 && p.Left < SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 80
            && p.Top > SystemParameters.VirtualScreenTop - 10 && p.Top < SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 60)
        { left = p.Left; top = p.Top; }
        else { left = work.Left + (work.Width - Width) / 2; top = work.Bottom - Height - 80; }
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = left; Top = top;
    }

    private void ScheduleGeometrySave()
    {
        if (!IsLoaded) return;
        _geometryTimer ??= new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = TimeSpan.FromMilliseconds(600) };
        _geometryTimer.Tick -= SaveGeometry; _geometryTimer.Tick += SaveGeometry;
        _geometryTimer.Stop(); _geometryTimer.Start();
    }

    private void SaveGeometry(object? sender, EventArgs e)
    {
        _geometryTimer?.Stop();
        if (WindowState != WindowState.Normal) return;
        var w = ActualWidth; var h = ActualHeight; var l = Left; var t = Top;
        _store.UpdateQuiet(s =>
        {
            s.Position = new WindowPosition(l, t);
            if (Math.Abs(w - LyricsMetrics.WindowWidth) > 0.5 || Math.Abs(h - LyricsMetrics.DefaultHeight) > 0.5 || s.WindowWidth is not null) { s.WindowWidth = w; s.WindowHeight = h; }
        });
    }

    public void ResetSize()
    {
        _store.UpdateQuiet(s => { s.WindowWidth = null; s.WindowHeight = null; });
        Width = LyricsMetrics.WindowWidth; Height = LyricsMetrics.DefaultHeight;
        Refresh(force: true);
    }

    // ---- Réactions

    private void OnModelChanged() => Refresh(force: false);
    /// <summary>« Afficher les animations » ou « Effets de transparence » a changé dans Windows : style et lignes sont reposés (aucune relecture à chaque image).</summary>
    private void OnSystemPrefsChanged() { ApplyStyleTo(); Refresh(force: true); }
    private void OnSettingsChanged() { ApplyStyleTo(); Refresh(force: true); if (_store.Current.ClickThrough != ClickThroughActive) SetClickThrough(_store.Current.ClickThrough); }

    private void SetHover(bool on)
    {
        if (ClickThroughActive) on = false;
        _hovering = on;
        var animate = SystemPrefs.Current.AnimationsEnabled;
        void Fade(UIElement e, double to) { if (animate) e.BeginAnimation(OpacityProperty, new DoubleAnimation(to, TimeSpan.FromMilliseconds(160))); else { e.BeginAnimation(OpacityProperty, null); e.Opacity = to; } }
        Fade(_bar, on ? 1 : 0);
        Fade(_attribution, on ? 1 : 0);
        _bar.IsHitTestVisible = on; _attribution.IsHitTestVisible = on;       // invisibles = non cliquables
    }

    // ---- Fond

    /// <summary>Style réellement dessiné : « Effets de transparence » désactivés dans Windows = Uni (règle testée dans le Core, lue une fois par <see cref="SystemPrefs"/>).</summary>
    private BackgroundStyle EffectiveStyle() => SystemPrefs.Current.EffectiveStyle(_store.Current.Style);

    private static Color C(Rgb c) => Color.FromRgb((byte)Math.Round(c.R * 255), (byte)Math.Round(c.G * 255), (byte)Math.Round(c.B * 255));

    private void ApplyStyleTo()
    {
        var s = _store.Current;
        var style = EffectiveStyle();
        var alpha = s.BackgroundOpacity / 100.0;
        var tint = s.ArtworkColors && _model.Palette is { } pal ? (Rgb?)pal.Tint : null;
        _background.BorderThickness = new Thickness(0); _background.BorderBrush = null;
        _glassSheen.Background = null; _glassSheen.BorderBrush = null; _glassSheen.BorderThickness = new Thickness(0);
        _background.CornerRadius = _glassSheen.CornerRadius = new CornerRadius(SystemBackdropActive ? 8 : 24);
        switch (style)
        {
            case BackgroundStyle.Solid:
            {
                var c = tint is { } t ? C(t) : Color.FromRgb(22, 22, 28);
                var a = Math.Min(1, 0.35 + 1.6 * alpha);
                _background.Background = new SolidColorBrush(Color.FromArgb((byte)Math.Round(a * 255), c.R, c.G, c.B));
                _background.BorderBrush = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255)); _background.BorderThickness = new Thickness(1);
                SetBackdrop(Native.DWMSBT_NONE);
                break;
            }
            case BackgroundStyle.Glass:
            {
                var c = tint is { } t ? C(t) : Color.FromRgb(26, 26, 34);
                // Sans flou réel (mode compatible), on relève un peu la teinte pour garder le texte lisible ; avec l'acrylique, la teinte est plus légère.
                var a = SystemBackdropActive ? Math.Min(1, alpha * 0.7 + 0.05) : Math.Min(0.92, (tint is null ? alpha : alpha + 0.18) + 0.12);
                _background.Background = new SolidColorBrush(Color.FromArgb((byte)Math.Round(a * 255), c.R, c.G, c.B));
                _glassSheen.Background = new LinearGradientBrush(Color.FromArgb(51, 255, 255, 255), Color.FromArgb(13, 255, 255, 255), 45);
                _glassSheen.BorderBrush = new SolidColorBrush(Color.FromArgb(56, 255, 255, 255)); _glassSheen.BorderThickness = new Thickness(1);
                SetBackdrop(Native.DWMSBT_TRANSIENTWINDOW);
                break;
            }
            default:
                _background.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));       // 1/255 : reste « attrapable » à la souris
                SetBackdrop(Native.DWMSBT_NONE);
                break;
        }
    }

    private void SetBackdrop(int type)
    {
        if (!_systemBackdrop || _hwnd == IntPtr.Zero) return;
        if (!Native.SetDwmInt(_hwnd, Native.DWMWA_SYSTEMBACKDROP_TYPE, type)) Log.Write("window", "DWMWA_SYSTEMBACKDROP_TYPE refusé (type " + type + ")");
    }

    // ---- Dessin des lignes

    private Color LineColor()
    {
        // Règle du Mac : la couleur choisie gagne pour le texte ; la pochette ne teinte que le fond (voir LineColorRule).
        var s = _store.Current;
        return (Color)ColorConverter.ConvertFromString(LineColorRule.TextHex(s.ColorHex, s.ArtworkColors, _model.Palette?.Accent.Hex));
    }

    private static FontWeight WeightOf(LyricWeight w) => w switch { LyricWeight.Light => FontWeights.Light, LyricWeight.Regular => FontWeights.Normal, LyricWeight.Semibold => FontWeights.SemiBold, _ => FontWeights.Bold };

    private double Measure(string text, double size, double width)
    {
        var ft = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, _typeface, size, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip) { MaxTextWidth = Math.Max(20, width) };
        return ft.Height;
    }

    private void Refresh(bool force)
    {
        RefreshCore(force);
        RefreshEffects();                         // S24 : fond animé et karaoké (réglages, désactivés par défaut)
    }

    private void RefreshCore(bool force)
    {
        if (!IsLoaded && !force) return;
        var s = _store.Current;
        var animate = SystemPrefs.Current.AnimationsEnabled;
        var count = s.LineCountValue;
        _typeface = new Typeface(new FontFamily(s.Font.Family()), FontStyles.Normal, WeightOf(s.FontWeight), FontStretches.Normal);
        var display = _model.Display;
        var bar = _model.BarText;
        // Les relevés SMTC arrivent chaque seconde : si rien de visible n'a changé, on ne refait rien.
        var head = $"{bar.Title}|{bar.Artist}|{display}|{_model.Notice}|{_model.Palette?.Accent.Hex}|{_model.UnsyncedScroll.Stamp}|{_model.CurrentIndex}|{_model.TrackEpoch}|{_store.Current.Style}";
        if (!force && head == _headSignature) return;
        _headSignature = head;

        UpdateShimmer(display.Current is DisplayState.Screen.Searching, _model.SearchHint, animate);
        if (display.Current is not DisplayState.Screen.Unsynced) StopUnsyncedAnimation();

        // barre
        _barTitle.Text = bar.Title; _barArtist.Text = bar.Artist ?? ""; _barArtist.Visibility = bar.Artist is null ? Visibility.Collapsed : Visibility.Visible;
        _playGlyph.Text = _model.Display.Paused || _model.Track is null ? "" : "";

        // avis
        if (_model.Notice is { } n) { _noticeText.Text = n; _noticePill.Visibility = Visibility.Visible; }
        else _noticePill.Visibility = Visibility.Collapsed;

        ApplyStyleTo();
        var color = LineColor();
        var brushCurrent = new SolidColorBrush(color);
        var neutral = new SolidColorBrush(Colors.White);
        _background.Effect = null;

        // état texte
        if (display.StateText is { } st)
        {
            _statePanel.Visibility = Visibility.Visible; _linesHost.Visibility = Visibility.Collapsed; _unsyncedHost.Visibility = Visibility.Collapsed; _unsyncedLabel.Visibility = Visibility.Collapsed;
            _stateTitle.Text = st.Title; _stateTitle.FontSize = Math.Max(15, s.Size * 0.72); _stateTitle.FontFamily = _typeface.FontFamily;
            _stateBody.Text = st.Body; _stateBody.Visibility = st.Body.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
            _stateBody.FontSize = 13; _stateBody.Foreground = new SolidColorBrush(Color.FromArgb(190, 255, 255, 255));
            if (_model.StateActionLabel is { } label)
            {
                _stateActionText.Text = label; _stateAction.Visibility = Visibility.Visible;
                _stateAction.Background = new SolidColorBrush(Color.FromRgb(10, 132, 255));
            }
            else _stateAction.Visibility = Visibility.Collapsed;
            if (_model.SecondaryActionLabel is { } second)
            {
                _stateSecondaryText.Text = second; _stateSecondary.Visibility = Visibility.Visible;
                _stateSecondary.Background = new SolidColorBrush(Color.FromArgb(41, 255, 255, 255));
            }
            else _stateSecondary.Visibility = Visibility.Collapsed;
            _signature = "state";
            _lastEpoch = _model.TrackEpoch;
            ApplyTextShadow(s);
            return;
        }
        _statePanel.Visibility = Visibility.Collapsed;

        if (display.Current is DisplayState.Screen.Unsynced)
        {
            _linesHost.Visibility = Visibility.Collapsed; _unsyncedHost.Visibility = Visibility.Visible;
            ApplyUnsynced(s, neutral);
            _unsyncedLabel.Visibility = Visibility.Collapsed;
            _signature = "unsynced";
            _lastEpoch = _model.TrackEpoch;
            ApplyTextShadow(s);
            return;
        }
        _unsyncedHost.Visibility = Visibility.Collapsed;
        _linesHost.Visibility = Visibility.Visible;

        var items = _model.LineItems(count);
        var texts = items.Select(i => i.Text).ToList();
        var w = ActualWidth > 0 ? ActualWidth : Width; var h = ActualHeight > 0 ? ActualHeight : Height;
        var sig = string.Join("\u001F", texts) + $"|{count}|{s.Size}|{s.Font}|{s.FontWeight}|{w:0}|{h:0}|{color}|{s.NeighbourRatio}|{s.Glow}|{s.Style}";
        if (!force && sig == _signature) return;
        var advance = items.Count > 0 && _previous.Count == items.Count && _lastEpoch == _model.TrackEpoch && items.Any(i => i.Offset == 0)
                      && _previous.Select(p => p.Key).Skip(1).SequenceEqual(items.Select(i => i.Key).Take(items.Count - 1)) && sig != _signature;
        var sameLines = string.Join("\u001F", texts) == string.Join("\u001F", _slots.Select(t => t.Text));
        _signature = sig;

        _fit = new LineFitter(Measure).Fit(texts, s.Size, w, h, s.NeighbourRatio);
        EnsureSlots(items.Count);
        var mid = items.Count / 2;
        var newState = new List<(string, double, double)>();
        for (var i = 0; i < items.Count; i++)
        {
            var item = items[i];
            var tb = _slots[i];
            var targetScale = LineLook.Scale(item.Offset, s.NeighbourRatio);
            var targetOpacity = LineLook.Opacity(item.Offset, item.Dim);       // même rapport que le Mac (0,62 pour une ligne atténuée)
            tb.Text = item.Text;
            tb.FontFamily = _typeface.FontFamily; tb.FontWeight = _typeface.Weight; tb.FontSize = _fit.CurrentSize;
            tb.Foreground = item.Offset == 0 ? brushCurrent : neutral;
            tb.Tag = targetScale;
            tb.Effect = item.Offset == 0 && s.Glow && !(s.KaraokeFill && SystemPrefs.Current.AnimationsEnabled) ? new DropShadowEffect { Color = color, BlurRadius = 16, ShadowDepth = 0, Opacity = 0.85 } : null;
            var scale = (ScaleTransform)tb.RenderTransform;
            if (animate && advance && IsVisible)
            {
                var from = _previous[Math.Min(i + 1, _previous.Count - 1)];
                var useFrom = i + 1 < _previous.Count;
                var fromScale = useFrom ? from.Scale : targetScale * 0.9;
                var fromOpacity = useFrom ? from.Opacity : 0.0;
                Anim(scale, ScaleTransform.ScaleXProperty, fromScale, targetScale, 380);
                Anim(scale, ScaleTransform.ScaleYProperty, fromScale, targetScale, 380);
                Anim(tb, OpacityProperty, fromOpacity, targetOpacity, 380);
            }
            else
            {
                scale.BeginAnimation(ScaleTransform.ScaleXProperty, null); scale.BeginAnimation(ScaleTransform.ScaleYProperty, null);
                scale.ScaleX = scale.ScaleY = targetScale;
                tb.BeginAnimation(OpacityProperty, null);
                tb.Opacity = targetOpacity;
            }
            newState.Add((item.Key, targetScale, targetOpacity));
        }
        _lines.Gap = LyricsMetrics.LineGap;
        _lines.InvalidateMeasure();
        _lines.UpdateLayout();
        var translate = (TranslateTransform)_lines.RenderTransform;
        if (animate && advance && IsVisible)
        {
            var shift = _lines.CenterDistance(mid, Math.Min(mid + 1, items.Count - 1));
            Anim(translate, TranslateTransform.YProperty, shift, 0, 380);
        }
        else
        {
            translate.BeginAnimation(TranslateTransform.YProperty, null); translate.Y = 0;
            if (animate && IsVisible && !sameLines && (_lastEpoch != _model.TrackEpoch || !advance))
                _linesHost.BeginAnimation(OpacityProperty, new DoubleAnimation(0.0, 1.0, TimeSpan.FromMilliseconds(260)));
        }
        _previous.Clear(); _previous.AddRange(newState);
        _lastEpoch = _model.TrackEpoch;
        ApplyTextShadow(s);
    }

    // ---- D1 : bloc « non synchronisées », une seule animation linéaire (plus de re-mesure ni de redessin à chaque pas)

    private void ApplyUnsynced(Settings s, Brush neutral)
    {
        var size = Math.Max(15, s.Size * 0.62);
        var width = Math.Max(120, LyricsMetrics.TextWidth(ActualWidth > 0 ? ActualWidth : Width));
        var viewport = Math.Max(40, (ActualHeight > 0 ? ActualHeight : Height) - LyricsMetrics.PaddingTop - LyricsMetrics.PaddingBottom);
        var layoutKey = $"{_model.TrackEpoch}|{size}|{s.Font}|{s.FontWeight}|{width:0}|{viewport:0}";
        var geometryChanged = false;
        if (layoutKey != _unsyncedLayoutKey)
        {
            // Mesure seulement si la largeur, la police, la taille ou le texte changent.
            _unsyncedLayoutKey = layoutKey;
            _unsyncedText.FontFamily = _typeface.FontFamily; _unsyncedText.FontWeight = _typeface.Weight; _unsyncedText.FontSize = size;
            _unsyncedText.Foreground = neutral; _unsyncedText.Width = width;
            _unsyncedText.Text = _model.PlainText;
            _unsyncedText.Measure(new Size(width, double.PositiveInfinity));
            _unsyncedOverflow = Math.Max(0, _unsyncedText.DesiredSize.Height - viewport * 0.9);
            _unsyncedMargin = viewport * 0.04;
            geometryChanged = true;                                        // la géométrie a changé : l'animation est ré-armée
        }
        var plan = _model.UnsyncedScroll;
        if (plan.Stamp == _unsyncedPlanStamp)
        {
            if (!geometryChanged) return;
            // Même trajectoire, autre mise en page (police, taille) : on repart de l'avancement actuel, sans faire revenir le texte en arrière.
            var (progress, remaining) = UnsyncedScrollMath.Advance(plan, Services.Clock.Seconds() - _unsyncedArmedAt);
            ArmUnsyncedAnimation(progress, remaining);
            return;
        }
        _unsyncedPlanStamp = plan.Stamp;
        _unsyncedArmedAt = Services.Clock.Seconds();
        ArmUnsyncedAnimation(plan.Progress, plan.Remaining);
    }

    private void ArmUnsyncedAnimation(double progress, double remaining)
    {
        var (from, to) = UnsyncedScrollMath.Offsets(progress, _unsyncedOverflow, _unsyncedMargin);
        var tr = (TranslateTransform)_unsyncedText.RenderTransform;
        tr.BeginAnimation(TranslateTransform.YProperty, null);
        tr.Y = from;
        // Pause, saut, reprise, redimensionnement : un nouveau plan arrive du modèle ; sinon l'animation linéaire suit toute seule jusqu'à la fin du bloc.
        if (remaining > 0 && _unsyncedOverflow > 0)
            tr.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(from, to, TimeSpan.FromSeconds(remaining)) { FillBehavior = FillBehavior.HoldEnd });
    }

    private void StopUnsyncedAnimation()
    {
        if (_unsyncedPlanStamp < 0 && _unsyncedLayoutKey.Length == 0) return;
        ((TranslateTransform)_unsyncedText.RenderTransform).BeginAnimation(TranslateTransform.YProperty, null);
        _unsyncedPlanStamp = -1; _unsyncedLayoutKey = "";
    }

    // ---- S22 : attente élégante (barres fantômes traversées par un reflet), comme Shimmer.swift

    private void UpdateShimmer(bool searching, bool hint, bool animate)
    {
        if (!searching)
        {
            if (!_shimmerOn) return;
            _shimmerOn = false;
            _sweepShift.BeginAnimation(TranslateTransform.XProperty, null);
            _shimmer.BeginAnimation(OpacityProperty, null);
            _shimmer.Opacity = 0; _shimmer.Visibility = Visibility.Collapsed;
            return;
        }
        var width = LyricsMetrics.TextWidth(ActualWidth > 0 ? ActualWidth : Width) * ShimmerLayout.WidthFraction;
        ((TranslateTransform)_shimmer.RenderTransform).Y = hint ? ShimmerLayout.HintOffset : 0;
        if (_shimmerOn && Math.Abs(width - _shimmerWidth) < 0.5 && animate == _shimmerAnimated) return;
        var first = !_shimmerOn;
        _shimmerOn = true; _shimmerWidth = width; _shimmerAnimated = animate;
        BuildShimmer(width, animate);
        _shimmer.Visibility = Visibility.Visible;
        if (first)
        {
            // Apparition après 0,45 s (une recherche rapide ne montre rien) ; animations réduites : même délai, apparition immédiate sans fondu.
            _shimmer.Opacity = 0;
            _shimmer.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromSeconds(animate ? ShimmerLayout.FadeSeconds : 0.01))
            { BeginTime = TimeSpan.FromSeconds(ShimmerLayout.DelaySeconds), FillBehavior = FillBehavior.HoldEnd });
        }
    }

    private void BuildShimmer(double width, bool animate)
    {
        var height = ShimmerLayout.AreaHeight;
        _shimmer.Children.Clear();
        _shimmer.Width = width; _shimmer.Height = height;
        var bars = ShimmerLayout.Bars(width, height);
        var barBrush = new SolidColorBrush(Color.FromArgb(28, 255, 255, 255));        // blanc à 11 %
        var canvas = new Canvas { Width = width, Height = height };
        var mask = new DrawingGroup();
        mask.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, width, height))));
        foreach (var b in bars)
        {
            var rect = new Rect(b.X, b.Y, b.W, b.H);
            var r = new System.Windows.Shapes.Rectangle { Width = b.W, Height = b.H, RadiusX = b.H / 2, RadiusY = b.H / 2, Fill = barBrush };
            Canvas.SetLeft(r, b.X); Canvas.SetTop(r, b.Y);
            canvas.Children.Add(r);
            mask.Children.Add(new GeometryDrawing(Brushes.White, null, new RectangleGeometry(rect, b.H / 2, b.H / 2)));
        }
        _shimmer.Children.Add(canvas);
        if (!animate) return;
        // Le reflet (bande dégradée qui traverse) n'est visible que sur les barres : le masque est la forme des barres.
        var band = width * ShimmerLayout.BandFraction;
        var sweep = new System.Windows.Shapes.Rectangle
        {
            Width = band, Height = height, HorizontalAlignment = HorizontalAlignment.Left, RenderTransform = _sweepShift,
            Fill = new LinearGradientBrush(new GradientStopCollection { new(Color.FromArgb(0, 255, 255, 255), 0), new(Color.FromArgb(61, 255, 255, 255), 0.5), new(Color.FromArgb(0, 255, 255, 255), 1) }, new Point(0, 0.5), new Point(1, 0.5)),
        };
        var host = new Grid
        {
            Width = width, Height = height, ClipToBounds = true, IsHitTestVisible = false,
            OpacityMask = new DrawingBrush(mask) { Stretch = Stretch.Fill, ViewboxUnits = BrushMappingMode.Absolute, Viewbox = new Rect(0, 0, width, height) },
        };
        host.Children.Add(sweep);
        _shimmer.Children.Add(host);
        _sweepShift.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-band, width, TimeSpan.FromSeconds(ShimmerLayout.SweepSeconds))
        { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }, RepeatBehavior = RepeatBehavior.Forever });
    }

    private void ApplyTextShadow(Settings s)
    {
        // Style transparent : un halo sombre léger garde le texte lisible sur n'importe quel fond.
        _content.Effect = EffectiveStyle() == BackgroundStyle.Clear
            ? new DropShadowEffect { Color = Colors.Black, BlurRadius = 8, ShadowDepth = 0, Opacity = 0.85 }
            : null;
    }

    private static void Anim(Animatable target, DependencyProperty prop, double from, double to, int ms)
    {
        var a = new DoubleAnimation(from, to, TimeSpan.FromMilliseconds(ms)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        target.BeginAnimation(prop, a);
    }

    private static void Anim(UIElement target, DependencyProperty prop, double from, double to, int ms)
    {
        var a = new DoubleAnimation(from, to, TimeSpan.FromMilliseconds(ms)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        target.BeginAnimation(prop, a);
    }

    private void EnsureSlots(int count)
    {
        while (_slots.Count < count)
        {
            var tb = new TextBlock
            {
                TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, RenderTransformOrigin = new Point(0.5, 0.5),
                RenderTransform = new ScaleTransform(1, 1), Tag = 1.0, IsHitTestVisible = false,
            };
            _slots.Add(tb);
        }
        while (_slots.Count > count) _slots.RemoveAt(_slots.Count - 1);
        if (!_lines.Children.Cast<UIElement>().Where(e => LinePanel.GetOverlayOf(e) is null).SequenceEqual(_slots))
        {
            _lines.Children.Clear();
            foreach (var t in _slots) _lines.Children.Add(t);
            _previous.Clear();
        }
    }

    /// <summary>Constat 17 : l'abonnement statique aux événements système est retiré, sinon la fenêtre fermée (RecreateWindow) reste vivante et agit sur un HWND détruit.</summary>
    protected override void OnClosed(EventArgs e)
    {
        Microsoft.Win32.SystemEvents.PowerModeChanged -= OnPowerModeChanged;
        _hwnd = IntPtr.Zero;
        _topmostTimer?.Stop();
        _geometryTimer?.Stop();
        StopEffects(); _fillTimer?.Stop();
        _model.Changed -= OnModelChanged;
        _store.Changed -= OnSettingsChanged;
        SystemPrefs.Changed -= OnSystemPrefsChanged;
        base.OnClosed(e);
    }
}
