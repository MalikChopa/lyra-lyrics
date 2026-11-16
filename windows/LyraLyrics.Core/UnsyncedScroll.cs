namespace LyraLyrics.Core;

/// <summary>
/// Plan de défilement du bloc « non synchronisées » (D1, port de <c>refreshUnsyncedScroll</c> du Mac) : point de départ (0…1), temps restant
/// jusqu'à la fin du bloc (0 = à l'arrêt, en pause) et numéro d'ordre. Le bloc défile par UNE animation linéaire : un nouveau plan
/// n'est publié que si la trajectoire change (saut, pause, reprise, redimensionnement).
/// </summary>
public readonly record struct UnsyncedScrollPlan(double Progress, double Remaining, int Stamp)
{
    public bool Playing => Remaining > 0;
}

/// <summary>Calculs purs du défilement non synchronisé (testés dans le Core ; l'animation WPF ne fait que les appliquer).</summary>
public static class UnsyncedScrollMath
{
    /// <summary>Durée supposée du titre quand elle est inconnue : 4 minutes.</summary>
    public const double DefaultSpan = 240;
    /// <summary>Écart toléré entre la trajectoire en cours et la position réelle avant de ré-armer l'animation (1,2 % du bloc).</summary>
    public const double Tolerance = 0.012;
    public const double MinRemaining = 0.1;

    public static double Span(double? duration) => duration is double d && d > 0 ? d : DefaultSpan;

    public static double Progress(double position, double span) => Math.Min(1, Math.Max(0, position / span));

    /// <summary>
    /// Nouveau plan, ou null si la trajectoire en cours reste bonne. <paramref name="oldAt"/> : instant où <paramref name="old"/> a été armé.
    /// </summary>
    public static UnsyncedScrollPlan? Next(UnsyncedScrollPlan old, double oldAt, double now, double position, double? duration, bool playing, bool force)
    {
        var span = Span(duration);
        var progress = Progress(position, span);
        var projected = old.Playing ? Math.Min(1, old.Progress + (now - oldAt) / span) : old.Progress;
        if (!force && old.Playing == playing && Math.Abs(projected - progress) < Tolerance) return null;
        return new UnsyncedScrollPlan(progress, playing ? Math.Max(MinRemaining, span - position) : 0, old.Stamp + 1);
    }

    /// <summary>
    /// Où en est l'animation d'un plan armé il y a <paramref name="elapsed"/> secondes (même trajectoire linéaire, sans nouveau plan) : sert à ré-armer l'animation
    /// après un changement de mise en page (police, taille) sans faire revenir le texte en arrière. À l'arrêt : inchangé.
    /// </summary>
    public static (double Progress, double Remaining) Advance(UnsyncedScrollPlan plan, double elapsed)
    {
        if (!plan.Playing) return (plan.Progress, 0);
        var e = Math.Min(Math.Max(0, elapsed), plan.Remaining);
        return (plan.Progress + (1 - plan.Progress) * e / plan.Remaining, Math.Max(MinRemaining, plan.Remaining - e));
    }

    /// <summary>Décalages vertical de départ et d'arrivée de l'animation (négatifs : le texte monte). <paramref name="margin"/> : marge haute (4 % de la hauteur visible).</summary>
    public static (double From, double To) Offsets(double progress, double overflow, double margin)
    {
        var o = Math.Max(0, overflow);
        return (-o * Math.Min(1, Math.Max(0, progress)) + margin, -o + margin);
    }
}
