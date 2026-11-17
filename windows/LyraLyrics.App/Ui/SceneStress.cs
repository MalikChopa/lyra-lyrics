using System.IO;
using System.Windows;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Mode caché de la CI (build Release). <c>--scene-stress &lt;dossier&gt;</c> lance, l'un après l'autre, <see cref="Trials"/> essais, CHACUN dans un processus enfant
/// (<c>--scene-stress-one &lt;n&gt; &lt;dossier&gt;</c>) : un plantage natif d'un essai ne coupe pas les suivants, et le code de sortie de chaque enfant est consigné (en hexadécimal
/// pour un NTSTATUS). Essais 1 à 4 : la VRAIE Scène à l'écran, les deux mises en page (« Avec la pochette », « Paroles seules » avec la carte du titre), chacune karaoké ÉTEINT (avec la
/// lueur du texte) puis karaoké ALLUMÉ. Essai 5 : la PETITE fenêtre réelle à l'écran, karaoké allumé. Modèle de lecture truqué (titre, artiste et paroles INVENTÉS, pochette générée),
/// position en temps réel, une ligne par seconde, au moins <see cref="MinChanges"/> changements de ligne par essai. Rien n'est écrit hors du dossier demandé (réglages et rapport), le
/// journal de l'utilisateur n'est pas touché, aucun réseau. <c>stress-rapport.txt</c> est complété à chaque étape (ouvert-écrit-fermé) : si un enfant meurt en silence, la dernière ligne
/// avant sa ligne « code » est la dernière étape atteinte. Dernière ligne du rapport : <c>RESULTAT essais=N plantages=K</c> (plantage = code négatif ou &gt; 255, ou enfant tué après délai).
/// Code de sortie de l'enfant : 0 = fini, 1 = exception, 2 = délai interne. Sans bureau interactif (exécuteur sans session), la fenêtre peut ne pas s'ouvrir : le rapport le dit, la CI ne bloque jamais.
/// </summary>
internal static class SceneStress
{
    public const int MinChanges = 10;
    public const double RunSeconds = 13;
    public const int Trials = 5;
    private const int ChildTimeoutSeconds = 70;
    private const double OverallTimeout = 120;

    private static readonly string[] Phrases =
    {
        "Une lumière tremble au bout du couloir", "Les horloges ont oublié leur tour", "On marche sans bruit sur le papier peint",
        "Le vent range les nuages par couleur", "Quelqu'un compte les étoiles à voix basse, une par une, jusqu'à l'aube",
        "Les valises dorment près de la porte", "Demain n'a pas encore de nom", "On inventera une langue pour le dire",
        "Et le jour se lèvera sans prévenir", "Un train imaginaire traverse la pièce",
    };

    private static string _file = "";
    private static readonly object Gate = new();
    private static readonly System.Diagnostics.Stopwatch Clock0 = System.Diagnostics.Stopwatch.StartNew();

    private static void Note(string line)
    {
        try { lock (Gate) File.AppendAllText(_file, $"{Clock0.Elapsed.TotalSeconds:000.0} {line}{Environment.NewLine}"); } catch { }
    }

    /// <summary>Code de sortie d'un enfant : plantage natif si négatif ou hors d'un octet ; texte lisible pour le rapport.</summary>
    internal static (bool Crash, string Text) Describe(int code) =>
        code is < 0 or > 255 ? (true, $"0x{(uint)code:X8} (plantage natif)") : (false, code == 0 ? "0 (fini)" : code == 1 ? "1 (exception)" : code == 2 ? "2 (délai interne)" : code.ToString());

