using System.Text;

namespace LyraLyrics.Core;

/// <summary>Nom, version et User-Agent : l'unique endroit à modifier pour renommer l'application (port d'AppIdentity.swift).</summary>
public static class AppIdentity
{
    public const string DisplayName = "Lyra Lyrics";
    /// <summary>Version : lue au lancement dans l'assembly, elle-même issue de <c>&lt;Version&gt;</c> dans windows/Directory.Build.props (source unique).</summary>
    public static string Version { get; } = ReadVersion();
    public const string ProjectUrl = "https://github.com/MalikChopa/lyra-lyrics";

    /// <summary>« Lyra Lyrics » → « LyraLyrics » : ASCII seul.</summary>
    public static string UserAgentToken => Token(DisplayName);

    private static string ReadVersion()
    {
        var asm = typeof(AppIdentity).Assembly;
        var info = asm.GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), false)
            .OfType<System.Reflection.AssemblyInformationalVersionAttribute>().FirstOrDefault()?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(info)) return info.Split('+')[0];       // « 1.0.1+hash » → « 1.0.1 »
        var v = asm.GetName().Version;
        return v is null ? "0.0.0" : $"{v.Major}.{v.Minor}.{v.Build}";
    }

    public static string Token(string name)
    {
        var decomposed = name.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var ch in decomposed)
            if (System.Globalization.CharUnicodeInfo.GetUnicodeCategory(ch) != System.Globalization.UnicodeCategory.NonSpacingMark) sb.Append(ch);
        var words = new List<string>();
        var current = new StringBuilder();
        foreach (var ch in sb.ToString())
        {
            if (ch < 128 && char.IsLetterOrDigit(ch)) current.Append(ch);
            else if (current.Length > 0) { words.Add(current.ToString()); current.Clear(); }
        }
        if (current.Length > 0) words.Add(current.ToString());
        return string.Concat(words.Select(w => char.ToUpperInvariant(w[0]) + w[1..]));
    }

    public static string UserAgent => $"{UserAgentToken}/{Version} (+{ProjectUrl})";
}
