using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Entrée et sortie de la Scène (S10, S25) : choix de l'écran (<see cref="SceneScreenChoice"/>, Core), zoom depuis la petite fenêtre (et retour),
/// petite fenêtre rendue à la sortie. Tout est journalisé SANS titre, artiste, paroles ni identifiant (indices et tailles d'écran seulement).
/// Si le zoom échoue, la Scène s'ouvre sans lui ; si la Scène elle-même échoue, tout est remis d'aplomb et un avis est affiché.
/// Non vérifié sur Windows : voir le journal W6a+b (ce que lyra.log montrera).
/// </summary>
internal sealed class SceneController
{
    public enum SceneState { Hidden, Entering, Shown, Exiting }

    private readonly AppModel _model;
    private readonly SettingsStore _store;
    private readonly Func<LyricsWindow> _small;
    private SceneWindow? _scene;
    private SceneZoomWindow? _zoom;
    private ScreenInfo? _screen;
    private RectD _smallRectPx;
    private bool _smallWasShown, _exitQueued;
    private readonly Stopwatch _shownFor = new();

    public SceneState State { get; private set; } = SceneState.Hidden;
    public bool IsActive => State != SceneState.Hidden;
    /// <summary>Appelé quand la Scène est fermée (le masquage automatique réévalue la situation).</summary>
    public Action? Exited { get; set; }
    /// <summary>Commandes de lecture de la barre et du clavier de la Scène (précédent, lecture / pause, suivant) : les mêmes que la petite fenêtre.</summary>
    public Action<PlaybackCommand>? Playback { get; set; }

    public SceneController(AppModel model, SettingsStore store, Func<LyricsWindow> small)
    {
        _model = model; _store = store; _small = small;
    }

    public void Toggle()
    {
        if (State == SceneState.Shown) Exit();
        else if (State == SceneState.Hidden) Enter();
        else if (State == SceneState.Entering) _exitQueued = true;
    }

    // ================================================================ Entrée

    public void Enter()
    {
        if (State != SceneState.Hidden) return;
        try { EnterCore(); }
        catch (Exception e)
        {
            Log.WriteException("erreur", "scène : entrée impossible", e);
            Abort();
            _model.ShowNotice("Scène impossible (voir lyra.log).", 5);
        }
    }

    private void EnterCore()
    {
        var screens = ScreenCatalog.List();
        if (screens.Count == 0) { Log.Write("scene", "entrée annulée : aucun écran trouvé"); return; }
        var small = _small();
        _smallWasShown = small.IsVisible;
        var windowIndex = ScreenCatalog.IndexOfWindow(screens, small.Hwnd);
        var setting = _store.Current.SceneScreen;
        var index = SceneScreenChoice.Pick(setting, screens.Select(s => s.Name).ToList(), ScreenCatalog.PrimaryIndex(screens), windowIndex);
        var screen = _screen = screens[index];
        var kind = setting == SceneScreenChoice.Window ? "écran de la fenêtre" : setting == SceneScreenChoice.Main ? "écran principal" : "écran choisi par son nom";
        Log.Write("scene", $"entrée : écran {index + 1} sur {screens.Count} ({screen.Width}x{screen.Height}, échelle {screen.Scale:0.##}), réglage « {kind} », niveau de rendu {RenderCapability.Tier >> 16}, " +
                           $"animations {(SystemPrefs.Current.AnimationsEnabled ? "oui" : "non (zoom remplacé par une apparition directe)")}, petite fenêtre {(_smallWasShown ? "affichée" : "cachée")}");

        State = SceneState.Entering;
        _exitQueued = false;
        _model.SetSceneVisible(true);
        _scene = new SceneWindow(_model, _store, screen) { ExitRequested = Exit, Playback = c => Playback?.Invoke(c), ScreenChanged = s => _screen = s };
        _smallRectPx = _smallWasShown && Native.GetWindowRect(small.Hwnd, out var r) ? new RectD(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top) : new RectD(0, 0, 0, 0);

        if (SystemPrefs.Current.AnimationsEnabled)
        {
            try
            {
                _scene.Prepare();
                var snapshot = _scene.Snapshot();
                _zoom = new SceneZoomWindow(screen, snapshot, LocalRectDip(screen), entering: true);
                _zoom.Show();
                if (_smallWasShown) small.HideFloating();
                _zoom.Run(SceneZoom.Duration, () => ShowSceneNow(hideSmall: false));
                return;
            }
            catch (Exception e)
            {
                Log.WriteException("erreur", "scène : zoom d'entrée impossible, ouverture directe", e);
                CloseZoom();
            }
        }
        ShowSceneNow(hideSmall: true);
    }

