using LyraLyrics.Core;

namespace LyraLyrics.App.Services;

/// <summary>
/// Journal local (D6) : horodatages, états, identifiants d'application de session média, positions. JAMAIS de titre, d'artiste, de paroles
/// ni d'identifiant LRCLIB. Écriture : %APPDATA%\LyraLyrics\lyra.log, 256 Ko puis rotation (lyra.log.1). Une erreur d'écriture passagère
/// ne coupe plus le journal (voir <see cref="RollingLog"/>). Chaque ligne passe par <see cref="LogScrub"/> (seconde barrière).
/// </summary>
internal static class Log
{
    public static readonly RollingLog File = new(AppPaths.LogFile);

    /// <summary>Valeurs à masquer en plus des motifs connus (titre et artiste courants, fournis par le modèle) : jamais écrites sur disque.</summary>
    public static Func<IEnumerable<string>>? Secrets { get; set; }

    public static void Write(string area, string message)
    {
        try
        {
            var clean = LogScrub.Scrub(message, Secrets?.Invoke());
            File.Write($"{RollingLog.Stamp()} [{area}] {clean}");
        }
        catch { }
    }

    public static void Write(string area, Dictionary<string, string> fields) =>
        Write(area, string.Join(" ", fields.Select(kv => $"{kv.Key}={kv.Value}")));

    /// <summary>Exception complète (type, HResult, message, pile, exceptions internes), une ligne du journal par ligne de texte.</summary>
    public static void WriteException(string area, string context, Exception ex)
    {
        Write(area, context + " : " + ex.GetType().FullName + " 0x" + ex.HResult.ToString("x8"));
        foreach (var line in DiagnosticReport.DescribeException(ex).Split('\n'))
            Write(area, "  " + line.TrimEnd('\r'));
    }
}
