using System.Reflection;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Drawing = System.Drawing;

namespace LyraLyrics.App.Services;

/// <summary>
/// Icône de l'application : le même fichier <c>AppIcon.ico</c> que celui de l'exe (<c>ApplicationIcon</c>), aussi embarqué comme ressource.
/// Fenêtres : <see cref="Wpf"/> ; zone de notification : <see cref="LoadTray"/> (taille d'icône du système, nette en haute densité).
/// En cas d'échec, rien ne casse : fenêtres sans icône, icône de zone de notification dessinée par <see cref="TrayService"/>.
/// </summary>
internal static class AppIcon
{
    private const string ResourceName = "AppIcon.ico";

    private static Stream? Open() => Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName);

    /// <summary>Source d'icône pour <c>Window.Icon</c> (la plus grande taille de l'ensemble ; Windows la réduit au besoin).</summary>
    public static ImageSource? Wpf { get; } = LoadWpf();

    private static ImageSource? LoadWpf()
    {
        try
        {
            using var s = Open();
            if (s is null) return null;
            var decoder = BitmapDecoder.Create(s, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var best = decoder.Frames.OrderByDescending(f => f.PixelWidth).First();
            best.Freeze();
            return best;
        }
        catch (Exception e) { Log.Write("erreur", "icône des fenêtres : " + e.GetType().Name); return null; }
    }

    /// <summary>Icône de la zone de notification à la taille « petite icône » du système ; <c>null</c> si le fichier est illisible.</summary>
    public static Drawing.Icon? LoadTray()
    {
        try
        {
            using var s = Open();
            return s is null ? null : new Drawing.Icon(s, System.Windows.Forms.SystemInformation.SmallIconSize);
        }
        catch (Exception e) { Log.Write("erreur", "icône de la zone de notification : " + e.GetType().Name); return null; }
    }
}
