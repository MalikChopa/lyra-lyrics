using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LyraLyrics.App.Services;
using LyraLyrics.App.Smtc;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Mode caché <c>--snapshot &lt;dossier&gt;</c> (build Release, comme le <c>--snapshot</c> du Mac) : rend hors écran, avec <see cref="RenderTargetBitmap"/>, la petite fenêtre
/// dans ses trois styles et la Scène (« Avec la pochette », « Paroles seules » avec la carte du titre, passage sans paroles, barre de commandes) à
/// 1920 × 1080 et 3840 × 2160, puis s'arrête. Contenu INVENTÉ (titre, artiste, paroles) et pochette générée : jamais de vraies paroles, jamais de réseau, jamais
/// d'écriture hors du dossier demandé (réglages dans ce dossier, journal désactivé). Sert au contrôle de la version à la sortie : la CI Windows le lance et publie
/// les PNG comme artefact séparé. Que WPF sache dessiner sur un exécuteur sans bureau interactif n'est PAS vérifié : chaque image est protégée
/// séparément et <c>snapshot-rapport.txt</c> liste ce qui a réussi ou échoué (type d'exception seulement).
/// </summary>
internal static class SnapshotMode
{
    private static readonly (int W, int H, double Scale, string Name)[] Sizes = { (1920, 1080, 1.0, "1080p"), (3840, 2160, 1.5, "4k") };

    // Contenu inventé : un morceau imaginaire, des phrases sans lien avec une œuvre existante.
    private const string DemoTitle = "Chanson d'essai";
    private const string DemoArtist = "Artiste imaginaire";
    private static readonly (double Time, string Text)[] DemoLines =
    {
        (6, "Une lumière tremble au bout du couloir"), (12, "Les horloges ont oublié leur tour"), (18, "On marche sans bruit sur le papier peint"),
        (24, "Le vent range les nuages par couleur"), (30, "Quelqu'un compte les étoiles à voix basse"), (60, "Les valises dorment près de la porte"),
        (66, "Demain n'a pas encore de nom"), (72, "On inventera une langue pour le dire"), (78, "Et le jour se lèvera sans prévenir"),
        (84, "Une lumière tremble au bout du couloir"), (90, "Les horloges ont oublié leur tour"), (96, "On marche sans bruit sur le papier peint"),
    };