    private RectD LocalRectDip(ScreenInfo screen)
    {
        var local = SceneZoom.LocalRect(_smallRectPx, new RectD(screen.X, screen.Y, screen.Width, screen.Height));
        return new RectD(local.X / screen.Scale, local.Y / screen.Scale, local.Width / screen.Scale, local.Height / screen.Scale);
    }

    /// <summary>Ferme la fenêtre de zoom une seule fois : le filet de sécurité (1,5 s) la refermait après le premier dessin de la Scène (fermer une fenêtre déjà fermée lève une exception).</summary>
    private static void CloseZoom(Window zoom)
    {
        try { zoom.Close(); } catch (InvalidOperationException) { }
    }

    private void ShowSceneNow(bool hideSmall)
    {
        if (State != SceneState.Entering || _scene is null) return;
        try
        {
            _scene.Show();
            _scene.Start();
            if (hideSmall && _smallWasShown) _small().HideFloating();
            var zoom = _zoom; _zoom = null;
            if (zoom is not null)
            {
                // la photo du zoom reste jusqu'à ce que la vraie Scène ait été dessinée : pas de clignotement
                EventHandler? handler = null;
                handler = (_, _) => { _scene!.ContentRendered -= handler; CloseZoom(zoom); };
                _scene.ContentRendered += handler;
                var failsafe = new DispatcherTimer(DispatcherPriority.Background, _scene.Dispatcher) { Interval = TimeSpan.FromSeconds(1.5) };
                failsafe.Tick += (_, _) => { failsafe.Stop(); CloseZoom(zoom); };
                failsafe.Start();
            }
            State = SceneState.Shown;
            _shownFor.Restart();
            Log.Write("scene", "Scène affichée");
        }
        catch (Exception e)
        {
            Log.WriteException("erreur", "scène : affichage impossible", e);
            Abort();
            _model.ShowNotice("Scène impossible (voir lyra.log).", 5);
            return;
        }
        if (_exitQueued) { _exitQueued = false; Exit(); }
    }

    // ================================================================ Sortie

    public void Exit()
    {
        if (State == SceneState.Entering) { _exitQueued = true; return; }
        if (State != SceneState.Shown || _scene is null) return;
        State = SceneState.Exiting;
        try
        {
            if (SystemPrefs.Current.AnimationsEnabled && _screen is { } screen)
            {
                var snapshot = _scene.Snapshot();
                _zoom = new SceneZoomWindow(screen, snapshot, LocalRectDip(screen), entering: false);
                _zoom.Show();
                // le zoom est par-dessus : une fois dessiné, la vraie Scène se cache et la petite fenêtre revient sous lui
                _zoom.Dispatcher.BeginInvoke(() => { _scene?.Hide(); if (_smallWasShown) _small().ShowFloating(); }, DispatcherPriority.ContextIdle);
                _zoom.Run(SceneZoom.Duration, FinishExit);
                return;
            }
        }
        catch (Exception e)
        {
            Log.WriteException("erreur", "scène : zoom de sortie impossible, fermeture directe", e);
            CloseZoom();
        }
        FinishExit();
    }

    private void FinishExit()
    {
        if (State == SceneState.Hidden) return;
        CloseZoom();
        var seconds = _shownFor.Elapsed.TotalSeconds;
        try { _scene?.Shutdown(); } catch (Exception e) { Log.WriteException("erreur", "scène : fermeture", e); }
        _scene = null;
        State = SceneState.Hidden;
        _model.SetSceneVisible(false);
        if (_smallWasShown) { var small = _small(); if (!small.IsVisible) small.ShowFloating(); }
        Log.Write("scene", $"sortie après {seconds:0} s");
        Exited?.Invoke();
    }

    /// <summary>Échec : on ne laisse jamais l'utilisateur coincé derrière une fenêtre noire.</summary>
    private void Abort()
    {
        CloseZoom();
        try { _scene?.Shutdown(); } catch { }
        _scene = null;
        State = SceneState.Hidden;
        _model.SetSceneVisible(false);
        if (_smallWasShown) { try { var small = _small(); if (!small.IsVisible) small.ShowFloating(); } catch { } }
        Exited?.Invoke();
    }

    private void CloseZoom()
    {
        var z = _zoom; _zoom = null;
        try { z?.Close(); } catch { }
    }

    /// <summary>À l'arrêt de l'application.</summary>
    public void Dispose()
    {
        CloseZoom();
        try { _scene?.Shutdown(); } catch { }
        _scene = null;
        State = SceneState.Hidden;
    }
}

