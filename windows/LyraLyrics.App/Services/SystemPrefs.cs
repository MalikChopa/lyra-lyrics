using System.Windows.Threading;
using LyraLyrics.Core;
using Microsoft.Win32;

namespace LyraLyrics.App.Services;

/// <summary>
/// Préférences d'accessibilité de Windows (« Afficher les animations », « Effets de transparence »), lues UNE fois au démarrage puis seulement
/// quand le système signale un changement de réglage (<see cref="SystemEvents.UserPreferenceChanged"/>), jamais à chaque image.
/// Les décisions (style effectif) sont dans le Core (<see cref="AccessibilityPrefs"/>, testé sur Mac) ; seule la lecture est ici (non vérifié sur Windows).
/// </summary>
internal static class SystemPrefs
{
    private static Dispatcher? _ui;
    public static AccessibilityPrefs Current { get; private set; } = AccessibilityPrefs.Default;
    public static event Action? Changed;

    public static void Start(Dispatcher ui)
    {
        _ui = ui;
        Current = Read();
        Log.Write("app", $"accessibilité : animations {(Current.AnimationsEnabled ? "oui" : "non")}, transparence {(Current.TransparencyEnabled ? "oui" : "non")}");
        SystemEvents.UserPreferenceChanged += OnChanged;
    }

    public static void Stop() => SystemEvents.UserPreferenceChanged -= OnChanged;

    private static void OnChanged(object? sender, UserPreferenceChangedEventArgs e)
    {
        // Événement levé sur un fil du système : on relit puis on prévient l'interface sur son fil.
        _ui?.BeginInvoke(() =>
        {
            var now = Read();
            if (now == Current) return;
            Current = now;
            Log.Write("app", $"accessibilité changée : animations {(now.AnimationsEnabled ? "oui" : "non")}, transparence {(now.TransparencyEnabled ? "oui" : "non")}");
            Changed?.Invoke();
        });
    }

    private static AccessibilityPrefs Read()
    {
        var animations = true;
        try
        {
            var v = 1;
            animations = Native.SystemParametersInfo(Native.SPI_GETCLIENTAREAANIMATION, 0, ref v, 0) ? v != 0 : System.Windows.SystemParameters.ClientAreaAnimation;
        }
        catch { }
        var transparency = true;
        try
        {
            using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            transparency = AccessibilityPrefs.TransparencyFromRegistry(k?.GetValue("EnableTransparency"));
        }
        catch { }
        return new AccessibilityPrefs(animations, transparency);
    }
}
