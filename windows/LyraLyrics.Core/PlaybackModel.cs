namespace LyraLyrics.Core;

/// <summary>Photographie de la session Spotify à un instant (rien ici ne contient de paroles). <c>At</c> : instant monotone (s).</summary>
public sealed record SmtcUpdate(bool HasSession, TrackInfo? Track, PlaybackState State, double? Position, double? Duration, double At, bool PositionPlausible);

/// <summary>Une ligne affichée (clé stable d'un état à l'autre, pour animer le défilement).</summary>
public sealed record LineItem(string Key, int Order, int Offset, string Text, bool Dim = false);

/// <summary>Ce que le modèle demande au monde extérieur (service des paroles, journal). Les réponses reviennent par <see cref="PlaybackModel.OnServiceEvent"/>.</summary>
public interface IPlaybackEffects
{
    /// <summary>Lance la recherche des paroles (durée éventuellement inconnue après 0,6 s d'attente).</summary>
    void StartLookup(TrackInfo track, string identity);
    /// <summary>« Réessayer » : recherche relancée de zéro.</summary>
    void RetryLookup(TrackInfo track, string identity);
    /// <summary>« Revenir au choix automatique » (1.1.0, B1) : oublie le choix mémorisé puis recherche normale. Par défaut : comme « Réessayer ».</summary>
    void RevertToAutomatic(TrackInfo track, string identity) => RetryLookup(track, identity);
    void CancelLookup();
    void SetServiceOnline(bool online);
    void ClearCache();
    void Log(string zone, string message);
}

/// <summary>
/// Modèle de lecture PUR (constat 13 ; port des règles d'AppModel.swift) : aucune dépendance à une interface, un minuteur ou un fil.
/// Entrées : relevés SMTC (<see cref="OnUpdate"/>), événements du service (<see cref="OnServiceEvent"/>), horloge injectée (<see cref="Tick"/>),
/// actions (décalage, « Réessayer », réseau, visibilité). Sorties : <see cref="Display"/>, lignes, indice courant, plan de défilement, avis.
/// Un seul appelant à la fois (l'adaptateur de l'app sérialise sur le fil de l'interface). Les paroles ne vivent qu'en mémoire.
/// </summary>
public sealed class PlaybackModel
{
    public const double HintDelay = 1.5, DurationWait = 0.6;

    private readonly Func<double> _clock;
    private readonly IPlaybackEffects _fx;
    private readonly PositionEstimator _estimator = new();
    private readonly TrackGuard _guard = new();
    private SyncEngine _engine = new();
    private bool _allowBackwardOnce;
    private bool _windowVisible = true;
    private double? _freshDuration;
    private double? _hintDueAt;
    private double? _noticeUntil;
    private (TrackInfo Info, string Identity, double Deadline)? _deferredLookup;
    private double _unsyncedAt;

    public DisplayState Display { get; private set; } = DisplayState.Initial;
    public TrackInfo? Track { get; private set; }
    public Lyrics? Lyrics { get; private set; }
    public int CurrentIndex { get; private set; } = -1;
    public double ManualOffset { get; private set; }
    public double BusyRetryIn { get; private set; }
    public UnsyncedScrollPlan UnsyncedScroll { get; private set; }
    public ArtworkPalette? Palette { get; private set; }
    public int TrackEpoch { get; private set; }
    public string? Notice { get; private set; }
    public string LastLookup { get; private set; } = "";
    public bool SmtcAvailable { get; private set; } = true;
    public bool WindowVisible => _windowVisible;
    /// <summary>Le titre tel que le service le cherche (avec la durée fraîche) : même clé d'index pour un choix manuel et pour la recherche normale.</summary>
    public TrackInfo? LookupTrack => Track is { } t ? t with { Duration = t.Duration ?? _freshDuration } : null;
    /// <summary>Nombre de recherches lancées (diagnostic, tests).</summary>
    public int LookupsStarted { get; private set; }

    /// <summary>Un changement visible a eu lieu (lignes, état, palette, avis, plan de défilement).</summary>
    public event Action? Changed;

    public PlaybackModel(Func<double> clock, IPlaybackEffects effects) { _clock = clock; _fx = effects; }

    // ---- Dérivés pour la vue

