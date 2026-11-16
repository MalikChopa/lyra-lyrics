namespace LyraLyrics.Core;

/// <summary>
/// États affichés (port de DisplayState.swift) : réducteur pur Reduce(état, événement) → état. « En pause » = drapeau posé sur l'écran courant.
/// Les états propres à Apple Music (autorisation, titre illisible) restent dans le réducteur pour garder la parité des tests,
/// mais la version Windows (Spotify seul) ne les émet jamais.
/// </summary>
public sealed record DisplayState(DisplayState.Screen Current, bool Paused = false, bool HasTrack = false)
{
    public abstract record Screen
    {
        public sealed record Nothing : Screen;
        public sealed record Searching(bool Hint) : Screen;
        public sealed record SyncedScreen : Screen;
        public sealed record Unsynced : Screen;
        public sealed record InstrumentalScreen : Screen;
        public sealed record Unavailable : Screen;
        public sealed record Busy(double RetryIn) : Screen;
        public sealed record Offline : Screen;
        public sealed record PermissionNeeded(bool Refused) : Screen;
        public sealed record Unreadable : Screen;

        public string Name => this switch
        {
            Nothing => "nothing", Searching => "searching", SyncedScreen => "synced", Unsynced => "unsynced", InstrumentalScreen => "instrumental",
            Unavailable => "unavailable", Busy => "busy", Offline => "offline", PermissionNeeded => "permission", Unreadable => "unreadable", _ => "?",
        };
    }

    public abstract record Event
    {
        public sealed record TrackChanged : Event;
        public sealed record SearchHintDue : Event;
        public sealed record LyricsSynced : Event;
        public sealed record LyricsUnsynced : Event;
        public sealed record Instrumental : Event;
        public sealed record NotFound : Event;
        public sealed record BudgetExhausted : Event;
        public sealed record ServiceBusy(double RetryIn) : Event;
        public sealed record BusyCountdown(double RetryIn) : Event;
        public sealed record ServiceStalled : Event;
        public sealed record WaitEnded : Event;
        public sealed record WentOffline : Event;
        public sealed record BackOnline : Event;
        public sealed record Paused : Event;
        public sealed record Resumed : Event;
        public sealed record Stopped : Event;
        public sealed record PermissionNeeded : Event;
        public sealed record PermissionRefused : Event;
        public sealed record PermissionGranted : Event;
        public sealed record TrackUnreadable : Event;
    }

    public static readonly DisplayState Initial = new(new Screen.Nothing());

    public static DisplayState Reduce(DisplayState state, Event ev)
    {
        var s = state;
        Screen next = s.Current;
        switch (ev)
        {
            case Event.TrackChanged:
                s = s with { HasTrack = true, Paused = false };
                if (s.Current is Screen.Offline or Screen.PermissionNeeded) return s;
                return s with { Current = new Screen.Searching(false) };
            case Event.SearchHintDue:
                if (s.Current is Screen.Searching { Hint: false }) return s with { Current = new Screen.Searching(true) };
                return s;
            case Event.LyricsSynced: return s.HasTrack ? s with { Current = new Screen.SyncedScreen() } : s;
            case Event.LyricsUnsynced: return s.HasTrack ? s with { Current = new Screen.Unsynced() } : s;
            case Event.Instrumental: return s.HasTrack ? s with { Current = new Screen.InstrumentalScreen() } : s;
            case Event.NotFound or Event.BudgetExhausted: return s.HasTrack ? s with { Current = new Screen.Unavailable() } : s;
            case Event.ServiceBusy sb: return Busy(s, sb.RetryIn);
            case Event.BusyCountdown bc: return Busy(s, bc.RetryIn);
            case Event.ServiceStalled:
                if (!s.HasTrack || s.Current is Screen.Offline) return s;
                return s with { Current = new Screen.Busy(0) };
            case Event.WaitEnded:
                if (s.Current is Screen.Busy) return s with { Current = s.HasTrack ? new Screen.Searching(false) : new Screen.Nothing() };
                return s;
            case Event.WentOffline: return s with { Current = new Screen.Offline() };
            case Event.BackOnline:
                if (s.Current is Screen.Offline) return s with { Current = s.HasTrack ? new Screen.Searching(false) : new Screen.Nothing() };
                return s;
            case Event.Paused: return s.HasTrack ? s with { Paused = true } : s;
            case Event.Resumed: return s with { Paused = false };
            case Event.Stopped:
                s = s with { HasTrack = false, Paused = false };
                if (s.Current is Screen.Offline) return s;
                return s with { Current = new Screen.Nothing() };
            case Event.PermissionNeeded:
                if (s.Current is Screen.PermissionNeeded { Refused: true }) return s;
                return s with { Current = new Screen.PermissionNeeded(false) };
            case Event.PermissionRefused: return s with { Current = new Screen.PermissionNeeded(true) };
            case Event.PermissionGranted:
                if (s.Current is Screen.PermissionNeeded) return s with { Current = s.HasTrack ? new Screen.Searching(false) : new Screen.Nothing() };
                return s;
            case Event.TrackUnreadable: return s.HasTrack ? s with { Current = new Screen.Unreadable() } : s;
        }
        return s with { Current = next };

        static DisplayState Busy(DisplayState s, double retryIn)
        {
            if (!s.HasTrack) return s;
            if (s.Current is Screen.Offline) return s;           // hors connexion prime sur un compte à rebours
            return s with { Current = new Screen.Busy(Math.Max(0, retryIn)) };
        }
    }

    /// <summary>Textes des états (validés, mêmes mots que sur Mac, « Spotify » seul) ; null pour les écrans à lignes.</summary>
    public (string Title, string Body)? StateText => Current switch
    {
        Screen.Nothing => ("Rien en lecture", "Lance un titre dans Spotify : ses paroles apparaîtront ici."),
        Screen.InstrumentalScreen => ("Morceau instrumental", ""),
        Screen.Unavailable => ("Paroles indisponibles", "Aucune parole trouvée pour ce titre. (Remix, titre rare ou pas encore référencé.)"),
        Screen.Busy b when b.RetryIn <= 0 => ("Service de paroles occupé", "Le service ne répond pas pour l'instant. Réessaie dans un moment."),
        Screen.Busy b => ("Service de paroles occupé", $"Nouvel essai dans {(int)Math.Ceiling(Math.Round(b.RetryIn, 9))} s."),
        Screen.Offline => ("Hors connexion", "Les paroles reviendront avec le réseau."),
        Screen.PermissionNeeded => ("Autorisation nécessaire", "Windows n'a pas donné accès aux contrôles média."),
        Screen.Unreadable => ("Titre illisible", "Ce titre ne donne pas ses informations."),
        _ => null,
    };

    public string? BarTitleWhenIdle => Current is Screen.Nothing ? "Aucune lecture" : null;
}
