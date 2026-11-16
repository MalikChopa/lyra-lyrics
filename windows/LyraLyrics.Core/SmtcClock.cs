namespace LyraLyrics.Core;

/// <summary>
/// Horloge SMTC pure. La position d'une session média Windows est un INSTANTANÉ daté : « Position valable à LastUpdatedTime »
/// (documentation Microsoft, GlobalSystemMediaTransportControlsSessionTimelineProperties). Il faut donc extrapoler.
/// </summary>
public static class SmtcClock
{
    /// <summary>
    /// position = Position + (maintenant − LastUpdatedTime) × vitesse en lecture, bornée à [StartTime, EndTime] ; Position seule sinon.
    /// <paramref name="end"/> ≤ <paramref name="start"/> : borne haute ignorée (durée inconnue).
    /// </summary>
    public static double Extrapolate(double position, DateTimeOffset lastUpdatedUtc, DateTimeOffset nowUtc, double rate, bool isPlaying, double start, double end)
    {
        var p = position;
        if (isPlaying)
        {
            var elapsed = (nowUtc - lastUpdatedUtc).TotalSeconds;
            // Un LastUpdatedTime dans le futur (horloges légèrement décalées) ou absurde (valeur par défaut) n'avance ni ne recule la position.
            if (elapsed < 0 || lastUpdatedUtc.Year < 2000) elapsed = 0;
            p += elapsed * (rate > 0 && double.IsFinite(rate) ? rate : 1.0);
        }
        if (end > start) p = Math.Min(p, end);
        return Math.Max(p, Math.Max(start, 0));
    }

    /// <summary>Durée en secondes depuis les bornes de la timeline (null si inconnue).</summary>
    public static double? Duration(double start, double end) => end > start ? end - start : null;

    /// <summary>Garde de changement de piste : un instantané dont la position dépasse la durée de plus de 2 s vient de l'ancien titre.</summary>
    public static bool IsPlausible(double position, double? duration) => position >= 0 && (duration is not double d || position <= d + 2.0);

    /// <summary>Publicité Spotify (titre « Advertisement ») : traitée comme « rien en lecture » (heuristique, non vérifiée).</summary>
    public static bool LooksLikeAdvertisement(string title, string artist) =>
        string.Equals(title.Trim(), "Advertisement", StringComparison.OrdinalIgnoreCase) || string.Equals(title.Trim(), "Publicité", StringComparison.OrdinalIgnoreCase)
        || (string.Equals(artist.Trim(), "Spotify", StringComparison.OrdinalIgnoreCase) && string.IsNullOrWhiteSpace(title));

    /// <summary>Session Spotify ? Identifiant de modèle d'application : Spotify.exe, SpotifyAB.SpotifyMusic_… (Store) ou tout identifiant contenant « spotify ».</summary>
    public static bool IsSpotifySession(string? appUserModelId)
    {
        if (string.IsNullOrEmpty(appUserModelId)) return false;
        return appUserModelId.Equals("Spotify.exe", StringComparison.OrdinalIgnoreCase)
            || appUserModelId.StartsWith("SpotifyAB.SpotifyMusic_", StringComparison.OrdinalIgnoreCase)
            || appUserModelId.Contains("spotify", StringComparison.OrdinalIgnoreCase);
    }
}