    public bool IsPaused => Display.Paused;
    public bool IsPlaying => _estimator.IsPlaying && !Display.Paused;
    public bool SearchHint => Display.Current is DisplayState.Screen.Searching { Hint: true };
    public string PlainText => Lyrics?.PlainText ?? "";
    public int LineCountTotal => _engine.Lines.Count;
    public double Position => _estimator.Estimate(_clock());
    /// <summary>Position dans les paroles (position estimée + avance + décalage manuel), comme pour le choix de la ligne (Mac : lyricPosition).</summary>
    public double LyricPosition => _engine.EffectivePosition(Position);

    public (string Title, string? Artist) BarText =>
        Track is null ? (Display.BarTitleWhenIdle ?? "Aucune lecture", null) : (Track.Title, IsPaused ? $"{Track.Artist} · En pause" : Track.Artist);

    /// <summary>Valeurs à masquer dans le journal et le diagnostic : titre et artiste en cours (deuxième barrière, D6).</summary>
    public IEnumerable<string> SecretsForLog() => Track is { } t ? new[] { t.Title, t.Artist } : Array.Empty<string>();

    /// <summary>Libellé du bouton de l'état affiché (null : pas de bouton).</summary>
    public string? StateActionLabel => Display.Current is DisplayState.Screen.Unavailable or DisplayState.Screen.Busy ? "Réessayer" : null;

    /// <summary>Second bouton des états « Paroles indisponibles » et « Service occupé » (B1, ligne 22 de l'audit), comme le Mac.</summary>
    public string? SecondaryActionLabel => Display.Current is DisplayState.Screen.Unavailable or DisplayState.Screen.Busy ? "Chercher une version" : null;

    /// <summary>Ce que fait la lecture (C1) : rien (aucun titre), en pause, ou en lecture.</summary>
    public PlaybackActivity Activity => Track is null ? PlaybackActivity.Nothing : (Display.Paused ? PlaybackActivity.Paused : PlaybackActivity.Playing);

    /// <summary>La version affichée est un choix de l'utilisateur (le texte de provenance commence par « choix manuel »).</summary>
    public bool IsManualChoice => Lyrics?.Provenance.StartsWith("choix manuel", StringComparison.Ordinal) == true;

    /// <summary>
    /// Le minuteur de l'adaptateur doit tourner : lignes synchronisées à suivre (fenêtre visible, lecture en cours), OU une échéance en attente
    /// (indice « Recherche… » à 1,5 s, durée attendue 0,6 s, avis passager). Le bloc non synchronisé n'en a pas besoin (animation unique, D1).
    /// </summary>
    public bool WantsTimer =>
        _hintDueAt is not null || _deferredLookup is not null || _noticeUntil is not null
        || (_windowVisible && _estimator.IsPlaying && !Display.Paused && Display.Current is DisplayState.Screen.SyncedScreen);

    /// <summary>Lignes affichées (<paramref name="count"/> entrées, la courante au milieu).</summary>
    public IReadOnlyList<LineItem> LineItems(int count)
    {
        var r = count / 2;
        var list = new List<LineItem>(count);
        switch (Display.Current)
        {
            case DisplayState.Screen.SyncedScreen:
            {
                var lines = _engine.Lines;
                if (CurrentIndex < 0)
                {
                    for (var o = -r; o <= r; o++)
                    {
                        var i = o - 1;
                        if (o == 0) list.Add(new LineItem("ph", -1, 0, SyncEngine.Placeholder));
                        else if (o > 0 && i < lines.Count) list.Add(new LineItem($"L{i}", i, o, lines[i].Text));
                        else list.Add(new LineItem($"b{(o < 0 ? o - 1 : i)}", o < 0 ? o - 1 : i, o, ""));
                    }
                    return list;
                }
                var index = Math.Min(CurrentIndex, Math.Max(lines.Count - 1, 0));
                for (var o = -r; o <= r; o++)
                {
                    var i = index + o;
                    list.Add(i >= 0 && i < lines.Count ? new LineItem($"L{i}", i, o, lines[i].Text) : new LineItem($"b{i}", i, o, ""));
                }
                return list;
            }
            case DisplayState.Screen.Searching s:
                for (var o = -r; o <= r; o++)
                    list.Add(o == 0 ? new LineItem("s0", 0, 0, s.Hint ? "Recherche des paroles…" : "", Dim: true) : new LineItem($"s{o}", o, o, ""));
                return list;
            default:
                for (var o = -r; o <= r; o++) list.Add(new LineItem($"e{o}", o, o, ""));
                return list;
        }
    }

