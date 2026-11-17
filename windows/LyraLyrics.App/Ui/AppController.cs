using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using System.Windows.Media;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>Assemble l'application : réglages, service de paroles, SMTC, modèle, fenêtre, raccourci, icône de notification.</summary>
internal sealed class AppController : IDisposable
{
    private readonly Dispatcher _ui = Dispatcher.CurrentDispatcher;
    private readonly SettingsStore _store = new(AppPaths.SettingsFile);
    private readonly HttpTransport _http = new();
    private readonly LyricsService _service;
    private readonly SmtcMonitor _smtc = new();
    private readonly AppModel _model;
    private readonly HotKeyService _hotKey = new();
    private readonly TrayService _tray = new(AppIdentity.DisplayName);
    private readonly NetworkWatcher _network = new();
    private readonly Diagnostics _diagnostics;
    private readonly UpdateService _update;
    private readonly AutoHideState _autoHide = new();
    private readonly DispatcherTimer _graceTimer;
    private readonly double _graceUntil = Clock.Seconds() + AutoHideState.GraceSeconds;
    private bool _evaluatingAutoHide, _welcomeOpen;
    private WelcomeWindow? _welcome;
    private ManualSearchWindow? _manualWindow;
    private LyricsWindow _window;
    private readonly SceneController _scene;
    private SettingsWindow? _settingsWindow;
    private AboutWindow? _aboutWindow;
    private bool _lastBackdrop;
    private HotKeyCombo _lastHotKey;
    private bool _disposed;

    public AppController()
    {
        SystemPrefs.Start(_ui);                        // accessibilité : animations et transparence lues une fois, puis sur événement système
        Log.Write("app", $"démarrage {AppIdentity.UserAgent} · Windows {Environment.OSVersion.Version} · {(Environment.Is64BitProcess ? "x64" : "x86")}");
        _update = new UpdateService(_http);
        _graceTimer = new DispatcherTimer(DispatcherPriority.Normal, _ui);
        _graceTimer.Tick += (_, _) => { _graceTimer.Stop(); EvaluateAutoHide(); };
        var client = new LrclibClient(_http, AppIdentity.UserAgent);
        _service = new LyricsService(client, AppPaths.IndexFile, LyricsService.SaltedHasher(_store.Current.IndexSalt), Clock.Seconds, Clock.Sleep,
            titlesBeforeBreaker: 3, log: f => Log.Write("lookup", f));
        _model = new AppModel(_ui, _service, _smtc)
        {
            PaletteDecoder = DecodePalette,
            ArtworkEnabled = () => _store.Current.ArtworkColors,
        };
        Log.Secrets = _model.SecretsForLog;
        _lastBackdrop = _store.Current.SystemBackdrop;
        _lastHotKey = _store.Current.HotKey;
        _window = CreateWindow();
        _scene = new SceneController(_model, _store, () => _window) { Exited = EvaluateAutoHide, Playback = cmd => _ = SendPlaybackAsync(cmd) };
        _diagnostics = new Diagnostics(() => _window, _smtc, _store) { TrayVisible = () => _tray.IconVisible };

        _hotKey.Pressed += () => _ui.BeginInvoke(OnHotKey);
        if (!_hotKey.Register(_store.Current.HotKey))
            _ui.BeginInvoke(() => _model.ShowNotice(_hotKey.LastError ?? "Raccourci indisponible", 6));
        _tray.State = () => (_window.IsVisible, _store.Current.ClickThrough);
        _tray.ToggleVisibility += () => _ui.BeginInvoke(ToggleVisibility);
        _tray.ToggleClickThrough += () => _ui.BeginInvoke(() => SetClickThrough(!_store.Current.ClickThrough));
        _tray.ToggleScene += () => _ui.BeginInvoke(_scene.Toggle);
        _tray.SceneActive = () => _scene.IsActive;
        _tray.OpenSettings += () => _ui.BeginInvoke(ShowSettings);
        _tray.OpenAbout += () => _ui.BeginInvoke(ShowAbout);
        _tray.OpenWelcome += () => _ui.BeginInvoke(ShowWelcome);
        _tray.OpenUpdate += () => _ui.BeginInvoke(OpenUpdatePage);
        _tray.UpdateTag = () => _model.UpdateRelease?.Tag;
        _model.Changed += EvaluateAutoHide;
        _tray.CopyDiagnostic += () => _ui.BeginInvoke(CopyDiagnostic);
        _tray.Quit += () => _ui.BeginInvoke(Quit);

        _network.Changed += online => _ui.BeginInvoke(() => _model.SetOnline(online));
        if (!_network.IsOnline) _model.SetOnline(false);
        _store.Changed += OnSettingsChanged;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs e) =>
        _ui.BeginInvoke(() => { if (!_disposed && _window.IsVisible) { Log.Write("window", "écrans modifiés : fenêtre ré-affichée"); _window.ShowFloating(); } });

