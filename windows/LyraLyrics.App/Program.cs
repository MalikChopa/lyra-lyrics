using System.Diagnostics;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Ui;

namespace LyraLyrics.App;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        // Mode caché pour le contrôle de la version à la sortie : `LyraLyrics.exe --snapshot <dossier>` ; ni instance unique, ni journal, ni réseau.
        var at = Array.IndexOf(args, "--snapshot");
        if (at >= 0 && at + 1 < args.Length) { Environment.Exit(SnapshotMode.Run(args[at + 1])); return; }
        try { Run(); }
        catch (Exception ex) { Fail("avant l'ouverture de la fenêtre", ex); }
    }

    private static void Run()
    {
        // Une seule instance : une seconde ouverture demande à la première de montrer sa fenêtre, puis s'arrête.
        using var mutex = new Mutex(true, @"Local\LyraLyrics.SingleInstance", out var created);
        var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\LyraLyrics.Show");
        if (!created) { showEvent.Set(); return; }

        // Erreurs non observées : tout est journalisé en entier (type, HResult, message, pile).
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception ex) Log.WriteException("erreur", "exception fatale", ex);
            else Log.Write("erreur", "exception fatale : " + e.ExceptionObject.GetType().FullName);
        };
        TaskScheduler.UnobservedTaskException += (_, e) => { Log.WriteException("erreur", "tâche non observée", e.Exception); e.SetObserved(); };

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var started = false;
        app.DispatcherUnhandledException += (_, e) =>
        {
            Log.WriteException("erreur", "exception non gérée", e.Exception);
            if (started) { e.Handled = true; return; }          // la fenêtre de paroles ne tombe jamais pour une erreur d'affichage...
            e.Handled = true;                                    // ... mais avant la fin du démarrage, rien n'est utilisable : on le dit et on quitte
            Fail("pendant le démarrage", e.Exception);
        };

        AppController? controller = null;
        app.Startup += async (_, _) =>
        {
            try
            {
                controller = new AppController();
                var waiter = new Thread(() =>
                {
                    while (showEvent.WaitOne()) app.Dispatcher.BeginInvoke(() => { try { controller?.ShowFromOtherInstance(); } catch (Exception ex) { Log.WriteException("erreur", "réouverture", ex); } });
                }) { IsBackground = true, Name = "LyraShowWaiter" };
                waiter.Start();
                await controller.StartAsync();
                started = true;
            }
            catch (Exception ex)
            {
                try { controller?.Dispose(); } catch { }
                Fail("au démarrage", ex);
            }
        };
        app.Exit += (_, _) => controller?.Dispose();
        app.Run();
    }

    /// <summary>
    /// Constat 3 : un échec de démarrage est toujours visible (boîte de message), entièrement journalisé, et le processus se termine
    /// (plus de processus invisible tenant l'instance unique).
    /// </summary>
    private static void Fail(string moment, Exception ex)
    {
        try { Log.WriteException("erreur", "échec " + moment, ex); } catch { }
        try
        {
            System.Windows.MessageBox.Show(
                "Lyra Lyrics n'a pas pu démarrer (" + moment + ").\n\nErreur : " + ex.GetType().Name + " (0x" + ex.HResult.ToString("x8") + ")\n\nLe détail est dans le journal :\n" + AppPaths.LogFile +
                "\n\nEnvoie ce fichier (il ne contient ni titre, ni artiste, ni paroles).",
                "Lyra Lyrics", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        catch { }
        Environment.Exit(1);
    }
}