    // ---- Relevés SMTC

    public void OnUpdate(SmtcUpdate u)
    {
        SmtcAvailable = true;
        if (!u.HasSession || u.Track is null)
        {
            if (Track is not null || Display.HasTrack) HandleStop();
            Raise();
            return;
        }
        var identity = u.Track.Identity;
        if (Track?.Identity != identity)
        {
            _freshDuration = u.Duration;       // durée du NOUVEAU titre (null tant que Windows ne l'a pas donnée) : jamais celle de l'ancien
            // Position implausible = celle de l'ancien titre : on attend l'instantané suivant, mais au plus TrackGuard.MaxWaitSeconds
            // (constat 8) : au-delà, le titre est chargé quand même (position inconnue : première ligne « ♪ » jusqu'à un relevé plausible).
            var verdict = _guard.Decide(identity, u.PositionPlausible, u.At);
            if (verdict == TrackGuard.Verdict.Wait) { Raise(); return; }
            if (verdict == TrackGuard.Verdict.StartForced) _fx.Log("model", $"garde de piste levée après {TrackGuard.MaxWaitSeconds:0} s (position restée implausible)");
            StartTrack(u.Track);
        }
        else
        {
            _guard.Reset();
            if (u.Duration is double known)
            {
                _freshDuration = known;
                if (_deferredLookup is { } d && d.Identity == identity) { _deferredLookup = null; Launch(d.Info with { Duration = known }, identity); }
            }
        }
        // Une position implausible n'alimente jamais l'estimateur (elle ferait sauter les lignes).
        if (!u.PositionPlausible) u = u with { Position = null };
        ApplyReading(u);
        Raise();
    }

    private void StartTrack(TrackInfo info)
    {
        Track = info;
        TrackEpoch++;
        Lyrics = null; CurrentIndex = -1; ManualOffset = 0; BusyRetryIn = 0;
        UnsyncedScroll = new UnsyncedScrollPlan(0, 0, UnsyncedScroll.Stamp + 1);
        Palette = null;
        _engine = new SyncEngine(); _estimator.Reset(); LastLookup = "";
        Display = DisplayState.Reduce(Display, new DisplayState.Event.TrackChanged());
        _fx.Log("model", $"nouveau titre (durée {(info.Duration is not null ? "connue" : "inconnue")}) -> écran {Display.Current.Name}");
        var identity = info.Identity;
        // Si la durée n'est pas encore connue, on attend jusqu'à 0,6 s qu'un relevé la fournisse (une durée améliore le choix).
        if (info.Duration is null && _freshDuration is null) _deferredLookup = (info, identity, _clock() + DurationWait);
        else { _deferredLookup = null; Launch(info with { Duration = info.Duration ?? _freshDuration }, identity); }
        ScheduleHint();
    }

    private void Launch(TrackInfo info, string identity) { LookupsStarted++; _fx.StartLookup(info, identity); }

    private void ApplyReading(SmtcUpdate u)
    {
        if (u.Position is not double p)
        {
            // Pas de position (arrêt ou pause sans instantané) : on traite comme une pause pour figer les lignes.
            if (u.State != PlaybackState.Playing) Display = DisplayState.Reduce(Display, new DisplayState.Event.Paused());
            RefreshUnsynced(force: true);
            return;
        }
        var kind = _estimator.Apply(new PlaybackReading(p, u.At, u.State));
        if (kind != PositionEstimator.Recalibration.Silent) _allowBackwardOnce = true;
        var wasPaused = Display.Paused;
        Display = DisplayState.Reduce(Display, u.State == PlaybackState.Paused ? new DisplayState.Event.Paused() : new DisplayState.Event.Resumed());
        if (wasPaused != Display.Paused) _allowBackwardOnce = true;
        EvaluateLine(_clock());
        RefreshUnsynced(force: wasPaused != Display.Paused);
    }