/// <summary>
/// Fenêtre transparente du zoom (S25) : une PHOTO de la Scène qui grandit depuis la petite fenêtre jusqu'au plein écran (ou l'inverse) : position,
/// échelle, coins arrondis, opacité (même courbe et mêmes durées que le Mac). Elle ne vit que le temps du zoom ; la vraie Scène, opaque, prend ensuite le relais.
/// </summary>
internal sealed class SceneZoomWindow : Window
{
    private readonly ScreenInfo _screen;
    private readonly RectD _local;
    private readonly bool _entering;
    private readonly Border _stage = new() { RenderTransformOrigin = new Point(0.5, 0.5), IsHitTestVisible = false };
    private readonly ScaleTransform _scale = new();
    private readonly TranslateTransform _move = new();
    private readonly RectangleGeometry _clip;
    private IntPtr _hwnd;
    private bool _done;

    public SceneZoomWindow(ScreenInfo screen, BitmapSource snapshot, RectD localDip, bool entering)
    {
        _screen = screen; _local = localDip; _entering = entering;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false; Topmost = true;
        AllowsTransparency = true; Background = Brushes.Transparent;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = screen.X / screen.Scale; Top = screen.Y / screen.Scale; Width = screen.DipWidth; Height = screen.DipHeight;
        Title = AppIdentity.DisplayName;
        UseLayoutRounding = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);

        var w = screen.DipWidth; var h = screen.DipHeight;
        _stage.Width = w; _stage.Height = h;
        _stage.Background = new ImageBrush(snapshot) { Stretch = Stretch.Fill };
        _clip = new RectangleGeometry(new Rect(0, 0, w, h), 0, 0);
        _stage.Clip = _clip;
        _stage.RenderTransform = new TransformGroup { Children = { _scale, _move } };
        var canvas = new Canvas { Background = Brushes.Transparent };
        canvas.Children.Add(_stage);
        Content = canvas;

        // état de départ (le zoom avant part de la petite fenêtre, le zoom arrière du plein écran)
        var s = SceneZoom.StartScale(localDip, w);
        var small = (Scale: s, Dx: localDip.MidX - w / 2, Dy: localDip.MidY - h / 2, Radius: SceneZoom.SmallCorner / s);
        if (entering) Apply(small.Scale, small.Dx, small.Dy, small.Radius, 0);
        else Apply(1, 0, 0, 0, 1);
        SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            Native.SetExStyle(_hwnd, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TRANSPARENT);
            Native.SetWindowPos(_hwnd, Native.HWND_TOPMOST, _screen.X, _screen.Y, _screen.Width, _screen.Height, Native.SWP_NOACTIVATE);
        };
    }

    private void Apply(double scale, double dx, double dy, double radius, double opacity)
    {
        _scale.ScaleX = _scale.ScaleY = scale; _move.X = dx; _move.Y = dy;
        _clip.RadiusX = _clip.RadiusY = radius; _stage.Opacity = opacity;
    }

    /// <summary>Lance le zoom ; <paramref name="done"/> est appelé UNE fois à la fin (ou au bout de la durée + 1 s si WPF n'a pas signalé la fin).</summary>
    public void Run(double seconds, Action done)
    {
        var w = _screen.DipWidth; var h = _screen.DipHeight;
        var s = SceneZoom.StartScale(_local, w);
        var dx = _local.MidX - w / 2; var dy = _local.MidY - h / 2; var radius = SceneZoom.SmallCorner / s;
        var half = seconds * 0.5;
        // en entrée, la photo apparaît vite au début ; en sortie, elle disparaît vite à la fin (la petite fenêtre prend le relais)
        var scaleAnim = SceneAnim.To(_entering ? 1 : s, seconds);
        void Finish() { if (_done) return; _done = true; done(); }
        scaleAnim.Completed += (_, _) => Finish();
        _scale.BeginAnimation(ScaleTransform.ScaleXProperty, scaleAnim);
        _scale.BeginAnimation(ScaleTransform.ScaleYProperty, SceneAnim.To(_entering ? 1 : s, seconds));
        _move.BeginAnimation(TranslateTransform.XProperty, SceneAnim.To(_entering ? 0 : dx, seconds));
        _move.BeginAnimation(TranslateTransform.YProperty, SceneAnim.To(_entering ? 0 : dy, seconds));
        _clip.BeginAnimation(RectangleGeometry.RadiusXProperty, SceneAnim.To(_entering ? 0 : radius, seconds));
        _clip.BeginAnimation(RectangleGeometry.RadiusYProperty, SceneAnim.To(_entering ? 0 : radius, seconds));
        _stage.BeginAnimation(OpacityProperty, SceneAnim.To(_entering ? 1 : 0, half, _entering ? 0 : half));
        var failsafe = new DispatcherTimer(DispatcherPriority.Normal, Dispatcher) { Interval = TimeSpan.FromSeconds(seconds + 1.0) };
        failsafe.Tick += (_, _) => { failsafe.Stop(); Finish(); };
        failsafe.Start();
    }
}