    public static int Run(string dir)
    {
        Log.Silent = true;
        var report = new List<string>();
        int ok = 0, failed = 0;
        try
        {
            Directory.CreateDirectory(dir);
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var art = MakeArtwork();
            foreach (var size in Sizes)
            {
                void Shot(string name, Func<BitmapSource> make)
                {
                    try
                    {
                        var image = make();
                        var file = Path.Combine(dir, $"{name}-{size.Name}.png");
                        using var fs = File.Create(file);
                        var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(image)); enc.Save(fs);
                        report.Add($"OK {Path.GetFileName(file)} {image.PixelWidth}x{image.PixelHeight}"); ok++;
                    }
                    catch (Exception e) { report.Add($"ECHEC {name}-{size.Name} : {e.GetType().Name} 0x{e.HResult:x8}"); failed++; }
                }
                foreach (var style in new[] { BackgroundStyle.Solid, BackgroundStyle.Glass, BackgroundStyle.Clear })
                    Shot("fenetre-" + style.ToString().ToLowerInvariant(), () => SmallWindow(dir, style, size, art));
                // positions : 26 s tombe dans la ligne de 24 s (ligne chantée, pas de passage) ; 45 s dans le passage sans paroles de 30 à 60 s
                const double Sung = 26;
                Shot("scene-avec-pochette", () => Scene(dir, size, art, SceneLayoutMode.WithArtwork, Sung, playing: false, SceneWindow.DemoKind.Normal, "scene-avec-pochette-" + size.Name, Expect.Lines, report));
                Shot("scene-paroles-seules-lignes", () => Scene(dir, size, art, SceneLayoutMode.LyricsOnly, Sung, playing: false, SceneWindow.DemoKind.Lines, "scene-paroles-seules-lignes-" + size.Name, Expect.Lines, report));
                Shot("scene-paroles-seules-carte", () => Scene(dir, size, art, SceneLayoutMode.LyricsOnly, Sung, playing: false, SceneWindow.DemoKind.Card, "scene-paroles-seules-carte-" + size.Name, Expect.Card, report));
                Shot("scene-passage-sans-paroles", () => Scene(dir, size, art, SceneLayoutMode.LyricsOnly, position: 45, playing: false, SceneWindow.DemoKind.Gap, "scene-passage-sans-paroles-" + size.Name, Expect.None, report));
                Shot("scene-barre-de-commandes", () => Scene(dir, size, art, SceneLayoutMode.WithArtwork, Sung, playing: true, SceneWindow.DemoKind.Controls, "scene-barre-de-commandes-" + size.Name, Expect.Lines, report));
            }
            app.Dispatcher.InvokeShutdown();
        }
        catch (Exception e) { report.Add($"ECHEC général : {e.GetType().Name} 0x{e.HResult:x8}"); failed++; }
        try { File.WriteAllLines(Path.Combine(dir, "snapshot-rapport.txt"), report.Append($"RESULTAT réussies={ok} échecs={failed}")); } catch { }
        return failed == 0 && ok > 0 ? 0 : 1;
    }

    // ---- Éléments de démonstration

    private sealed record Art(byte[] Png, byte[] Rgba, int Side);

    /// <summary>Pochette GÉNÉRÉE : dégradé diagonal et deux cercles, aucune image existante.</summary>
    private static Art MakeArtwork()
    {
        const int side = 400;
        var rgba = new byte[side * side * 4];
        for (var y = 0; y < side; y++)
            for (var x = 0; x < side; x++)
            {
                var t = (x + y) / (2.0 * side);
                double r = 40 + 190 * t, g = 70 + 60 * (1 - t), b = 160 - 90 * t;
                double d1 = Math.Sqrt(Math.Pow(x - 130, 2) + Math.Pow(y - 140, 2)), d2 = Math.Sqrt(Math.Pow(x - 280, 2) + Math.Pow(y - 270, 2));
                if (d1 < 70) { r = 255; g = 214; b = 120; }
                if (d2 < 55) { r = 250; g = 120; b = 150; }
                var i = (y * side + x) * 4;
                rgba[i] = (byte)Math.Clamp(r, 0, 255); rgba[i + 1] = (byte)Math.Clamp(g, 0, 255); rgba[i + 2] = (byte)Math.Clamp(b, 0, 255); rgba[i + 3] = 255;
            }
        var bgra = (byte[])rgba.Clone();
        for (var i = 0; i < side * side; i++) (bgra[i * 4], bgra[i * 4 + 2]) = (bgra[i * 4 + 2], bgra[i * 4]);
        var bmp = BitmapSource.Create(side, side, 96, 96, PixelFormats.Bgra32, null, bgra, side * 4);
        using var ms = new MemoryStream();
        var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(bmp)); enc.Save(ms);
        return new Art(ms.ToArray(), rgba, side);
    }

    private static (AppModel Model, SettingsStore Store) Setup(string dir, Art art, double position, bool playing, Action<Settings> tune)
    {
        var store = new SettingsStore(Path.Combine(dir, "reglages-snapshot.json"));
        store.Update(tune);
        // aucun accès réseau : transport qui refuse tout, et le modèle ne lance jamais de recherche (Offline)
        var service = new LyricsService(new LrclibClient(new RefusingTransport(), "snapshot"), null, x => x, Clock.Seconds, Clock.Sleep);
        var model = new AppModel(Dispatcher.CurrentDispatcher, service, new SmtcMonitor()) { Offline = true };
        var track = new TrackInfo(DemoTitle, DemoArtist, "Album imaginaire", 215, "snapshot-1", "snapshot");
        var lyrics = Lyrics.Synced(DemoLines.Select(l => new LyricLine(l.Time, l.Text)).ToList(), null, "démonstration");
        model.LoadDemo(track, lyrics, position, playing, art.Png, ArtworkPalette.FromRgba(art.Rgba, art.Side, art.Side));
        return (model, store);
    }

    private sealed class RefusingTransport : ILrclibTransport
    {
        public Task<HttpReply> SendAsync(LrclibRequest request, double timeoutSeconds, CancellationToken ct) => throw new InvalidOperationException("réseau interdit en mode captures");
    }

    private static BitmapSource SmallWindow(string dir, BackgroundStyle style, (int W, int H, double Scale, string Name) size, Art art)
    {
        var (model, store) = Setup(dir, art, 40.5, false, s => { s.Style = style; s.KaraokeFill = false; s.AnimatedBackground = false; });
        var w = new LyricsWindow(model, store, systemBackdrop: false);
        return w.RenderForSnapshot(size.W, size.H, size.Scale, Color.FromRgb(36, 52, 92), Color.FromRgb(20, 120, 140));
    }

    /// <summary>Ce qu'un cliché doit montrer : des lignes dont la courante (chantée), la carte du titre, ou rien de particulier (passage).</summary>
    private enum Expect { None, Lines, Card }

    private static BitmapSource Scene(string dir, (int W, int H, double Scale, string Name) size, Art art, SceneLayoutMode layout, double position, bool playing, SceneWindow.DemoKind kind, string shot, Expect expect, List<string> report)
    {
        var (model, store) = Setup(dir, art, position, playing, s => { s.SceneLayout = layout; s.KaraokeFill = false; s.SceneEffects = true; });
        var screen = new ScreenInfo("Écran de démonstration", 0, 0, size.W, size.H, size.Scale, true);
        var scene = new SceneWindow(model, store, screen);
        try
        {
            scene.Prepare();
            scene.ApplyDemo(kind);
            var image = scene.Snapshot();                       // refait la mise en page avant le rendu ; le contrôle ci-dessous la lit
            var st = scene.Inspect();
            report.Add($"INFO {shot} carte={st.CardVisible}/{st.CardTotal} lignes={st.LinesVisible} courante={st.CurrentLinesVisible}");
            if (expect == Expect.Card && st.CardVisible < 3) report.Add($"WARNING {shot} : cliché suspect, carte du titre attendue mais {st.CardVisible} élément(s) visible(s) sur {st.CardTotal}");
            if (expect == Expect.Lines && (st.LinesVisible < 1 || st.CurrentLinesVisible < 1)) report.Add($"WARNING {shot} : cliché suspect, ligne chantée attendue mais lignes={st.LinesVisible} courante={st.CurrentLinesVisible}");
            if (expect == Expect.Lines && st.CardVisible > 0) report.Add($"WARNING {shot} : cliché suspect, carte visible alors qu'elle n'est pas attendue ({st.CardVisible})");
            return image;
        }
        finally { try { scene.Shutdown(); } catch { } }
    }
}