    /// <summary>« Copier le diagnostic » : faits + 200 dernières lignes du journal, sans titre, artiste, paroles ni identifiant LRCLIB.</summary>
    private void CopyDiagnostic()
    {
        try
        {
            var text = _diagnostics.BuildReport(_model.SecretsForLog());
            for (var attempt = 1; ; attempt++)
            {
                try { System.Windows.Clipboard.SetText(text); break; }
                catch (System.Runtime.InteropServices.COMException) when (attempt < 5) { System.Threading.Thread.Sleep(80); }   // presse-papiers pris par une autre appli
            }
            Log.Write("app", $"diagnostic copié ({text.Length} caractères)");
            _model.ShowNotice("Diagnostic copié : colle-le dans un message.", 4);
        }
        catch (Exception e)
        {
            Log.WriteException("erreur", "copie du diagnostic", e);
            _model.ShowNotice("Copie impossible (voir lyra.log).", 4);
        }
    }

    public async Task StartAsync()
    {
        _window.Show();
        _window.ShowFloating();
        Log.Write("app", $"fenêtre affichée {(DateTime.Now - System.Diagnostics.Process.GetCurrentProcess().StartTime).TotalSeconds:0.0} s après le lancement du processus");
        _diagnostics.LogStartup();
        _diagnostics.StartPerfLog();
        if (_store.Current.ClickThrough) _model.ShowNotice($"Clic-à-travers activé · {_store.Current.HotKey.Display} pour le couper", 5);
        if (!_store.Current.WelcomeSeen) ShowWelcome();
        await _smtc.StartAsync();
        EvaluateAutoHide();
        _ = CheckForUpdatesAsync();
        Log.Write("app", "démarrage terminé");
    }

    // ---- A1 : accueil

    private void ShowWelcome()
    {
        if (_welcomeOpen && _welcome is not null) { _welcome.Activate(); return; }
        _welcome = new WelcomeWindow(_store.Current.HotKey.Display, () => _model.PlaybackAvailable || _smtc.SessionAppId is not null) { Start = FinishWelcome };
        _welcomeOpen = true;
        _welcome.Closed += (_, _) => { _welcomeOpen = false; FinishWelcome(); };
        _welcome.Show();
    }

    /// <summary>« Commencer » (ou fermeture) : l'accueil ne reviendra pas tout seul.</summary>
    private void FinishWelcome()
    {
        if (!_store.Current.WelcomeSeen) _store.Update(s => s.WelcomeSeen = true);
        EvaluateAutoHide();
    }

    // ---- C1 : masquage automatique (règles dans le Core : AutoHideState)

    private void EvaluateAutoHide()
    {
        if (_disposed || _evaluatingAutoHide || _welcomeOpen) return;
        if (_scene?.IsActive == true) return;            // comme le Mac : le masquage automatique attend la sortie de la Scène (Exited le relance)
        var wait = AutoHideState.GraceWait(Clock.Seconds(), _graceUntil);
        if (wait > 0) { _graceTimer.Stop(); _graceTimer.Interval = TimeSpan.FromSeconds(wait); _graceTimer.Start(); return; }
        _evaluatingAutoHide = true;
        try
        {
            var activity = _model.Activity;
            var action = _autoHide.Evaluate(_store.Current.AutoHide, activity, _window.IsVisible);
            if (action is null) return;
            Log.Write("window", $"masquage automatique : {action} (activité : {activity})");
            if (action == AutoHideState.Action.Hide) { _settingsWindow?.Close(); _window.HideFloating(); }
            else _window.ShowFloating();
        }
        finally { _evaluatingAutoHide = false; }
    }

    // ---- B1 : recherche manuelle

