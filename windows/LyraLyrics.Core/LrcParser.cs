using System.Globalization;
using System.Text;

namespace LyraLyrics.Core;

/// <summary>
/// Analyseur LRC (port de LRCParser.swift) : [mm:ss.xx] / [mm:ss.xxx] / [mm:ss], plusieurs horodatages par ligne, [offset:±ms],
/// métadonnées ignorées, BOM, CRLF, lignes vides (→ « ♪ »), désordre (tri stable), balises mot à mot retirées.
/// </summary>
public static class LrcParser
{
    public sealed record Result(IReadOnlyList<LyricLine> Lines, int OffsetMillis, IReadOnlyDictionary<string, string> Metadata);

    public const string Placeholder = "♪";

    public static IReadOnlyList<LyricLine> Parse(string text) => ParseDetailed(text).Lines;

    public static Result ParseDetailed(string text)
    {
        var source = text.StartsWith('﻿') ? text[1..] : text;
        var normalized = source.Replace("\r\n", "\n").Replace('\r', '\n');
        var metadata = new Dictionary<string, string>();
        var offsetMillis = 0;
        var entries = new List<(double Time, string Text, int Order)>();

        var order = -1;
        foreach (var rawLine in normalized.Split('\n'))
        {
            order++;
            // W2 (audit constat 22) : une ligne indentée (espaces, tabulation, espace insécable) est acceptée, comme sur le Mac.
            var rest = rawLine.AsSpan().TrimStart(" \t\u00A0");
            var times = new List<double>();
            while (LeadingTag(rest, out var content, out var after))
            {
                var contentStr = content.ToString();
                if (Timestamp(contentStr) is double t) times.Add(t);
                else
                {
                    var colon = contentStr.IndexOf(':');
                    if (colon >= 0 && IsMetadataKey(contentStr[..colon]))
                    {
                        var key = contentStr[..colon].Trim().ToLowerInvariant();
                        var value = contentStr[(colon + 1)..].Trim();
                        if (key == "offset")
                            offsetMillis = int.TryParse(value.Replace(" ", ""), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var o) ? o : 0;
                        else metadata[key] = value;
                    }
                    else break;        // « [Refrain] » ou crochet quelconque : c'est du texte
                }
                rest = after;
            }
            if (times.Count == 0) continue;
            var cleaned = StripWordTags(rest.ToString()).Trim();
            var lineText = cleaned.Length == 0 ? Placeholder : cleaned;
            foreach (var t in times) entries.Add((t, lineText, order));
        }

        var offset = offsetMillis / 1000.0;
        var lines = entries
            .OrderBy(e => e.Time).ThenBy(e => e.Order)
            .Select(e => new LyricLine(Math.Max(0, Math.Round((e.Time - offset) * 1000, MidpointRounding.AwayFromZero) / 1000), e.Text))
            .ToList();
        return new Result(lines, offsetMillis, metadata);
    }

    /// <summary>Texte seul d'un LRC (bloc « non synchronisées ») : lignes sans « ♪ ».</summary>
    public static string PlainText(IEnumerable<LyricLine> lines) => string.Join("\n", lines.Select(l => l.Text).Where(t => t != Placeholder));

    // ---- Détails

    private static bool LeadingTag(ReadOnlySpan<char> s, out ReadOnlySpan<char> content, out ReadOnlySpan<char> rest)
    {
        content = default; rest = default;
        if (s.Length == 0 || s[0] != '[') return false;
        var close = s.IndexOf(']');
        if (close < 0) return false;
        var inner = s[1..close];
        if (inner.Contains('[')) return false;
        content = inner; rest = s[(close + 1)..];
        return true;
    }

    private static bool IsMetadataKey(string key)
    {
        var k = key.Trim();
        return k.Length > 0 && k.All(c => char.IsLetter(c) || c == '#' || c == '_');
    }

    /// <summary>mm:ss, mm:ss.xx, mm:ss.xxx, mm:ss:xx ; minutes sans limite.</summary>
    internal static double? Timestamp(string s)
    {
        var parts = s.Split(':');
        if (parts.Length is not (2 or 3)) return null;
        if (!TryInt(parts[0], out var minutes) || minutes < 0 || parts[0].Length > 4) return null;
        var secondsPart = parts[1];
        string? fraction = null;
        if (parts.Length == 3) fraction = parts[2];
        else
        {
            var dot = secondsPart.IndexOf('.');
            if (dot >= 0) { fraction = secondsPart[(dot + 1)..]; secondsPart = secondsPart[..dot]; }
        }
        if (!TryInt(secondsPart, out var seconds) || seconds < 0 || seconds >= 60 || secondsPart.Length > 2) return null;
        var frac = 0.0;
        if (fraction is not null)
        {
            if (fraction.Length == 0 || fraction.Length > 3 || !TryInt(fraction, out var digits)) return null;
            frac = digits / Math.Pow(10, fraction.Length);
        }
        return minutes * 60 + seconds + frac;
    }

    private static bool TryInt(string s, out int value) => int.TryParse(s, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out value);

    /// <summary>Retire les balises mot à mot &lt;mm:ss.xx&gt; et resserre les espaces.</summary>
    internal static string StripWordTags(string s)
    {
        var sb = new StringBuilder();
        var i = 0;
        while (i < s.Length)
        {
            if (s[i] == '<')
            {
                var close = s.IndexOf('>', i);
                if (close > i && Timestamp(s.Substring(i + 1, close - i - 1)) is not null) { i = close + 1; continue; }
            }
            sb.Append(s[i]); i++;
        }
        return string.Join(" ", sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }
}
