using System.Windows.Interop;
using LyraLyrics.Core;

namespace LyraLyrics.App.Services;

/// <summary>Raccourci global (RegisterHotKey) reçu par une fenêtre de messages invisible.</summary>
internal sealed class HotKeyService : IDisposable
{
    private const int HotKeyId = 0x4C59;      // « LY »
    private readonly HwndSource _source;
    private HotKeyCombo? _registered;
    public event Action? Pressed;
    public string? LastError { get; private set; }

    public HotKeyService()
    {
        var p = new HwndSourceParameters("LyraLyricsHotKey") { Width = 0, Height = 0, ParentWindow = new IntPtr(-3) /* HWND_MESSAGE */ };
        _source = new HwndSource(p);
        _source.AddHook(Hook);
    }

    private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_HOTKEY && wParam.ToInt32() == HotKeyId) { handled = true; Pressed?.Invoke(); }
        return IntPtr.Zero;
    }

    /// <summary>Enregistre (ou remplace) le raccourci. Rend faux, avec <see cref="LastError"/>, s'il est déjà pris ou invalide : l'ancien reste alors actif.</summary>
    public bool Register(HotKeyCombo combo)
    {
        LastError = null;
        if (!combo.IsValid) { LastError = "Combinaison non valide : ajoute Ctrl, Alt ou Win."; return false; }
        var previous = _registered;
        if (previous is not null) Native.UnregisterHotKey(_source.Handle, HotKeyId);
        if (Native.RegisterHotKey(_source.Handle, HotKeyId, combo.Modifiers | Native.MOD_NOREPEAT, combo.Key))
        {
            _registered = combo;
            Log.Write("hotkey", "enregistré " + combo.Display);
            return true;
        }
        LastError = $"{combo.Display} est déjà utilisé par une autre application.";
        Log.Write("hotkey", "échec d'enregistrement de " + combo.Display);
        if (previous is not null && Native.RegisterHotKey(_source.Handle, HotKeyId, previous.Modifiers | Native.MOD_NOREPEAT, previous.Key)) _registered = previous;
        else _registered = null;
        return false;
    }

    public void Dispose()
    {
        if (_registered is not null) Native.UnregisterHotKey(_source.Handle, HotKeyId);
        _source.RemoveHook(Hook);
        _source.Dispose();
    }
}
