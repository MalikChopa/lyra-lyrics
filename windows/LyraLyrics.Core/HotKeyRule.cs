namespace LyraLyrics.Core;

/// <summary>
/// Raccourci global (décision du 2026-11-17) : il BASCULE le clic-à-travers dans les deux sens ; si la fenêtre est cachée, il la montre
/// (l'appui ne semble jamais ne rien faire) ; il ne la cache jamais. Cacher / montrer la fenêtre passe par le menu de la zone de notification.
/// Règle pure, même fixture que Swift (<c>Sources/AppSupport/HotKeyRule.swift</c>) : <c>Fixtures/golden/hotkey.json</c>.
/// </summary>
public static class HotKeyRule
{
    public readonly record struct Outcome(bool ClickThrough, bool ShowWindow);

    public static Outcome Decide(bool windowShown, bool clickThrough) => new(!clickThrough, !windowShown);
}