    private void ShowManualSearch()
    {
        if (_model.Track is null) return;
        if (!_window.IsVisible) _window.ShowFloating();
        if (_manualWindow is { IsLoaded: true }) { _manualWindow.Prepare(); _manualWindow.Activate(); return; }
        _manualWindow = new ManualSearchWindow(_model);
        _manualWindow.Prepare();
        _manualWindow.Show();
    }

    // ---- E1 : mises à jour (une requête par jour au plus, au lancement)

    private async Task CheckForUpdatesAsync()
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(8));          // comme le Mac : jamais pendant le démarrage
            if (_disposed || !_store.Current.CheckUpdates) return;
            var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
            if (!UpdateCheck.IsDue(_store.Current.LastUpdateCheck, now)) return;
            if (!_network.IsOnline) { Log.Write("app", "mises à jour : hors connexion, aucune requête"); return; }
            _store.Update(s => s.LastUpdateCheck = now);        // noté AVANT la requête : au plus une tentative par jour, même en cas d'échec
            var outcome = await _update.CheckAsync(AppIdentity.Version);
            if (_disposed) return;
            _model.UpdateRelease = (outcome as UpdateCheck.Outcome.Newer)?.Release;
            Log.Write("app", "mises à jour : " + outcome.GetType().Name);
            if (_model.UpdateRelease is { } r)
            {
                _model.ShowNotice($"Nouvelle version disponible : {r.Tag} (voir les réglages)", 6);
                _settingsWindow?.RefreshUpdate();
            }
        }
        catch (Exception e) { Log.WriteException("erreur", "vérification des mises à jour", e); }
    }

    private void OpenUpdatePage()
    {
        if (_model.UpdateRelease is { } r) LinkOpener.OpenRelease(r.Url);
    }

    private LyricsWindow CreateWindow()
    {
        var w = new LyricsWindow(_model, _store, _store.Current.SystemBackdrop)
        {
            OpenSettings = ShowSettings, OpenAbout = ShowAbout, OpenManualSearch = ShowManualSearch, OpenScene = () => _scene?.Toggle(), Playback = cmd => _ = SendPlaybackAsync(cmd),
        };
        return w;
    }

    private void OnSettingsChanged()
    {
        var s = _store.Current;
        if (s.HotKey != _lastHotKey)
        {
            _lastHotKey = s.HotKey;
            if (!_hotKey.Register(s.HotKey)) _model.ShowNotice(_hotKey.LastError ?? "Raccourci indisponible", 5);
        }
        if (s.SystemBackdrop != _lastBackdrop)
        {
            _lastBackdrop = s.SystemBackdrop;
            RecreateWindow();
        }
        EvaluateAutoHide();
    }

    /// <summary>Changer de mode de rendu (couches ↔ flou du système) exige une nouvelle fenêtre : on ferme l'ancienne et on rouvre au même endroit.</summary>
    private void RecreateWindow()
    {
        var wasVisible = _window.IsVisible;
        _store.SaveNow();
        var old = _window;
        _window = CreateWindow();
        _ui.BeginInvoke(() =>
        {
            old.Close();
            if (wasVisible) { _window.Show(); _window.ShowFloating(); }
            _model.ShowNotice(_store.Current.SystemBackdrop ? "Mode flou du système" : "Mode compatible", 2.5);
        });
    }

    /// <summary>Une seconde instance a été lancée (A3, comme sur le Mac) : on coupe le clic-à-travers, on montre la fenêtre ET on ouvre les réglages.</summary>
    public void ShowFromOtherInstance()
    {
        if (_scene.IsActive) { _scene.Exit(); return; }
        if (_store.Current.ClickThrough) _store.Update(s => s.ClickThrough = false);
        _window.ShowFloating();
        _autoHide.ManualChange(_window.IsVisible);
        ShowSettings();
    }

    private void ToggleVisibility()
    {
        if (_scene.IsActive) { _scene.Exit(); return; }          // clic sur l'icône de notification pendant la Scène : on en sort
        if (_window.IsVisible) _window.HideFloating(); else { if (!_window.IsLoaded) _window.Show(); _window.ShowFloating(); }
        _autoHide.ManualChange(_window.IsVisible);       // jamais défait par le masquage automatique
    }

    private void SetClickThrough(bool on)
    {
        _store.Update(s => s.ClickThrough = on);
        if (on) { if (!_window.IsVisible) { _window.ShowFloating(); _autoHide.ManualChange(true); } _model.ShowNotice($"Clic-à-travers activé · {_store.Current.HotKey.Display} pour le couper", 4.5); }
    }

    /// <summary>
    /// Raccourci global (décision du 2026-11-17, comme le Mac) : BASCULE le clic-à-travers dans les deux sens ; si la fenêtre est cachée, il la montre ; il ne la cache jamais
    /// (cacher / montrer = menu de l'icône). Règle pure <see cref="HotKeyRule"/>, fixture <c>golden/hotkey.json</c> partagée avec Swift.
    /// </summary>
    private void OnHotKey()
    {
        if (_scene.IsActive) { _scene.Exit(); return; }          // le raccourci global est aussi une sortie de la Scène (comme le Mac)
        var outcome = HotKeyRule.Decide(_window.IsVisible, _store.Current.ClickThrough);
        if (outcome.ShowWindow)
        {
            if (!_window.IsLoaded) _window.Show();
            _window.ShowFloating();
            _autoHide.ManualChange(_window.IsVisible);       // jamais défait par le masquage automatique
        }
        _store.Update(s => s.ClickThrough = outcome.ClickThrough);
        _model.ShowNotice(outcome.ClickThrough ? $"Clic-à-travers activé · {_store.Current.HotKey.Display} pour le couper" : "Clic-à-travers désactivé", outcome.ClickThrough ? 4.5 : 2.5);
    }

    private async Task SendPlaybackAsync(PlaybackCommand cmd)
    {
        if (!_model.PlaybackAvailable) { _model.ShowNotice("Aucune lecture Spotify en cours.", 2.5); return; }
        var ok = await _smtc.SendAsync(cmd);
        if (!ok) await _ui.InvokeAsync(() => _model.ShowNotice("Spotify n'a pas répondu à la commande.", 3));
    }

    private void ShowSettings()
    {
        if (_settingsWindow is { IsLoaded: true }) { _settingsWindow.Activate(); return; }
        _settingsWindow = new SettingsWindow(_store, _model)
        {
            TryHotKey = c => { var ok = _hotKey.Register(c); _settingsWindow!.HotKeyError = _hotKey.LastError; if (ok) _lastHotKey = c; return ok; },
            ResetSize = () => _window.ResetSize(),
            OpenAbout = ShowAbout, OpenManualSearch = ShowManualSearch, OpenWelcome = ShowWelcome, OpenUpdate = OpenUpdatePage, OpenScene = () => _scene.Toggle(),
        };
        _settingsWindow.Show();
    }

    private void ShowAbout()
    {
        if (_aboutWindow is { IsLoaded: true }) { _aboutWindow.Activate(); return; }
        _aboutWindow = new AboutWindow();
        _aboutWindow.Show();
    }

    /// <summary>Pochette (octets de l'image lus localement via SMTC) → vignette 48 px → palette. En mémoire seulement.</summary>
    private static ArtworkPalette? DecodePalette(byte[] bytes)
    {
        if (bytes.Length == 0 || bytes.Length > 8 * 1024 * 1024) return null;
        using var ms = new MemoryStream(bytes);
        var bmp = new BitmapImage();
        bmp.BeginInit();
        bmp.CacheOption = BitmapCacheOption.OnLoad;
        bmp.DecodePixelWidth = 48;
        bmp.StreamSource = ms;
        bmp.EndInit();
        var conv = new FormatConvertedBitmap(bmp, PixelFormats.Bgra32, null, 0);
        int w = conv.PixelWidth, h = conv.PixelHeight;
        var buf = new byte[w * h * 4];
        conv.CopyPixels(buf, w * 4, 0);
        for (var i = 0; i < w * h; i++) (buf[i * 4], buf[i * 4 + 2]) = (buf[i * 4 + 2], buf[i * 4]);   // BGRA → RGBA
        return ArtworkPalette.FromRgba(buf, w, h);
    }

    public void Quit()
    {
        Dispose();
        Application.Current.Shutdown();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        _graceTimer.Stop();
        _scene.Dispose();
        SystemPrefs.Stop();
        _diagnostics.Dispose();
        try { _store.SaveNow(); } catch { }
        _tray.Dispose();
        _hotKey.Dispose();
        _network.Dispose();
        _smtc.Dispose();
        _service.Cancel();
        _http.Dispose();
        Log.Write("app", "arrêt");
    }
}
