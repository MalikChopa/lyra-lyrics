using System.Runtime.InteropServices;
using WinForms = System.Windows.Forms;

namespace LyraLyrics.App.Services;

/// <summary>Un écran : nom affiché (celui du réglage « écran de la Scène »), rectangle en PIXELS du bureau virtuel, échelle (1 = 96 ppp), écran principal.</summary>
internal sealed record ScreenInfo(string Name, int X, int Y, int Width, int Height, double Scale, bool Primary)
{
    public double DipWidth => Width / Scale;
    public double DipHeight => Height / Scale;
}

/// <summary>
/// Liste des écrans (S10). Le nom est celui du moniteur donné par le pilote (« DELL U2720Q » ; « Generic PnP Monitor » à défaut), sinon le nom
/// de l'adaptateur (« \\.\DISPLAY1 »). Les noms ne sont pas forcément uniques : le premier correspondant gagne, comme sur le Mac.
/// Non vérifié sur Windows : si les noms sont vides ou identiques, le journal écrit « écrans : N » avec la taille de chacun (sans nom).
/// </summary>
internal static class ScreenCatalog
{
    public static IReadOnlyList<ScreenInfo> List()
    {
        var result = new List<ScreenInfo>();
        foreach (var s in WinForms.Screen.AllScreens)
        {
            var b = s.Bounds;
            result.Add(new ScreenInfo(FriendlyName(s.DeviceName), b.X, b.Y, b.Width, b.Height, ScaleOf(b), s.Primary));
        }
        return result;
    }

    public static IReadOnlyList<string> Names() => List().Select(s => s.Name).ToList();

    public static int PrimaryIndex(IReadOnlyList<ScreenInfo> screens)
    {
        for (var i = 0; i < screens.Count; i++) if (screens[i].Primary) return i;
        return 0;
    }

    /// <summary>Indice de l'écran qui contient (le plus) la fenêtre <paramref name="hwnd"/> ; 0 si elle est introuvable.</summary>
    public static int IndexOfWindow(IReadOnlyList<ScreenInfo> screens, IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !Native.GetWindowRect(hwnd, out var r)) return 0;
        var best = 0; long bestArea = -1;
        for (var i = 0; i < screens.Count; i++)
        {
            var s = screens[i];
            long w = Math.Max(0, Math.Min(r.Right, s.X + s.Width) - Math.Max(r.Left, s.X));
            long h = Math.Max(0, Math.Min(r.Bottom, s.Y + s.Height) - Math.Max(r.Top, s.Y));
            if (w * h > bestArea) { bestArea = w * h; best = i; }
        }
        return best;
    }

    private static double ScaleOf(System.Drawing.Rectangle bounds)
    {
        try
        {
            var mon = Native.MonitorFromPoint(new Native.POINT { X = bounds.X + bounds.Width / 2, Y = bounds.Y + bounds.Height / 2 }, Native.MONITOR_DEFAULTTONEAREST);
            if (mon != IntPtr.Zero && Native.GetDpiForMonitor(mon, Native.MDT_EFFECTIVE_DPI, out var dx, out _) == 0 && dx > 0) return dx / 96.0;
        }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException or COMException) { }
        return 1.0;
    }

    private static string FriendlyName(string adapter)
    {
        try
        {
            var dd = new Native.DISPLAY_DEVICE { cb = Marshal.SizeOf<Native.DISPLAY_DEVICE>() };
            if (Native.EnumDisplayDevices(adapter, 0, ref dd, 0) && !string.IsNullOrWhiteSpace(dd.DeviceString)) return dd.DeviceString.Trim();
        }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException or COMException) { }
        return adapter;
    }
}
