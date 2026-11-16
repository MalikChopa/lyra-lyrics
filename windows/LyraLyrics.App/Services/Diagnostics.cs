using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using LyraLyrics.App.Smtc;
using LyraLyrics.App.Ui;
using LyraLyrics.Core;
using WinForms = System.Windows.Forms;

namespace LyraLyrics.App.Services;

/// <summary>
/// Diagnostic pour le premier essai sur Windows : faits système et fenêtre au lancement (dans lyra.log), relevé CPU / RAM toutes les 60 s,
/// et texte « Copier le diagnostic ». Aucun titre, artiste, paroles ni identifiant LRCLIB : seulement des nombres, des modes et des noms d'applis média.
/// </summary>
internal sealed class Diagnostics : IDisposable
{
    private readonly Func<LyricsWindow> _window;
    private readonly SmtcMonitor _smtc;
    private readonly SettingsStore _store;
    private readonly DispatcherTimer _perf;
    private TimeSpan _lastCpu;
    private DateTime _lastWall;
    public Func<bool>? TrayVisible { get; set; }

    public Diagnostics(Func<LyricsWindow> window, SmtcMonitor smtc, SettingsStore store)
    {
        _window = window; _smtc = smtc; _store = store;
        _lastWall = DateTime.UtcNow; _lastCpu = Process.GetCurrentProcess().TotalProcessorTime;
        _perf = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromSeconds(60) };
        _perf.Tick += (_, _) => LogPerf();
    }

    public void StartPerfLog() => _perf.Start();

    /// <summary>Une ligne toutes les 60 s : mémoire (Mo) et CPU moyen du processus sur l'intervalle (% d'un cœur et % de la machine).</summary>
    private void LogPerf()
    {
        try
        {
            using var p = Process.GetCurrentProcess();
            var now = DateTime.UtcNow; var cpu = p.TotalProcessorTime;
            var wall = (now - _lastWall).TotalSeconds; var used = (cpu - _lastCpu).TotalSeconds;
            _lastWall = now; _lastCpu = cpu;
            var core = wall > 0 ? used / wall * 100 : 0;
            Log.Write("perf", string.Create(CultureInfo.InvariantCulture,
                $"ram={p.WorkingSet64 / 1048576.0:0.0} Mo privé={p.PrivateMemorySize64 / 1048576.0:0.0} Mo cpu={core:0.0}% d'un cœur ({core / Environment.ProcessorCount:0.00}% de la machine) fils={p.Threads.Count} poignées={p.HandleCount}"));
        }
        catch (Exception e) { Log.Write("perf", "relevé impossible : " + e.GetType().Name); }
    }

    /// <summary>Tous les faits, dans l'ordre d'affichage. À appeler sur le fil de l'interface.</summary>
    public List<KeyValuePair<string, string>> Collect()
    {
        var f = new List<KeyValuePair<string, string>>();
        void Add(string k, string v) => f.Add(new(k, v));
        void Try(string k, Func<string> v) { try { Add(k, v()); } catch (Exception e) { Add(k, "illisible (" + e.GetType().Name + ")"); } }

        Add("Application", $"{AppIdentity.DisplayName} {AppIdentity.Version}");
        Try("Windows", () => $"{System.Runtime.InteropServices.RuntimeInformation.OSDescription} · build {Environment.OSVersion.Version.Build} · {(Environment.Is64BitOperatingSystem ? "64" : "32")} bits");
        Try(".NET", () => System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription + " · " + System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture);
        Try("Niveau de rendu WPF", () => $"tier {RenderCapability.Tier >> 16} (0 = logiciel, 1 = partiel, 2 = matériel)");
        Try("Machine", () => $"{Environment.ProcessorCount} cœurs logiques");
        Try("Lancement", () => $"processus lancé il y a {(DateTime.Now - Process.GetCurrentProcess().StartTime).TotalSeconds:0.0} s");
        Try("Dossier de l'exe", () => ExeFolderKind());
        Try("Écrans", () =>
        {
            var screens = WinForms.Screen.AllScreens;
            return string.Join(" ; ", screens.Select((s, i) => $"#{i + 1}{(s.Primary ? " principal" : "")} {s.Bounds.Width}x{s.Bounds.Height} en ({s.Bounds.X},{s.Bounds.Y}), zone utile {s.WorkingArea.Width}x{s.WorkingArea.Height}"));
        });

        var w = _window();
        Try("Mode de fenêtre", () => w.SystemBackdropMode ? $"flou du système (DWM actif : {w.SystemBackdropActive})" : "compatible (AllowsTransparency, fenêtre en couches)");
        Try("DPI", () => { var d = VisualTreeHelper.GetDpi(w); return $"échelle WPF {d.DpiScaleX:0.00} x {d.DpiScaleY:0.00}" + (w.Hwnd != IntPtr.Zero ? $", DPI de la fenêtre {Native.GetDpiForWindow(w.Hwnd)}" : ""); });
        Try("Fenêtre (WPF)", () => $"visible={w.IsVisible} chargée={w.IsLoaded} gauche={w.Left:0} haut={w.Top:0} largeur={w.ActualWidth:0} hauteur={w.ActualHeight:0} topmost={w.Topmost}");
        Try("Fenêtre (rectangle réel Win32)", () =>
        {
            if (w.Hwnd == IntPtr.Zero) return "pas encore de poignée";
            var ok = Native.GetWindowRect(w.Hwnd, out var r);
            return $"GetWindowRect ok={ok} ({r.Left},{r.Top})-({r.Right},{r.Bottom}) = {r.Right - r.Left}x{r.Bottom - r.Top} px · IsWindowVisible={Native.IsWindowVisible(w.Hwnd)}";
        });
        Try("Style étendu", () => w.Hwnd == IntPtr.Zero ? "pas encore de poignée" : Native.DescribeExStyle(Native.GetExStyle(w.Hwnd)));
        Try("Clic-à-travers", () => w.ClickThroughActive ? "activé" : "désactivé");
        Try("Réglages", () => { var s = _store.Current; return $"style {s.Style}, {s.LineCountValue} ligne(s), pochette {s.ArtworkColors}, flou système {s.SystemBackdrop}, démarrage Windows {StartupRegistration.IsEnabled}"; });
        Try("Icône de notification", () => "créée" + (TrayVisible is { } t ? ", visible=" + t() : ""));
        Try("Spotify", () => _smtc.SessionAppId is { } id ? "session trouvée : " + id : "aucune session Spotify trouvée");
        Try("Sessions média vues", () => _smtc.KnownSessionIds);
        Try("Mémoire", () => { using var p = Process.GetCurrentProcess(); return $"{p.WorkingSet64 / 1048576.0:0.0} Mo ; CPU cumulé {p.TotalProcessorTime.TotalSeconds:0.0} s"; });
        Try("Journal", () => $"{Log.File.TotalFailures} échec(s) d'écriture depuis le lancement");
        return f;
    }

    /// <summary>Journal de démarrage : appelé une fois la fenêtre montrée.</summary>
    public void LogStartup()
    {
        try { foreach (var kv in Collect()) Log.Write("diag", $"{kv.Key} : {kv.Value}"); }
        catch (Exception e) { Log.WriteException("diag", "diagnostic de démarrage", e); }
    }

    /// <summary>Texte du presse-papiers : faits + 200 dernières lignes du journal, sans titre, artiste, paroles ni identifiant LRCLIB.</summary>
    public string BuildReport(IEnumerable<string>? secrets) =>
        DiagnosticReport.Build(AppIdentity.DisplayName, AppIdentity.Version, Collect(), Log.File.ReadTail(DiagnosticReport.TailLines), secrets);

    private static string ExeFolderKind()
    {
        var p = Environment.ProcessPath ?? "";
        var temp = Path.GetTempPath();
        if (p.StartsWith(temp, StringComparison.OrdinalIgnoreCase)) return "sous %TEMP% (probablement lancé depuis le zip : à extraire d'abord)";
        if (p.Contains(@"\Downloads\", StringComparison.OrdinalIgnoreCase)) return "dans Téléchargements";
        return "dossier ordinaire";
    }

    public void Dispose() => _perf.Stop();
}