    /// <summary>Processus parent : un enfant par essai, puis la ligne finale. Pas de WPF ici.</summary>
    public static int Run(string dir)
    {
        try
        {
            Directory.CreateDirectory(dir);
            _file = Path.Combine(dir, "stress-rapport.txt");
            File.WriteAllText(_file, "Essai de charge (contenu inventé), un processus par essai" + Environment.NewLine);
        }
        catch { return 1; }
        var exe = Environment.ProcessPath;
        var crashes = 0;
        for (var n = 1; n <= Trials; n++)
        {
            Note($"LANCEMENT essai {n}/{Trials}");
            string text; bool crash;
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo(exe!) { UseShellExecute = false };
                psi.ArgumentList.Add("--scene-stress-one"); psi.ArgumentList.Add(n.ToString()); psi.ArgumentList.Add(dir);
                using var child = System.Diagnostics.Process.Start(psi)!;
                if (child.WaitForExit(ChildTimeoutSeconds * 1000)) (crash, text) = Describe(child.ExitCode);
                else { try { child.Kill(true); } catch { } crash = true; text = $"enfant tué après {ChildTimeoutSeconds} s (blocage)"; }
            }
            catch (Exception e) { crash = true; text = "lancement impossible : " + e.GetType().Name; }
            if (crash) crashes++;
            Note($"CODE essai {n} : {text}");
        }
        Note($"RESULTAT essais={Trials} plantages={crashes}");
        return crashes == 0 ? 0 : 1;
    }

    /// <summary>Processus enfant : un seul essai (1 à 4 : Scène ; 5 : petite fenêtre).</summary>
    public static int RunOne(int trial, string dir)
    {
        Log.Silent = true;
        var exceptions = 0;
        try { Directory.CreateDirectory(dir); _file = Path.Combine(dir, "stress-rapport.txt"); }
        catch { return 1; }
        Note($"DEBUT enfant essai {trial}");
        SceneWindow.CrumbHook = step => Note("étape: " + step);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Note("EXCEPTION fatale : " + (e.ExceptionObject as Exception)?.GetType().FullName);
        var code = 0;
        try
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            app.DispatcherUnhandledException += (_, e) => { exceptions++; Note($"EXCEPTION {e.Exception.GetType().FullName} 0x{e.Exception.HResult:x8}"); e.Handled = true; };
            var watchdog = new DispatcherTimer { Interval = TimeSpan.FromSeconds(OverallTimeout) };
            watchdog.Tick += (_, _) => { Note("DELAI DEPASSE"); code = 2; app.Shutdown(); };
            watchdog.Start();
            app.Startup += async (_, _) =>
            {
                try
                {
                    var screens = ScreenCatalog.List();
                    var screen = screens.Count > 0 ? screens[ScreenCatalog.PrimaryIndex(screens)] : new ScreenInfo("Écran de repli", 0, 0, 1280, 720, 1.0, true);
                    Note($"écran {screen.Width}x{screen.Height} échelle {screen.Scale:0.##} ; écrans={screens.Count}");
                    var art = SnapshotMode.MakeArtwork();
                    exceptions += trial == 5
                        ? await OneRunSmall(dir, art, trial)
                        : await OneRun(dir, art, screen, trial <= 2 ? SceneLayoutMode.WithArtwork : SceneLayoutMode.LyricsOnly, trial % 2 == 0, trial);
                }
                catch (Exception e) { exceptions++; Note($"EXCEPTION {e.GetType().FullName} 0x{e.HResult:x8}"); }
                finally { watchdog.Stop(); app.Shutdown(); }
            };
            app.Run();
        }
        catch (Exception e) { Note($"EXCEPTION {e.GetType().FullName} 0x{e.HResult:x8}"); exceptions++; }
        if (code == 0 && exceptions > 0) code = 1;
        Note($"FIN enfant essai {trial} : code={code} exceptions={exceptions}");
        return code;
    }

    private static async Task<int> OneRun(string dir, SnapshotMode.Art art, ScreenInfo screen, SceneLayoutMode layout, bool karaoke, int n)
    {
        var tag = $"essai {n} : {(layout == SceneLayoutMode.WithArtwork ? "avec pochette" : "paroles seules")}, karaoké {(karaoke ? "allumé" : "éteint")}";
        Note("DEBUT " + tag);
        var store = new SettingsStore(Path.Combine(dir, "reglages-stress.json"));
        store.Update(s => { s.SceneLayout = layout; s.KaraokeFill = karaoke; s.Glow = !karaoke; s.SceneEffects = true; });
        var service = new LyricsService(new LrclibClient(new SnapshotMode.RefusingTransport(), "stress"), null, x => x, Services.Clock.Seconds, Services.Clock.Sleep);
        var model = new AppModel(Dispatcher.CurrentDispatcher, service, new SmtcMonitor()) { Offline = true };
        var track = new TrackInfo("Chanson d'essai", "Artiste imaginaire", "Album imaginaire", 215, "stress-" + n, "stress");
        // une ligne par seconde dès la 2e seconde : au moins 8 changements en 8 s
        var lines = Enumerable.Range(0, 60).Select(i => new LyricLine(2 + i * 1.0, Phrases[i % Phrases.Length])).ToList();
        model.LoadDemo(track, Lyrics.Synced(lines, null, "démonstration"), 0.5, playing: true, art.Png, ArtworkPalette.FromRgba(art.Rgba, art.Side, art.Side));
        var errors = 0;
        SceneWindow? scene = null;
        try
        {
            scene = new SceneWindow(model, store, screen);
            scene.Show();
            scene.Start();
            model.SetSceneVisible(true);
            Note("Scène affichée");
            var changes = 0; var last = model.CurrentIndex;
            var end = DateTime.UtcNow.AddSeconds(RunSeconds + (layout == SceneLayoutMode.LyricsOnly ? 3 : 0));      // la carte du titre masque les lignes ~3 s au début
            while (DateTime.UtcNow < end)
            {
                await Task.Delay(100);
                if (model.CurrentIndex != last) { last = model.CurrentIndex; changes++; Note($"ligne vue {changes}"); }
            }
            Note($"FIN {tag} : changements de ligne vus={changes}" + (changes < MinChanges ? $" (ATTENTION moins de {MinChanges})" : ""));
        }
        catch (Exception e) { errors++; Note($"EXCEPTION {tag} : {e.GetType().FullName} 0x{e.HResult:x8}"); }
        finally
        {
            try { model.SetSceneVisible(false); scene?.Shutdown(); } catch (Exception e) { errors++; Note($"EXCEPTION fermeture : {e.GetType().FullName}"); }
        }
        return errors;
    }

    /// <summary>Essai 5 : la petite fenêtre réelle à l'écran, karaoké allumé (même technique de remplissage que la Scène : deux couches et découpage à la main).</summary>
    private static async Task<int> OneRunSmall(string dir, SnapshotMode.Art art, int n)
    {
        const string tag = "petite fenêtre, karaoké allumé";
        Note("DEBUT essai " + n + " : " + tag);
        var store = new SettingsStore(Path.Combine(dir, "reglages-stress.json"));
        store.Update(s => { s.KaraokeFill = true; s.Style = BackgroundStyle.Glass; s.AnimatedBackground = false; s.Size = 30; });
        var service = new LyricsService(new LrclibClient(new SnapshotMode.RefusingTransport(), "stress"), null, x => x, Services.Clock.Seconds, Services.Clock.Sleep);
        var model = new AppModel(Dispatcher.CurrentDispatcher, service, new SmtcMonitor()) { Offline = true };
        var track = new TrackInfo("Chanson d'essai", "Artiste imaginaire", "Album imaginaire", 215, "stress-" + n, "stress");
        var lines = Enumerable.Range(0, 60).Select(i => new LyricLine(2 + i * 1.0, Phrases[i % Phrases.Length])).ToList();
        model.LoadDemo(track, Lyrics.Synced(lines, null, "démonstration"), 0.5, playing: true, art.Png, ArtworkPalette.FromRgba(art.Rgba, art.Side, art.Side));
        var errors = 0;
        LyricsWindow? window = null;
        try
        {
            window = new LyricsWindow(model, store, systemBackdrop: false);
            window.Show();
            window.ShowFloating();
            Note("Petite fenêtre affichée");
            var changes = 0; var last = model.CurrentIndex;
            var end = DateTime.UtcNow.AddSeconds(RunSeconds);
            while (DateTime.UtcNow < end)
            {
                await Task.Delay(100);
                if (model.CurrentIndex != last) { last = model.CurrentIndex; changes++; Note($"ligne vue {changes}"); }
            }
            Note($"FIN {tag} : changements de ligne vus={changes}" + (changes < MinChanges ? $" (ATTENTION moins de {MinChanges})" : ""));
        }
        catch (Exception e) { errors++; Note($"EXCEPTION {tag} : {e.GetType().FullName} 0x{e.HResult:x8}"); }
        finally
        {
            try { window?.Close(); } catch (Exception e) { errors++; Note($"EXCEPTION fermeture : {e.GetType().FullName}"); }
        }
        return errors;
    }
}
