namespace LyraLyrics.Core;

/// <summary>Ce que fait la lecture en ce moment (C1). Mêmes valeurs que <c>PlaybackActivity</c> côté Mac.</summary>
public enum PlaybackActivity { Nothing, Paused, Playing }

/// <summary>
/// Masquage automatique (C1, port de <c>AutoHideState</c> de Features110.swift). Jamais par-dessus un choix manuel : seule la fenêtre que
/// NOUS avons masquée est remontrée, et un affichage manuel pendant la condition la garde affichée jusqu'à ce que la condition
/// disparaisse puis revienne.
/// </summary>
public sealed class AutoHideState
{
    public enum Action { Hide, Show }

    /// <summary>Délai de grâce après le lancement (comme le Mac : 6 s) pendant lequel rien n'est masqué.</summary>
    public const double GraceSeconds = 6;

    public bool AutoHidden { get; private set; }
    public bool OverrideActive { get; private set; }
    public bool LastCondition { get; private set; }

    public static bool Condition(AutoHideMode mode, PlaybackActivity activity) => mode switch
    {
        AutoHideMode.Never => false,
        AutoHideMode.Paused => activity != PlaybackActivity.Playing,
        AutoHideMode.Idle => activity == PlaybackActivity.Nothing,
        _ => false,
    };

    public Action? Evaluate(AutoHideMode mode, PlaybackActivity activity, bool windowShown)
    {
        var cond = Condition(mode, activity);
        LastCondition = cond;
        if (cond)
        {
            if (windowShown && !OverrideActive && !AutoHidden) { AutoHidden = true; return Action.Hide; }
            return null;
        }
        OverrideActive = false;
        if (AutoHidden) { AutoHidden = false; return windowShown ? null : Action.Show; }
        return null;
    }

    /// <summary>À appeler après un masquage / affichage fait par l'utilisateur (raccourci, icône, menu).</summary>
    public void ManualChange(bool windowShown)
    {
        AutoHidden = false;
        OverrideActive = windowShown && LastCondition;
    }

    /// <summary>Secondes à attendre avant d'évaluer, si le délai de grâce n'est pas écoulé ; 0 sinon.</summary>
    public static double GraceWait(double now, double graceUntil) => now < graceUntil ? graceUntil - now + 0.05 : 0;
}
