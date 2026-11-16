namespace LyraLyrics.App.Services;

/// <summary>Seul dossier d'écriture de l'application : %APPDATA%\LyraLyrics (réglages, index sans texte, journal).</summary>
internal static class AppPaths
{
    public static string Dir { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LyraLyrics");
    public static string SettingsFile => Path.Combine(Dir, "settings.json");
    public static string IndexFile => Path.Combine(Dir, LyraLyrics.Core.LookupIndex.FileName);
    public static string LogFile => Path.Combine(Dir, "lyra.log");
}
