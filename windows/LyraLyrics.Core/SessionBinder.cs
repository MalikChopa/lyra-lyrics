namespace LyraLyrics.Core;

/// <summary>
/// Rattachement à la session média (Spotify) : choisit la session, abonne / désabonne ses événements, et rattrape par le sondage
/// une session apparue sans événement (constat 2 de l'audit). Générique pour être testé avec de fausses sessions sur le Mac.
/// </summary>
public sealed class SessionBinder<T> where T : class
{
    private readonly Func<T?> _pick;
    private readonly Func<T, string> _id;
    private readonly Action<T> _attach;
    private readonly Action<T> _detach;
    private readonly Action<string> _log;
    private readonly object _lock = new();
    private T? _current;

    public SessionBinder(Func<T?> pick, Func<T, string> id, Action<T> attach, Action<T> detach, Action<string>? log = null)
    {
        _pick = pick; _id = id; _attach = attach; _detach = detach; _log = log ?? (_ => { });
    }

    /// <summary>Session actuellement suivie (null : aucune). Lisible depuis tous les fils.</summary>
    public T? Current { get { lock (_lock) return _current; } }

    /// <summary>
    /// Relit la liste des sessions. <paramref name="force"/> (liste modifiée) : on se rattache même à un identifiant identique
    /// (Spotify a pu être relancé : nouvel objet). Sinon on garde l'objet déjà abonné. Rend vrai si la session suivie a changé.
    /// </summary>
    public bool Rebind(bool force)
    {
        lock (_lock)
        {
            var next = _pick();
            var same = ReferenceEquals(next, _current) || (next is not null && _current is not null && _id(next) == _id(_current));
            if (!force && same) return false;
            DetachLocked();
            _current = next;
            if (next is not null) { _attach(next); _log("session Spotify attachée : " + _id(next)); }
            else _log("aucune session Spotify");
            return true;
        }
    }

    /// <summary>Lâche la session (échecs répétés, arrêt).</summary>
    public void Detach() { lock (_lock) DetachLocked(); }

    private void DetachLocked()
    {
        if (_current is null) return;
        try { _detach(_current); } catch { }
        _current = null;
    }

    /// <summary>
    /// Tour de sondage : sans session suivie, cherche si Spotify est apparu ; si oui, se rattache PUIS appelle
    /// <paramref name="afterAttach"/> (relevé complet). Rend vrai si un rattachement a eu lieu.
    /// </summary>
    public async Task<bool> PollAsync(Func<Task> afterAttach)
    {
        if (Current is not null) return false;
        if (!Rebind(false) || Current is null) return false;
        _log("session trouvée par le sondage (aucun événement reçu)");
        await afterAttach().ConfigureAwait(false);
        return true;
    }
}
