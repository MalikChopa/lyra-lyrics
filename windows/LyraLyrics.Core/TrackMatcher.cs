using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace LyraLyrics.Core;

/// <summary>
/// Choix de la bonne entrée LRCLIB (port de TrackMatcher.swift) : normalisation, score des candidats, règles de durée
/// (≤ 5 s → synchro ; 5 à 15 s → synchro si titre ET artiste correspondent ; au-delà → texte ; durée inconnue → synchro sans contrôle).
/// </summary>
public static class TrackMatcher
{
    public const double DurationTolerance = 5.0;
    public const double SyncedGapLimit = 15.0;

    public sealed record Candidate(int Id, string Title, string Artist, string? Album = null, double? Duration = null,
                                   bool Instrumental = false, bool HasSynced = false, bool HasPlain = false);

    public enum Mode { Synced, Plain, Instrumental, None }

    public sealed record Decision(Candidate? Candidate, Mode Mode, double Score, string Reason);

    public abstract record DurationVerdict
    {
        public sealed record Unknown : DurationVerdict;
        public sealed record Close(double Delta) : DurationVerdict;
        public sealed record Far(double Delta) : DurationVerdict;
    }

    private const RegexOptions Opt = RegexOptions.CultureInvariant;
    private const string Versions = @"((\d{4}\s+)?(re-?master(ed)?|remastered\s+version)(\s+\d{4})?(\s+version)?|single\s+version|album\s+version|mono\s+version|stereo\s+version|radio\s+edit|bonus\s+track)";

    private static readonly Regex FeatParen = new(@"\s*[\(\[]\s*(feat\.?|featuring|ft\.?|with)\s+[^\)\]]*[\)\]]", Opt);
    private static readonly Regex FeatPlain = new(@"\s+-?\s*(feat\.?|featuring|ft\.?)\s+.*$", Opt);
    private static readonly Regex VersionDash = new(@"\s*[-–—]\s*" + Versions + @"\s*$", Opt);
    private static readonly Regex VersionParen = new(@"\s*[\(\[]\s*" + Versions + @"\s*[\)\]]", Opt);
    private static readonly Regex VideoWords = new(@"\b(official|video|lyrics?|mv|hd|4k|youtube|vevo|audio|visualizer|clip officiel)\b", Opt);
    private static readonly Regex ArtistSplit = new(@"\s*(?:/|,|;|\+|\band\b|\bx\b|\bfeat(?:\.|\b)|\bfeaturing\b|\bft(?:\.|\b)|\bvs(?:\.|\b))\s*", Opt);
    private static readonly Regex Quotes = new("[\"'’‘“”`´]", Opt);
    private static readonly Regex LeadingThe = new(@"^the\s+", Opt);
    private static readonly Regex LeadingTheI = new(@"^the\s+", Opt | RegexOptions.IgnoreCase);
    private static readonly Regex PrimaryFeat = new(@"\s+(feat\.?|featuring|ft\.?|with|vs\.?|x)\s+.*$", Opt | RegexOptions.IgnoreCase);
    private static readonly Regex PrimarySplit = new(@"\s*(?:,|;|\s/\s|\s&\s|\sand\s)\s*", Opt);
    private static readonly Regex QFeatParen = new(FeatParen.ToString(), Opt | RegexOptions.IgnoreCase);
    private static readonly Regex QFeatPlain = new(FeatPlain.ToString(), Opt | RegexOptions.IgnoreCase);
    private static readonly Regex QVersionDash = new(VersionDash.ToString(), Opt | RegexOptions.IgnoreCase);
    private static readonly Regex QVersionParen = new(VersionParen.ToString(), Opt | RegexOptions.IgnoreCase);
    private static readonly Regex ShortDash = new(@"\s+[-–—]\s+.*$", Opt);
    private static readonly Regex ShortParen = new(@"\s*[\(\[][^\)\]]*[\)\]]\s*$", Opt);

    // ---- Normalisation

    /// <summary>NFKC, minuscules, « &amp; » → « and », guillemets retirés, « (feat. …) » et suffixes de version retirés ; « Live » et « Remix » conservés.</summary>
    public static string NormalizeTitle(string raw)
    {
        var s = Basic(raw);
        s = FeatParen.Replace(s, "");
        s = FeatPlain.Replace(s, "");
        s = VersionDash.Replace(s, "");
        s = VersionParen.Replace(s, "");
        return Collapse(s);
    }

