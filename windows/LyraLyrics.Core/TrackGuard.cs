namespace LyraLyrics.Core;

/// <summary>
/// Garde de changement de piste (constat 8) : quand un nouveau titre arrive avec une position « implausible » (celle de l'ancien
/// titre), on attend l'instantané suivant, mais au plus <see cref="MaxWaitSeconds"/> : passé ce délai le titre est chargé quand même.
/// </summary>
public sealed class TrackGuard
{
    /// <summary>Borne d'attente : 3 s (3 relevés SMTC à 1 s) sur le même nouvel identifiant.</summary>
    public const double MaxWaitSeconds = 3.0;

    public enum Verdict { Wait, Start, StartForced }

    private string? _pending;
    private double _since;

    public Verdict Decide(string identity, bool positionPlausible, double now)
    {
        if (positionPlausible) { _pending = null; return Verdict.Start; }
        if (_pending != identity) { _pending = identity; _since = now; return Verdict.Wait; }
        if (now - _since >= MaxWaitSeconds) { _pending = null; return Verdict.StartForced; }
        return Verdict.Wait;
    }

    public void Reset() => _pending = null;
}
