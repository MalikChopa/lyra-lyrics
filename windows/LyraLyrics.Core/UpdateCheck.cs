using System.Globalization;
using System.Text.Json;

namespace LyraLyrics.Core;

/// <summary>
/// Vérification des mises à jour (E1, port de <c>UpdateCheck</c> de Features110.swift) : UNE requête GET par jour au plus vers l'API publique
/// de GitHub, rien d'envoyé hormis le User-Agent de l'app. Ici : seulement la logique pure (adresse, lecture de la réponse, comparaison
/// de versions, cadence). La réponse est une donnée, jamais une instruction : seul un lien vers une page de versions du dépôt est accepté.
/// </summary>
public static class UpdateCheck
{
    public const string Host = "api.github.com";
    public const string Repository = "MalikChopa/lyra-lyrics";
    public const string RepositoryName = "lyra-lyrics";
    public static readonly Uri Endpoint = new("https://api.github.com/repos/MalikChopa/lyra-lyrics/releases/latest");
    /// <summary>Page des signalements (ligne 31 de l'audit : « Signaler un problème »).</summary>
    public static readonly Uri IssuesPage = new("https://github.com/MalikChopa/lyra-lyrics/issues");
    public const double Interval = 24 * 3600;
    /// <summary>Taille maximale de réponse lue (le Mac refuse au-delà de 200 000 octets).</summary>
    public const int MaxBodyBytes = 200_000;

    public sealed record Release(string Tag, Uri Url);

    public abstract record Outcome
    {
        public sealed record Newer(Release Release) : Outcome;
        public sealed record UpToDate : Outcome;
        public sealed record Failed : Outcome;
    }

    /// <summary><c>tag_name</c> et <c>html_url</c> de la réponse ; le lien n'est accepté que s'il est de confiance.</summary>
    public static Release? Parse(byte[] data)
    {
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
            if (!doc.RootElement.TryGetProperty("tag_name", out var t) || t.ValueKind != JsonValueKind.String) return null;
            if (!doc.RootElement.TryGetProperty("html_url", out var l) || l.ValueKind != JsonValueKind.String) return null;
            var tag = t.GetString()!;
            if (tag.Length == 0 || new System.Globalization.StringInfo(tag).LengthInTextElements > 40) return null;
            if (!Uri.TryCreate(l.GetString(), UriKind.Absolute, out var url) || !IsTrusted(url)) return null;
            return new Release(tag, url);
        }
        catch (JsonException) { return null; }
    }

    /// <summary>
    /// Lien accepté : https, github.com, dépôt <c>lyra-lyrics</c>, rubrique <c>releases</c>, sans identifiant ni port. Le propriétaire n'est PAS figé
    /// (GitHub renvoie le dépôt sous le nom de compte actuel après un renommage).
    /// </summary>
    public static bool IsTrusted(Uri url)
    {
        if (url.Scheme != "https" || !string.Equals(url.Host, "github.com", StringComparison.OrdinalIgnoreCase)) return false;
        // Identifiant ou port écrit (même « :443 ») : refusé comme sur le Mac. On lit l'autorité telle qu'écrite.
        var s = url.OriginalString;
        var start = s.IndexOf("//", StringComparison.Ordinal);
        if (start < 0) return false;
        var rest = s[(start + 2)..];
        var end = rest.IndexOfAny(new[] { '/', '?', '#' });
        var authority = end < 0 ? rest : rest[..end];
        if (authority.Contains('@') || authority.Contains(':')) return false;
        var parts = url.AbsolutePath.ToLowerInvariant().Split('/', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 3 && parts[1] == RepositoryName && parts[2] == "releases";
    }

    /// <summary>Composantes numériques d'une version (« v1.2.3 » → [1, 2, 3]) ; null si illisible.</summary>
    public static long[]? Components(string version)
    {
        var v = version.Trim(' ', '\t');
        if (v.StartsWith('v') || v.StartsWith('V')) v = v[1..];
        var dash = v.IndexOfAny(new[] { '-', '+' });
        if (dash >= 0) v = v[..dash];
        var parts = v.Split('.');
        var result = new long[parts.Length];
        for (var i = 0; i < parts.Length; i++)
            if (!long.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out result[i])) return null;
        return result;
    }

    public static bool IsNewer(string remote, string local)
    {
        if (Components(remote) is not { } r || Components(local) is not { } l) return false;
        for (var i = 0; i < Math.Max(r.Length, l.Length); i++)
        {
            var a = i < r.Length ? r[i] : 0; var b = i < l.Length ? l[i] : 0;
            if (a != b) return a > b;
        }
        return false;
    }

    /// <summary>Une vérification est due si la dernière date de 24 h ou plus (ou n'a jamais eu lieu, ou est dans le futur de plus d'une heure).</summary>
    public static bool IsDue(double? last, double now)
    {
        if (last is not { } l) return true;
        return now - l >= Interval || l > now + 3600;
    }

    public static Outcome Evaluate(byte[] data, string localVersion)
    {
        if (Parse(data) is not { } release) return new Outcome.Failed();
        return IsNewer(release.Tag, localVersion) ? new Outcome.Newer(release) : new Outcome.UpToDate();
    }
}