    public static string NormalizeArtist(string raw) => Collapse(Basic(raw));

    public static ISet<string> ArtistTokens(string raw)
    {
        var s = NormalizeArtist(raw);
        var set = new HashSet<string>();
        foreach (var part in ArtistSplit.Split(s))
        {
            if (part.Length == 0) continue;
            var t = ArtistToken(part);
            if (t.Length > 0) set.Add(t);
        }
        return set;
    }

    public static bool LooksLikeVideoTitle(string artist)
    {
        var s = NormalizeArtist(artist);
        if (s.Length > 60 || s.Contains('|')) return true;
        return VideoWords.IsMatch(s);
    }

    public static DurationVerdict GetDurationVerdict(double? track, double? candidate)
    {
        if (track is not double t || candidate is not double c || t <= 0 || c <= 0) return new DurationVerdict.Unknown();
        var delta = c - t;
        return Math.Abs(delta) <= DurationTolerance ? new DurationVerdict.Close(delta) : new DurationVerdict.Far(delta);
    }

    // ---- Score et choix

    /// <summary>Score d'un candidat ; null = inéligible (titre sans rapport).</summary>
    public static double? Score(Candidate c, TrackInfo track)
    {
        var wanted = TitleKey(track.Title);
        var got = TitleKey(c.Title);
        double score = 0;
        if (wanted == got) score += 10;
        else if (wanted.Length >= 3 && got.Length >= 3 && (got.Contains(wanted) || wanted.Contains(got))) score += 4;
        else return null;

        var wantedArtists = ArtistTokens(track.Artist);
        var gotArtists = ArtistTokens(c.Artist);
        if (LooksLikeVideoTitle(c.Artist)) score -= 6;
        else if (wantedArtists.Overlaps(gotArtists)) score += 5;
        else score -= 4;

        switch (GetDurationVerdict(track.Duration, c.Duration))
        {
            case DurationVerdict.Close close: score += Math.Abs(close.Delta) <= 2 ? 6 : 4; break;
            case DurationVerdict.Far far: score -= Math.Abs(far.Delta) <= SyncedGapLimit ? 1 : 3; break;
        }
        if (track.Album is { Length: > 0 } a && c.Album is { Length: > 0 } b && NormalizeTitle(a) == NormalizeTitle(b)) score += 2;
        if (c.Instrumental) score += 0;
        else if (c.HasSynced) score += 3;
        else if (c.HasPlain) score += 1;
        else score -= 5;
        return score;
    }

    public static bool SyncToleratesGap(double d, bool artistMatches) => artistMatches && Math.Abs(d) <= SyncedGapLimit;

    public static Mode ModeFor(Candidate c, TrackInfo track)
    {
        if (c.Instrumental) return Mode.Instrumental;
        if (c.HasSynced && GetDurationVerdict(track.Duration, c.Duration) is DurationVerdict.Far far)
            return SyncToleratesGap(far.Delta, ArtistMatches(c.Artist, track)) ? Mode.Synced : Mode.Plain;
        if (c.HasSynced) return Mode.Synced;
        if (c.HasPlain) return Mode.Plain;
        return Mode.None;
    }

    public static Decision Choose(TrackInfo track, IEnumerable<Candidate> candidates)
    {
        var list = candidates.ToList();
        (Candidate C, double S)? best = null;
        foreach (var c in list)
        {
            if (Score(c, track) is not double s) continue;
            if (best is { } b)
            {
                var closer = Math.Abs(Delta(c, track)) < Math.Abs(Delta(b.C, track));
                if (s > b.S || (s == b.S && (closer || (Math.Abs(Delta(c, track)) == Math.Abs(Delta(b.C, track)) && c.Id < b.C.Id)))) best = (c, s);
            }
            else best = (c, s);
        }
        if (best is not { } chosen)
            return new Decision(null, Mode.None, 0, list.Count == 0 ? "aucun candidat" : "aucun titre compatible");
        var m = ModeFor(chosen.C, track);
        var reason = $"id {chosen.C.Id}, score {(int)chosen.S}";
        switch (GetDurationVerdict(track.Duration, chosen.C.Duration))
        {
            case DurationVerdict.Unknown: reason += ", durée inconnue"; break;
            case DurationVerdict.Close close: reason += $", durée {Signed(close.Delta)} s"; break;
            case DurationVerdict.Far far: reason += $", durée {Signed(far.Delta)} s (> 5 s{(m == Mode.Synced ? ", toléré ≤ 15 s" : "")})"; break;
        }
        return new Decision(m == Mode.None ? null : chosen.C, m, chosen.S, reason);
    }

