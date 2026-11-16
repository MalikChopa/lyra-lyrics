using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Adaptateur mince autour de <see cref="PlaybackModel"/> (Core, pur, testé sur Mac) : branche les relevés SMTC et les événements du service
/// sur le fil de l'interface, fournit l'horloge et le minuteur (10 Hz, allumé seulement quand <see cref="PlaybackModel.WantsTimer"/>),
/// décode la pochette. Aucune règle d'état ici.
/// </summary>
internal sealed class AppModel : IPlaybackEffects
{
    private readonly Dispatcher _ui;
    private readonly LyricsService _service;
    private readonly SmtcMonitor _smtc;
    private readonly DispatcherTimer _timer;
    private readonly PlaybackModel _m;

    /// <summary>Un changement visible a eu lieu (lignes, état, palette, avis).</summary>
    public event Action? Changed;

    public Func<byte[], ArtworkPalette?>? PaletteDecoder { get; set; }
    public Func<bool>? ArtworkEnabled { get; set; }

    public AppModel(Dispatcher ui, LyricsService service, SmtcMonitor smtc)
    {
        _ui = ui; _service = service; _smtc = smtc;
        _m = new PlaybackModel(Clock.Seconds, this);
        _m.Changed += () => { Changed?.Invoke(); UpdateTimer(); };
        _timer = new DispatcherTimer(DispatcherPriority.Normal, ui) { Interval = TimeSpan.FromMilliseconds(100) };
        _timer.Tick += (_, _) => { _m.Tick(); UpdateTimer(); };
        _smtc.Updated += u => _ui.BeginInvoke(() => { _m.OnUpdate(u); UpdateTimer(); });
        _smtc.ArtworkReady += (id, bytes) => _ui.BeginInvoke(() => OnArtwork(id, bytes));
    }

    private void UpdateTimer()
    {
        if (_m.WantsTimer && !_timer.IsEnabled) _timer.Start();
        else if (!_m.WantsTimer && _timer.IsEnabled) _timer.Stop();
    }

    // ---- Effets demandés par le modèle

    /// <summary>Mode captures (<c>--snapshot</c>) : aucune recherche, aucun appel réseau ; le contenu est inventé et injecté par <see cref="LoadDemo"/>.</summary>
    public bool Offline { get; set; }

    void IPlaybackEffects.StartLookup(TrackInfo track, string identity)
    {
        if (Offline) return;
        _ = _service.LookupAsync(track, e => _ui.BeginInvoke(() => _m.OnServiceEvent(e, identity)));
    }
    void IPlaybackEffects.RetryLookup(TrackInfo track, string identity)
    {
        if (Offline) return;
        _ = _service.RetryAsync(track, e => _ui.BeginInvoke(() => _m.OnServiceEvent(e, identity)));
    }
    void IPlaybackEffects.RevertToAutomatic(TrackInfo track, string identity) =>
        _ = _service.RevertToAutomaticAsync(track, e => _ui.BeginInvoke(() => _m.OnServiceEvent(e, identity)));
    void IPlaybackEffects.CancelLookup() => _service.Cancel();
    void IPlaybackEffects.SetServiceOnline(bool online) => _service.SetOnline(online);
    void IPlaybackEffects.ClearCache() => _service.ClearAll();
    void IPlaybackEffects.Log(string zone, string message) => Log.Write(zone, message);

    // ---- Lecture seule pour la vue (tout vient du modèle)

    public DisplayState Display => _m.Display;
    public TrackInfo? Track => _m.Track;
    public Lyrics? Lyrics => _m.Lyrics;
    public int CurrentIndex => _m.CurrentIndex;
    public double ManualOffset => _m.ManualOffset;
    public double BusyRetryIn => _m.BusyRetryIn;
    public UnsyncedScrollPlan UnsyncedScroll => _m.UnsyncedScroll;
    public ArtworkPalette? Palette => _m.Palette;
    public int TrackEpoch => _m.TrackEpoch;
    public string? Notice => _m.Notice;
    public string LastLookup => _m.LastLookup;
    public bool SmtcAvailable => _m.SmtcAvailable;
    public bool IsPaused => _m.IsPaused;
    public bool SearchHint => _m.SearchHint;
    public string PlainText => _m.PlainText;
    public (string Title, string? Artist) BarText => _m.BarText;
    public string? StateActionLabel => _m.StateActionLabel;
    public string? SecondaryActionLabel => _m.SecondaryActionLabel;
    public bool IsManualChoice => _m.IsManualChoice;
    public PlaybackActivity Activity => _m.Activity;
    /// <summary>Nouvelle version annoncée par la vérification quotidienne (E1), null sinon.</summary>
    public UpdateCheck.Release? UpdateRelease { get; set; }
    /// <summary>Position de lecture estimée (secondes) et position dans les paroles (avance et décalage compris).</summary>
    public double Position => _m.Position;
    public double LyricPosition => _m.LyricPosition;
    public bool IsPlaying => _m.IsPlaying;
    public IEnumerable<string> SecretsForLog() => _m.SecretsForLog();
    public IReadOnlyList<LineItem> LineItems(int count) => _m.LineItems(count);
    public bool PlaybackAvailable => _m.Track is not null && _smtc.SessionAppId is not null;

