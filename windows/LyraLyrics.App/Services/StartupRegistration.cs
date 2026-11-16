using Microsoft.Win32;

namespace LyraLyrics.App.Services;

/// <summary>Lancement à la connexion : clé HKCU\Software\Microsoft\Windows\CurrentVersion\Run, valeur « LyraLyrics ». Aucune tâche planifiée, aucun service.</summary>
internal static class StartupRegistration
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "LyraLyrics";

    public static bool IsEnabled
    {
        get
        {
            try { using var k = Registry.CurrentUser.OpenSubKey(KeyPath); return k?.GetValue(ValueName) is string s && s.Length > 0; }
            catch { return false; }
        }
    }

    public static bool Set(bool enabled)
    {
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(KeyPath, writable: true) ?? Registry.CurrentUser.CreateSubKey(KeyPath);
            if (enabled)
            {
                var exe = Environment.ProcessPath;
                if (string.IsNullOrEmpty(exe)) return false;
                k.SetValue(ValueName, "\"" + exe + "\"");
            }
            else k.DeleteValue(ValueName, throwOnMissingValue: false);
            return true;
        }
        catch (Exception e) { Log.Write("startup", "échec : " + e.GetType().Name); return false; }
    }
}