    /// <summary>Entier signé comme printf « %+.0f ».</summary>
    internal static string Signed(double d)
    {
        var r = Math.Round(d, MidpointRounding.ToEven);
        return (r < 0 ? "-" : "+") + Math.Abs(r).ToString("0", CultureInfo.InvariantCulture);
    }

    // ---- Clés de comparaison et requêtes

    /// <summary>Clé de comparaison de deux titres : normalisé, sans accents ni ponctuation. Si rien ne reste, le titre normalisé lui-même.</summary>
    public static string TitleKey(string raw)
    {
        var n = NormalizeTitle(raw);
        var folded = Fold(n);
        var sb = new StringBuilder();
        foreach (var rune in folded.EnumerateRunes())
        {
            var cat = Rune.GetUnicodeCategory(rune);
            var keep = cat is UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
                or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter or UnicodeCategory.NonSpacingMark
                or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark or UnicodeCategory.DecimalDigitNumber
                or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber;
            if (keep) sb.Append(rune.ToString()); else sb.Append(' ');
        }
        var key = Collapse(sb.ToString());
        return key.Length == 0 ? n : key;
    }

    internal static string ArtistToken(string raw)
    {
        var t = Fold(raw);
        t = LeadingThe.Replace(t, "");
        return Collapse(t);
    }

    public static bool ArtistMatches(string candidateArtist, TrackInfo track)
    {
        if (LooksLikeVideoTitle(candidateArtist)) return false;
        var wanted = ArtistTokens(track.Artist);
        var got = ArtistTokens(candidateArtist);
        if (wanted.Overlaps(got)) return true;
        return wanted.Any(w => w.Length >= 3 && got.Any(g => g.Length >= 3 && (g.Contains(w) || w.Contains(g))));
    }

    /// <summary>Premier artiste d'une chaîne multi-artistes ; « AC/DC » reste entier.</summary>
    public static string PrimaryArtist(string raw)
    {
        var s = PrimaryFeat.Replace(raw, "");
        var first = PrimarySplit.Split(s).FirstOrDefault(p => p.Length > 0)?.Trim() ?? "";
        return first.Length == 0 ? raw.Trim() : first;
    }

    public static string WithoutThe(string raw)
    {
        var t = LeadingTheI.Replace(raw, "");
        return t.Length == 0 ? raw : t;
    }

    /// <summary>Titre pour une requête : « (feat. …) » et suffixes de version retirés, casse, accents et apostrophes GARDÉS.</summary>
    public static string QueryTitle(string raw)
    {
        var s = raw.Normalize(NormalizationForm.FormKC);
        s = QFeatParen.Replace(s, "");
        s = QFeatPlain.Replace(s, "");
        s = QVersionDash.Replace(s, "");
        s = QVersionParen.Replace(s, "");
        var t = Collapse(s);
        return t.Length == 0 ? raw.Trim() : t;
    }

    public static string ShortQueryTitle(string raw)
    {
        var s = QueryTitle(raw);
        s = ShortDash.Replace(s, "");
        s = ShortParen.Replace(s, "");
        var t = Collapse(s);
        return t.Length == 0 ? QueryTitle(raw) : t;
    }

    // ---- Détails

    private static double Delta(Candidate c, TrackInfo t) => c.Duration is double a && t.Duration is double b ? a - b : 1e9;

    private static string Basic(string raw)
    {
        // « İ » (U+0130) : ToLowerInvariant le laisse tel quel, Swift `lowercased()` donne « i » + point combinant (W2 : même résultat).
        var s = raw.Normalize(NormalizationForm.FormKC).Replace("\u0130", "i\u0307").ToLowerInvariant();
        s = s.Replace("&", " and ");
        return Quotes.Replace(s, "");
    }

    /// <summary>Minuscules, sans diacritiques, repli de casse Unicode comme Swift `folding(.caseInsensitive)` : « ß »/« ẞ » → « ss », « ς » → « σ » (W2).</summary>
    internal static string Fold(string raw)
    {
        var d = raw.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(d.Length);
        foreach (var ch in d)
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark) sb.Append(ch);
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant().Replace("ß", "ss").Replace("ς", "σ");
    }

    internal static string Collapse(string s) => string.Join(" ", s.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
}