    private void HandleStop()
    {
        _guard.Reset();
        _fx.CancelLookup();
        _hintDueAt = null; _deferredLookup = null;
        Track = null; Lyrics = null; CurrentIndex = -1; ManualOffset = 0; BusyRetryIn = 0; TrackEpoch++;
        UnsyncedScroll = new UnsyncedScrollPlan(0, 0, UnsyncedScroll.Stamp + 1);
        _engine = new SyncEngine(); _estimator.Reset(); LastLookup = ""; Palette = null;
        Display = DisplayState.Reduce(Display, new DisplayState.Event.Stopped());
    }

    // ---- Service des paroles

    public void OnServiceEvent(LyricsServiceEvent e, string identity)
    {
        if (identity != Track?.Identity) return;
        switch (e)
        {
            case LyricsServiceEvent.Searching: break;
            case LyricsServiceEvent.Retrying:
                Display = DisplayState.Reduce(Display, new DisplayState.Event.WaitEnded());
                ScheduleHint();
                break;
            case LyricsServiceEvent.Busy b:
                BusyRetryIn = b.RetryIn;
                Display = DisplayState.Reduce(Display, new DisplayState.Event.ServiceBusy(b.RetryIn));   // compte à rebours : le service renvoie Busy avec un délai décroissant
                LastLookup = $"occupé ({b.Reason})";
                break;
            case LyricsServiceEvent.Offline:
                Display = DisplayState.Reduce(Display, new DisplayState.Event.WentOffline());
                break;
            case LyricsServiceEvent.Found f:
                Lyrics = f.Lyrics;
                LastLookup = f.Cached ? "cache" : f.Lyrics.Provenance;
                _hintDueAt = null;
                ShowLyrics(f.Lyrics, newlyFound: true);
                break;
            case LyricsServiceEvent.NotFound n:
                LastLookup = n.Reason;
                Display = DisplayState.Reduce(Display, new DisplayState.Event.NotFound());
                break;
            case LyricsServiceEvent.Stalled st:
                BusyRetryIn = 0;
                LastLookup = $"service occupé ({st.Reason})";
                Display = DisplayState.Reduce(Display, new DisplayState.Event.ServiceStalled());
                break;
        }
        _fx.Log("model", $"service -> écran {Display.Current.Name}");       // D6 : LastLookup (provenance, identifiant LRCLIB) reste en mémoire, jamais dans le journal
        Raise();
    }

    private void ShowLyrics(Lyrics l, bool newlyFound)
    {
        switch (l.Kind)
        {
            case LyricsKind.Synced:
                if (newlyFound) _engine = new SyncEngine(l.Lines, ManualOffset);
                Display = DisplayState.Reduce(Display, new DisplayState.Event.LyricsSynced());
                _allowBackwardOnce = true;
                EvaluateLine(_clock());
                break;
            case LyricsKind.Plain:
                Display = DisplayState.Reduce(Display, new DisplayState.Event.LyricsUnsynced());
                RefreshUnsynced(force: true);
                break;
            default: Display = DisplayState.Reduce(Display, new DisplayState.Event.Instrumental()); break;
        }
    }

    /// <summary>Bouton « Réessayer » : recherche relancée de zéro pour le titre courant.</summary>
    public void RetryLookup()
    {
        if (Track is not { } info || Display.Current is not (DisplayState.Screen.Unavailable or DisplayState.Screen.Busy)) return;
        Display = DisplayState.Reduce(Display, new DisplayState.Event.TrackChanged());
        Lyrics = null; LastLookup = "nouvel essai demandé"; BusyRetryIn = 0;
        LookupsStarted++;
        _fx.RetryLookup(info with { Duration = info.Duration ?? _freshDuration }, info.Identity);
        ScheduleHint();
        Raise();
    }

    /// <summary>« Revenir au choix automatique » : l'affichage repart de « Recherche… », le service oublie le choix et cherche normalement.</summary>
    public void RevertToAutomatic()
    {
        if (Track is not { } info) return;
        Display = DisplayState.Reduce(Display, new DisplayState.Event.TrackChanged());
        Lyrics = null; LastLookup = "retour au choix automatique"; BusyRetryIn = 0; CurrentIndex = -1;
        LookupsStarted++;
        _fx.RevertToAutomatic(info with { Duration = info.Duration ?? _freshDuration }, info.Identity);
        ScheduleHint();
        Raise();
    }

    private void ScheduleHint() => _hintDueAt = _clock() + HintDelay;

