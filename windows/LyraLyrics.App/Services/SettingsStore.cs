using LyraLyrics.Core;

namespace LyraLyrics.App.Services;

/// <summary>Charge et enregistre settings.json (atomique : fichier temporaire puis remplacement). Enregistrement différé de 400 ms.</summary>
internal sealed class SettingsStore
{
    private readonly string _path;
    private readonly System.Windows.Threading.DispatcherTimer _timer;
    public Settings Current { get; private set; }
    public event Action? Changed;

    public SettingsStore(string path)
    {
        _path = path;
        byte[]? data = null;
        try { if (File.Exists(path)) data = File.ReadAllBytes(path); } catch (Exception e) { Log.Write("settings", "lecture impossible : " + e.GetType().Name); }
        var (s, outcome) = Settings.Decode(data);
        Current = s;
        if (outcome is Settings.DecodeOutcome.Corrupt or Settings.DecodeOutcome.NewerVersion) Log.Write("settings", "réglages ignorés (" + outcome + "), valeurs par défaut");
        if (string.IsNullOrEmpty(Current.IndexSalt)) { Current.IndexSalt = LyricsService.NewSalt(); SaveNow(); }
        _timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _timer.Tick += (_, _) => { _timer.Stop(); SaveNow(); };
    }

    /// <summary>Modifie les réglages, les ramène dans leurs plages, prévient les abonnés et programme l'enregistrement.</summary>
    public void Update(Action<Settings> change)
    {
        change(Current);
        Current.Clamp();
        Changed?.Invoke();
        _timer.Stop(); _timer.Start();
    }

    /// <summary>Enregistre la position/taille sans prévenir les abonnés (évite une boucle avec la fenêtre).</summary>
    public void UpdateQuiet(Action<Settings> change)
    {
        change(Current);
        _timer.Stop(); _timer.Start();
    }

    public void SaveNow()
    {
        try
        {
            Directory.CreateDirectory(AppPaths.Dir);
            var tmp = _path + ".tmp";
            File.WriteAllBytes(tmp, Current.Encode());
            File.Move(tmp, _path, overwrite: true);
        }
        catch (Exception e) { Log.Write("settings", "écriture impossible : " + e.GetType().Name); }
    }
}
