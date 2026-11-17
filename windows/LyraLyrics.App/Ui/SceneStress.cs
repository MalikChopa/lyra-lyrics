using System.IO;
using System.Windows;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Mode caché <c>--scene-stress &lt;dossier&gt;</c> (CI, build Release) : ouvre la VRAIE Scène à l'écran (pas hors écran) avec un modèle de lecture truqué (titre, artiste et
/// paroles INVENTÉS, pochette générée) dont la position avance en temps réel ; une ligne change chaque seconde, au moins <see cref="MinChanges"/> fois par essai. Quatre essais d'environ
/// <see cref="RunSeconds"/> s : les deux mises en page (« Avec la pochette », « Paroles seules » avec la carte du titre), chacune karaoké ÉTEINT (avec la lueur du texte, la dernière combinaison
/// effet + transformation animée) puis karaoké ALLUMÉ. Rien n'est écrit hors du dossier demandé (réglages et rapport), le journal de l'utilisateur n'est pas touché, aucun réseau.
/// <c>stress-rapport.txt</c> est complété à chaque étape (<see cref="SceneWindow.CrumbHook"/>, ouvert-écrit-fermé) : si le processus meurt en silence, la dernière ligne est la dernière étape
/// atteinte. Code de sortie : 0 = fini sans exception, 1 = exception, 2 = délai dépassé (la CI note un code négatif ou NTSTATUS en hexadécimal : plantage natif).
/// Sans bureau interactif (exécuteur sans session), la fenêtre peut ne pas s'ouvrir : le rapport le dit, la CI ne bloque jamais.
/// </summary>
internal static class SceneStress
{
    public const int MinChanges = 8;
    public const double RunSeconds = 8;
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

    public static int Run(string dir)
    {
        Log.Silent = true;
        var exceptions = 0;
        try
        {
            Directory.CreateDirectory(dir);
            _file = Path.Combine(dir, "stress-rapport.txt");
            File.WriteAllText(_file, "Scène : essai de charge (contenu inventé)" + Environment.NewLine);
        }
        catch { return 1; }

        Note("DEBUT");
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
                    var n = 0;
                    foreach (var layout in new[] { SceneLayoutMode.WithArtwork, SceneLayoutMode.LyricsOnly })
                        foreach (var karaoke in new[] { false, true })
                        {
                            n++;
                            exceptions += await OneRun(dir, art, screen, layout, karaoke, n);
                        }
                }
                catch (Exception e) { exceptions++; Note($"EXCEPTION {e.GetType().FullName} 0x{e.HResult:x8}"); }
                finally { watchdog.Stop(); app.Shutdown(); }
            };
            app.Run();
        }
        catch (Exception e) { Note($"EXCEPTION {e.GetType().FullName} 0x{e.HResult:x8}"); exceptions++; }
        if (code == 0 && exceptions > 0) code = 1;
        Note($"RESULTAT code={code} exceptions={exceptions}");
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
                if (model.CurrentIndex != last) { last = model.CurrentIndex; changes++; }
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
}