    public void SetOnline(bool online)
    {
        _fx.SetServiceOnline(online);
        if (online)
        {
            if (Display.Current is DisplayState.Screen.Offline && Lyrics is { } l)
            {
                ShowLyrics(l, newlyFound: false);     // les paroles du titre sont déjà en mémoire : on les remet
            }
            else Display = DisplayState.Reduce(Display, new DisplayState.Event.BackOnline());
        }
        else if (Lyrics is null)
        {
            Display = DisplayState.Reduce(Display, new DisplayState.Event.WentOffline());
        }
        Raise();
    }

    // ---- Décalage manuel

    public void SetManualOffset(double value)
    {
        ManualOffset = SyncEngine.SnappedOffset(value);
        _engine.ManualOffset = ManualOffset;
        _allowBackwardOnce = true;
        EvaluateLine(_clock());
        RefreshUnsynced(force: true);
        Raise();
    }

    public void AdjustOffset(double delta) => SetManualOffset(ManualOffset + delta);

    // ---- Pochette

    public void SetPalette(string identity, ArtworkPalette? palette)
    {
        if (identity != Track?.Identity) return;
        Palette = palette;
        Raise();
    }

    public void ClearPalette() { if (Palette is not null) { Palette = null; Raise(); } }

    /// <summary>Rien n'a changé dans le modèle mais la vue doit se redessiner (réglage « Couleurs de la pochette », taille…).</summary>
    public void Touch() => Raise();

    // ---- Avis passager

    public void ShowNotice(string text, double seconds = 3.5)
    {
        Notice = text;
        _noticeUntil = _clock() + seconds;
        Raise();
    }

    // ---- Minuteur, ligne courante et défilement non synchronisé

    /// <summary>Un pas d'horloge (≈ 10 Hz tant que <see cref="WantsTimer"/>) : échéances, puis ligne courante.</summary>
    public void Tick()
    {
        var now = _clock();
        var changed = false;
        if (_noticeUntil is double nu && now >= nu) { _noticeUntil = null; Notice = null; changed = true; }
        if (_hintDueAt is double hd && now >= hd)
        {
            _hintDueAt = null;
            if (Display.Current is DisplayState.Screen.Searching { Hint: false })
            {
                Display = DisplayState.Reduce(Display, new DisplayState.Event.SearchHintDue());
                changed = true;
            }
        }
        if (_deferredLookup is { } d && now >= d.Deadline)
        {
            _deferredLookup = null;
            if (d.Identity == Track?.Identity) Launch(d.Info with { Duration = _freshDuration }, d.Identity);
        }
        if (changed) Raise();
        if (!_windowVisible) return;
        if (Display.Current is DisplayState.Screen.SyncedScreen && _estimator.IsPlaying) EvaluateLine(now);
    }

    private void EvaluateLine(double now)
    {
        if (Display.Current is not DisplayState.Screen.SyncedScreen || Lyrics?.IsSynced != true) return;
        if (!_windowVisible) return;
        var position = _estimator.Estimate(now);
        var index = _engine.IndexAt(position, CurrentIndex, _allowBackwardOnce);
        _allowBackwardOnce = false;
        if (index != CurrentIndex)
        {
            CurrentIndex = index;
            Raise();
        }
    }

    /// <summary>
    /// Ré-arme le plan de défilement du bloc non synchronisé seulement si la trajectoire change (saut, pause, reprise) ou si <paramref name="force"/>
    /// (visibilité, redimensionnement, décalage). Appelé par l'adaptateur au redimensionnement.
    /// </summary>
    public void RefreshUnsynced(bool force = false)
    {
        if (Display.Current is not DisplayState.Screen.Unsynced) return;
        var now = _clock();
        var plan = UnsyncedScrollMath.Next(UnsyncedScroll, _unsyncedAt, now, _estimator.Estimate(now), Track?.Duration ?? _freshDuration, IsPlaying, force);
        if (plan is null) return;
        UnsyncedScroll = plan.Value; _unsyncedAt = now;
        Raise();
    }

    public void SetWindowVisible(bool visible)
    {
        if (visible == _windowVisible) return;
        _windowVisible = visible;
        if (visible)
        {
            _allowBackwardOnce = true;
            EvaluateLine(_clock());
            RefreshUnsynced(force: true);
            Raise();
        }
    }

    private void Raise() => Changed?.Invoke();
}
