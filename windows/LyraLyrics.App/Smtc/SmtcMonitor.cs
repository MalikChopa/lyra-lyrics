using LyraLyrics.App.Services;
using LyraLyrics.Core;
using Windows.Media.Control;
using Windows.Storage.Streams;

namespace LyraLyrics.App.Smtc;

internal enum PlaybackCommand { Previous, PlayPause, Next }

/// <summary>
/// Lecture de Spotify via SMTC (GlobalSystemMediaTransportControlsSessionManager), sans consentement requis d'après la recherche 03
/// (non confirmé pour un exe non empaqueté : à vérifier sur le PC). La position est un INSTANTANÉ daté : on l'extrapole avec
/// <see cref="SmtcClock.Extrapolate"/>. Les événements WinRT arrivent sur des fils du système : tout est sérialisé ici puis
/// remis à l'interface par l'appelant.
/// </summary>
internal sealed class SmtcMonitor : IDisposable
{
    private volatile GlobalSystemMediaTransportControlsSessionManager? _manager;
    private readonly SemaphoreSlim _gate = new(1, 1);          // protège les champs en cache (_cachedIdentity, _cachedTrack, …) : relevé ET rattachement
    private readonly Timer _poll;
    private readonly SessionBinder<GlobalSystemMediaTransportControlsSession> _binder;
    private string? _cachedIdentity;
    private TrackInfo? _cachedTrack;
    private int _mediaVersion;
    private int _loggedEvents;
    private volatile bool _disposed;
    private long _nextManagerAttempt;
    private int _managerBusy;
    private volatile string _lastIds = "\0";

    public event Action<SmtcUpdate>? Updated;
    /// <summary>Miniature de la pochette (octets PNG/JPEG), lue localement via SMTC : aucune requête réseau.</summary>
    public event Action<string, byte[]>? ArtworkReady;
    public string? SessionAppId { get { try { return _binder.Current?.SourceAppUserModelId; } catch { return null; } } }
    /// <summary>Dernière liste d'applis média vue (noms d'exe, jamais de titre) : pour le diagnostic.</summary>
    public string KnownSessionIds => _lastIds == "\0" ? "(pas encore relevé)" : "[" + _lastIds + "]";

    public SmtcMonitor()
    {
        _binder = new SessionBinder<GlobalSystemMediaTransportControlsSession>(PickSpotify, s => s.SourceAppUserModelId, Subscribe, Unsubscribe, m => Log.Write("smtc", m));
        _poll = new Timer(_ => { try { _ = RefreshAsync("poll"); } catch { } }, null, Timeout.Infinite, Timeout.Infinite);
    }

    /// <summary>
    /// Démarre le sondage de 1 s dans tous les cas (constat 19) : si <c>RequestAsync()</c> échoue ici, le sondage retente toutes les 10 s
    /// jusqu'à obtenir le gestionnaire de sessions.
    /// </summary>
    public async Task StartAsync()
    {
        _poll.Change(TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(1));
        if (await EnsureManagerAsync().ConfigureAwait(false)) await AttachAndRefreshAsync("start").ConfigureAwait(false);
        else Updated?.Invoke(new SmtcUpdate(false, null, PlaybackState.Stopped, null, null, Clock.Seconds(), true));
    }

    private async Task<bool> EnsureManagerAsync()
    {
        if (_manager is not null) return true;
        if (Environment.TickCount64 < Interlocked.Read(ref _nextManagerAttempt)) return false;
        if (Interlocked.Exchange(ref _managerBusy, 1) == 1) return false;
        try
        {
            Interlocked.Exchange(ref _nextManagerAttempt, Environment.TickCount64 + 10_000);
            var m = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
            m.SessionsChanged += (_, _) => { Log.Write("smtc", "SessionsChanged"); _ = AttachAndRefreshAsync("sessions", force: true); };
            m.CurrentSessionChanged += (_, _) => { Log.Write("smtc", "CurrentSessionChanged"); _ = AttachAndRefreshAsync("current"); };
            _manager = m;
            Log.Write("smtc", "gestionnaire de sessions obtenu");
            return true;
        }
        catch (Exception e)
        {
            Log.Write("smtc", "démarrage impossible (nouvel essai dans 10 s) : " + e.GetType().Name + " 0x" + e.HResult.ToString("x"));
            return false;
        }
        finally { Interlocked.Exchange(ref _managerBusy, 0); }
    }

    private GlobalSystemMediaTransportControlsSession? PickSpotify()
    {
        var manager = _manager;
        if (manager is null) return null;
        var sessions = manager.GetSessions();
        var ids = string.Join(",", sessions.Select(s => s.SourceAppUserModelId));
        if (ids != _lastIds) { _lastIds = ids; Log.Write("smtc", "sessions=[" + ids + "]"); }
        return sessions.FirstOrDefault(s => SmtcClock.IsSpotifySession(s.SourceAppUserModelId));
    }

