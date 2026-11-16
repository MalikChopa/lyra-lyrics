using System.Text;
using System.Text.RegularExpressions;

namespace LyraLyrics.Core;

/// <summary>
/// Nettoyage du journal et du « diagnostic » copiable (D6) : aucun titre, artiste, paroles ni identifiant LRCLIB. Le journal n'en écrit
/// déjà pas ; ceci est la deuxième barrière (motifs connus + valeurs secrètes connues de l'appelant, ex. titre en cours).
/// </summary>
public static class LogScrub
{
    private static readonly Regex Ids = new(@"\bid[ =:]+\d+", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex GetPath = new(@"/api/get/\d+", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex Provenance = new(@"\bprovenance\s*=.*$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex TextFields = new(@"\b(titre|title|artiste|artist|album|paroles|lyrics|track|trackName|artistName)\s*[=:]\s*.*$", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex UserDir = new(@"[A-Za-z]:\\Users\\[^\\\s""']+", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static string Scrub(string line, IEnumerable<string>? secrets = null)
    {
        var s = line;
        s = Ids.Replace(s, "id=#");
        s = GetPath.Replace(s, "/api/get/#");
        s = Provenance.Replace(s, "provenance=[retiré]");
        s = TextFields.Replace(s, m => m.Groups[1].Value + "=[retiré]");
        s = UserDir.Replace(s, @"%USERPROFILE%");
        if (secrets is not null)
            foreach (var secret in secrets)
                if (secret.Trim().Length >= 3) s = s.Replace(secret.Trim(), "[retiré]", StringComparison.OrdinalIgnoreCase);
        return s;
    }
}

/// <summary>Texte du « Copier le diagnostic » : faits + dernières lignes du journal, nettoyées.</summary>
public static class DiagnosticReport
{
    public const int TailLines = 200;

    public static string Build(string appName, string version, IEnumerable<KeyValuePair<string, string>> facts, IEnumerable<string> logLines, IEnumerable<string>? secrets = null)
    {
        var sec = secrets?.ToList() ?? new List<string>();
        var sb = new StringBuilder();
        sb.AppendLine($"Diagnostic {appName} {version} : sans titre, artiste, paroles ni identifiant LRCLIB.");
        sb.AppendLine("--- faits ---");
        foreach (var kv in facts) sb.AppendLine(LogScrub.Scrub($"{kv.Key} : {kv.Value}", sec));
        sb.AppendLine($"--- {TailLines} dernières lignes du journal ---");
        foreach (var l in logLines.TakeLast(TailLines)) sb.AppendLine(LogScrub.Scrub(l, sec));
        return sb.ToString();
    }

    /// <summary>Écriture d'une exception en texte complet (type, HResult, message, pile, exceptions internes) : pour le journal de démarrage (constat 3).</summary>
    public static string DescribeException(Exception ex)
    {
        var sb = new StringBuilder();
        var depth = 0;
        for (var e = ex; e is not null && depth < 6; e = e.InnerException, depth++)
        {
            sb.AppendLine($"{(depth == 0 ? "" : "interne : ")}{e.GetType().FullName} HResult=0x{e.HResult:x8}");
            sb.AppendLine("message : " + e.Message);
            sb.AppendLine(e.StackTrace ?? "(pas de pile)");
        }
        return sb.ToString().TrimEnd();
    }
}
