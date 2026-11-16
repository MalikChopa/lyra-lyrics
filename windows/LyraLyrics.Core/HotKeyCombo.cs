using System.Text.Json.Serialization;

namespace LyraLyrics.Core;

/// <summary>Raccourci global « Cacher / montrer ». Modificateurs au format Win32 (<c>RegisterHotKey</c>), touche = code de touche virtuelle.</summary>
public sealed record HotKeyCombo(
    [property: JsonPropertyName("modifiers")] uint Modifiers,
    [property: JsonPropertyName("key")] uint Key,
    [property: JsonPropertyName("label")] string Label)
{
    public const uint ModAlt = 0x1, ModControl = 0x2, ModShift = 0x4, ModWin = 0x8;
    public const uint AllModifiers = ModAlt | ModControl | ModShift | ModWin;
    /// <summary>Ctrl ou Alt ou Win exigé (Maj seul est une frappe de texte).</summary>
    public const uint RequiredOneOf = ModAlt | ModControl | ModWin;

    /// <summary>Ctrl+Alt+Maj+L : pas le ⌃⌥⌘L du Mac (⌘ = touche Windows, réservée au shell ; Ctrl+Alt seul = AltGr sur beaucoup de claviers).</summary>
    public static readonly HotKeyCombo Default = new(ModControl | ModAlt | ModShift, 0x4C, "L");

    public bool IsValid => Key != 0 && (Modifiers & RequiredOneOf) != 0 && (Modifiers & ~AllModifiers) == 0;

    /// <summary>Affichage : Ctrl+Alt+Maj+L.</summary>
    public string Display
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & ModControl) != 0) parts.Add("Ctrl");
            if ((Modifiers & ModAlt) != 0) parts.Add("Alt");
            if ((Modifiers & ModShift) != 0) parts.Add("Maj");
            if ((Modifiers & ModWin) != 0) parts.Add("Win");
            parts.Add(Label);
            return string.Join("+", parts);
        }
    }
}