    private void Subscribe(GlobalSystemMediaTransportControlsSession s)
    {
        s.MediaPropertiesChanged += OnMedia;
        s.PlaybackInfoChanged += OnPlayback;
        s.TimelinePropertiesChanged += OnTimeline;
    }

    private void Unsubscribe(GlobalSystemMediaTransportControlsSession s)
    {
        s.MediaPropertiesChanged -= OnMedia;
        s.PlaybackInfoChanged -= OnPlayback;
        s.TimelinePropertiesChanged -= OnTimeline;
    }

    /// <summary>Rattache (sous le verrou des champs en cache : constat 19) puis relève.</summary>
    private async Task AttachAndRefreshAsync(string why, bool force = false)
    {
        if (_disposed) return;
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_binder.Rebind(force)) { _cachedIdentity = null; _cachedTrack = null; }
        }
        catch (Exception e) { Log.Write("smtc", "attache : " + e.GetType().Name + " 0x" + e.HResult.ToString("x")); }
        finally { _gate.Release(); }
        await RefreshAsync(why).ConfigureAwait(false);
    }

    private void LogEvent(string name)
    {
        // Mesure de cadence (recherche 03, risque n° 1) : les 400 premiers événements sont consignés avec horodatage et position, sans titre.
        var session = _binder.Current;
        if (_loggedEvents >= 400 || session is null) return;
        _loggedEvents++;
        try
        {
            var t = session.GetTimelineProperties();
            Log.Write("smtc-evt", $"{name} pos={t.Position.TotalSeconds:0.000} start={t.StartTime.TotalSeconds:0.0} end={t.EndTime.TotalSeconds:0.000} lastUpdated={t.LastUpdatedTime.UtcDateTime:HH:mm:ss.fff}Z");
        }
        catch { }
    }

    private void OnMedia(GlobalSystemMediaTransportControlsSession s, MediaPropertiesChangedEventArgs a) { Interlocked.Increment(ref _mediaVersion); LogEvent("MediaPropertiesChanged"); _ = RefreshAsync("media"); }
    private void OnPlayback(GlobalSystemMediaTransportControlsSession s, PlaybackInfoChangedEventArgs a) { LogEvent("PlaybackInfoChanged"); _ = RefreshAsync("playback"); }
    private void OnTimeline(GlobalSystemMediaTransportControlsSession s, TimelinePropertiesChangedEventArgs a) { LogEvent("TimelinePropertiesChanged"); _ = RefreshAsync("timeline"); }

    private async Task RefreshAsync(string why)
    {
        if (_disposed) return;
        if (_manager is null)
        {
            // Le gestionnaire n'a pas pu être obtenu au démarrage : on retente (au plus toutes les 10 s) à chaque tour de sondage.
            if (why != "poll") return;
            if (!await EnsureManagerAsync().ConfigureAwait(false))
            {
                Updated?.Invoke(new SmtcUpdate(false, null, PlaybackState.Stopped, null, null, Clock.Seconds(), true));
                return;
            }
            await AttachAndRefreshAsync("manager-ok").ConfigureAwait(false);
            return;
        }
        if (why == "poll" && _binder.Current is null)
        {
            // Constat 2 : Spotify peut être apparu sans événement. Le rattachement a lieu ICI, hors du try / finally du relevé
            // (l'ancien `return` dans le try empêchait d'aller plus loin).
            bool reattached;
            try { reattached = await _binder.PollAsync(() => ResetCachesThenRefreshAsync()).ConfigureAwait(false); }
            catch (Exception e) { Log.Write("smtc", "sondage : " + e.GetType().Name + " 0x" + e.HResult.ToString("x")); reattached = false; }
            if (reattached) return;
        }
        if (!await _gate.WaitAsync(0).ConfigureAwait(false)) return;      // un relevé est déjà en cours : le prochain (1 s) rattrapera
        try
        {
            var session = _binder.Current;
            if (session is null)
            {
                Updated?.Invoke(new SmtcUpdate(false, null, PlaybackState.Stopped, null, null, Clock.Seconds(), true));
                return;
            }

            var playback = session.GetPlaybackInfo();
            var status = playback.PlaybackStatus;
            var rate = playback.PlaybackRate ?? 1.0;
            var timeline = session.GetTimelineProperties();
            var start = timeline.StartTime.TotalSeconds;
            var end = timeline.EndTime.TotalSeconds;
            var state = status switch
            {
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing => PlaybackState.Playing,
                GlobalSystemMediaTransportControlsSessionPlaybackStatus.Stopped or GlobalSystemMediaTransportControlsSessionPlaybackStatus.Closed => PlaybackState.Stopped,
                _ => PlaybackState.Paused,
            };

            // Métadonnées : relues quand elles ont changé (événement) ou si on n'en a pas encore.
            var version = Volatile.Read(ref _mediaVersion);
            if (_cachedTrack is null || version != _cachedVersion)
            {
                var props = await session.TryGetMediaPropertiesAsync();
                var title = props.Title ?? "";
                var artist = props.Artist ?? "";
                var album = props.AlbumTitle;
                if (title.Length > 0 && !SmtcClock.LooksLikeAdvertisement(title, artist))
                {
                    var identity = new TrackInfo(title, artist, string.IsNullOrWhiteSpace(album) ? null : album, null, null, "spotify").Identity;
                    if (identity != _cachedIdentity)
                    {
                        _cachedIdentity = identity;
                        _cachedVersion = version;
                        _cachedTrack = new TrackInfo(title, artist, string.IsNullOrWhiteSpace(album) ? null : album, null, null, "spotify");
                        _ = FetchArtworkAsync(props, identity);
                    }
                    else _cachedVersion = version;
                }
                else
                {
                    _cachedTrack = null; _cachedIdentity = null; _cachedVersion = version;     // titre vide (transition) ou publicité
                }
            }

            var duration = SmtcClock.Duration(start, end);
            double? position = null;
            var plausible = true;
            if (_cachedTrack is not null && state != PlaybackState.Stopped)
            {
                var p = SmtcClock.Extrapolate(timeline.Position.TotalSeconds, timeline.LastUpdatedTime, DateTimeOffset.UtcNow, rate, state == PlaybackState.Playing, start, end);
                plausible = SmtcClock.IsPlausible(p, duration);
                position = p;
            }
            _failures = 0;
            var track = _cachedTrack is null ? null : _cachedTrack with { Duration = duration };
            Updated?.Invoke(new SmtcUpdate(true, track, track is null ? PlaybackState.Stopped : state, position, duration, Clock.Seconds(), plausible));
        }
        catch (Exception e)
        {
            Log.Write("smtc", $"relevé ({why}) : {e.GetType().Name} 0x{e.HResult:x}");
            // Session morte (Spotify fermé ou relancé sans événement) : après 3 échecs de suite on la lâche, le sondage en cherchera une neuve.
            if (++_failures >= 3) { _failures = 0; _binder.Detach(); _cachedTrack = null; _cachedIdentity = null; Log.Write("smtc", "session abandonnée après 3 échecs"); }
        }
        finally { _gate.Release(); }
    }

    private async Task ResetCachesThenRefreshAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try { _cachedIdentity = null; _cachedTrack = null; }
        finally { _gate.Release(); }
        await RefreshAsync("poll-found").ConfigureAwait(false);
    }
    private int _cachedVersion = -1;
    private int _failures;

    private async Task FetchArtworkAsync(GlobalSystemMediaTransportControlsSessionMediaProperties props, string identity)
    {
        try
        {
            var thumb = props.Thumbnail;
            if (thumb is null) { ArtworkReady?.Invoke(identity, Array.Empty<byte>()); return; }
            using IRandomAccessStreamWithContentType stream = await thumb.OpenReadAsync();
            if (stream.Size == 0 || stream.Size > 8 * 1024 * 1024) { ArtworkReady?.Invoke(identity, Array.Empty<byte>()); return; }
            using var net = stream.AsStreamForRead();
            using var ms = new MemoryStream();
            await net.CopyToAsync(ms);
            ArtworkReady?.Invoke(identity, ms.ToArray());
        }
        catch (Exception e)
        {
            Log.Write("smtc", "pochette : " + e.GetType().Name);
            ArtworkReady?.Invoke(identity, Array.Empty<byte>());
        }
    }

    /// <summary>Commande de lecture. Rend faux si Spotify ne répond pas (ou s'il n'y a pas de session).</summary>
    public async Task<bool> SendAsync(PlaybackCommand command)
    {
        try
        {
            var s = _binder.Current;
            if (s is null) return false;
            var ok = command switch
            {
                PlaybackCommand.Previous => await s.TrySkipPreviousAsync(),
                PlaybackCommand.Next => await s.TrySkipNextAsync(),
                _ => await s.TryTogglePlayPauseAsync(),
            };
            Log.Write("smtc", $"commande {command} -> {ok}");
            return ok;
        }
        catch (Exception e) { Log.Write("smtc", "commande : " + e.GetType().Name); return false; }
    }

    public void Dispose()
    {
        _disposed = true;
        _poll.Dispose();
        _binder.Detach();
    }
}