    // ---- Actions

    public void RetryLookup() { _m.RetryLookup(); UpdateTimer(); }

    // ---- Recherche manuelle (B1)

    /// <summary>UNE requête LRCLIB par appel ; métadonnées seulement.</summary>
    public Task<ManualSearchOutcome> SearchVersionsAsync(string title, string artist) => _service.SearchAsync(title, artist);

    /// <summary>Utilise la version choisie pour le titre en cours et la mémorise (identifiant seulement). Faux si elle n'est plus en mémoire.</summary>
    public bool ChooseVersion(int id)
    {
        if (_m.LookupTrack is not { } info) return false;
        var identity = info.Identity;
        var ok = _service.Choose(id, info, e => _m.OnServiceEvent(e, identity));
        Log.Write("lookup", ok ? "version choisie à la main" : "version choisie introuvable");     // D6 : jamais d'identifiant LRCLIB
        UpdateTimer();
        return ok;
    }

    /// <summary>« Revenir au choix automatique » : oublie le choix mémorisé et relance la recherche normale.</summary>
    public void RevertToAutomatic() { _m.RevertToAutomatic(); UpdateTimer(); }
    public void SetOnline(bool online) { _m.SetOnline(online); UpdateTimer(); }
    public void SetManualOffset(double value) => _m.SetManualOffset(value);
    public void AdjustOffset(double delta) => _m.AdjustOffset(delta);
    public void ClearCache() => _service.ClearAll();
    public void ShowNotice(string text, double seconds = 3.5) { _m.ShowNotice(text, seconds); UpdateTimer(); }
    // Le minuteur et les publications du modèle continuent tant que la petite fenêtre OU la Scène est affichée (comme le Mac : setSceneVisible).
    private bool _smallVisible, _sceneVisible;
    public bool SceneVisible => _sceneVisible;
    public void SetWindowVisible(bool visible) { _smallVisible = visible; _m.SetWindowVisible(_smallVisible || _sceneVisible); UpdateTimer(); }
    public void SetSceneVisible(bool visible) { _sceneVisible = visible; _m.SetWindowVisible(_smallVisible || _sceneVisible); UpdateTimer(); }
    /// <summary>Redimensionnement ou autre événement de mise en page : le défilement non synchronisé est ré-armé (une seule animation).</summary>
    public void RefreshUnsyncedScroll() => _m.RefreshUnsynced(force: true);
    public void RefreshPaletteVisibility() => _m.Touch();

    /// <summary>Mode captures : injecte un titre INVENTÉ, ses paroles inventées, une position et (option) une pochette générée. Jamais appelé hors <c>--snapshot</c>.</summary>
    public void LoadDemo(TrackInfo track, Lyrics lyrics, double position, bool playing, byte[]? artwork, ArtworkPalette? palette)
    {
        Offline = true;
        var now = Clock.Seconds();
        _m.OnUpdate(new SmtcUpdate(true, track, playing ? PlaybackState.Playing : PlaybackState.Paused, position, track.Duration, now, true));
        _m.OnServiceEvent(new LyricsServiceEvent.Found(lyrics, false), track.Identity);
        _m.OnUpdate(new SmtcUpdate(true, track, playing ? PlaybackState.Playing : PlaybackState.Paused, position, track.Duration, Clock.Seconds(), true));
        if (artwork is not null) { _artIdentity = track.Identity; _artBytes = artwork; ArtworkRevision++; }
        if (palette is not null) _m.SetPalette(track.Identity, palette);
        _m.Tick();
    }

    // ---- Pochette

    private string? _artIdentity;
    private byte[] _artBytes = Array.Empty<byte>();
    /// <summary>Octets de la pochette du titre en cours (lus localement via SMTC, en mémoire seulement) ; null s'il n'y en a pas (encore).</summary>
    public byte[]? ArtworkBytes => _artBytes.Length > 0 && _artIdentity == _m.Track?.Identity ? _artBytes : null;
    /// <summary>Change à chaque nouvelle pochette reçue.</summary>
    public int ArtworkRevision { get; private set; }

    private void OnArtwork(string identity, byte[] bytes)
    {
        if (identity != _m.Track?.Identity) return;
        _artIdentity = identity; _artBytes = bytes; ArtworkRevision++;
        if (ArtworkEnabled?.Invoke() == false || bytes.Length == 0) { _m.SetPalette(identity, null); return; }
        try { _m.SetPalette(identity, PaletteDecoder?.Invoke(bytes)); }
        catch (Exception e) { Log.Write("model", "palette : " + e.GetType().Name); _m.SetPalette(identity, null); }
    }
}
