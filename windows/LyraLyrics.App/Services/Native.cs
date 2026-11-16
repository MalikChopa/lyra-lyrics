using System.Runtime.InteropServices;

namespace LyraLyrics.App.Services;

/// <summary>Appels Win32 / DWM. Rien ici ne peut être exécuté sur la machine de développement (Mac) : tout est à tester sur le PC.</summary>
internal static class Native
{
    public const int GWL_EXSTYLE = -20;
    public const long WS_EX_TRANSPARENT = 0x00000020L, WS_EX_TOOLWINDOW = 0x00000080L, WS_EX_LAYERED = 0x00080000L,
                      WS_EX_NOACTIVATE = 0x08000000L, WS_EX_TOPMOST = 0x00000008L;
    public static readonly IntPtr HWND_TOPMOST = new(-1);
    public const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40;
    public const uint LWA_ALPHA = 0x2;
    public const int WM_HOTKEY = 0x0312;
    public const uint MOD_NOREPEAT = 0x4000;

    // DWM
    public const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    public const int DWMWA_SYSTEMBACKDROP_TYPE = 38;
    public const int DWMSBT_NONE = 1, DWMSBT_TRANSIENTWINDOW = 3;     // 3 = acrylique
    public const int DWMWCP_ROUND = 2;

    public const uint SPI_GETCLIENTAREAANIMATION = 0x1042;

    /// <summary>Lecture directe (non mise en cache par WPF) de « Afficher les animations dans Windows ».</summary>
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, ref int value, uint winIni);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS { public int Left, Right, Top, Bottom; }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    public static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);

    // ---- Scène (W6b) : écrans, DPI, veille de l'écran
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    public const uint MONITOR_DEFAULTTONEAREST = 2;
    public const int MDT_EFFECTIVE_DPI = 0;

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromPoint(POINT pt, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [DllImport("shcore.dll")]
    public static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool EnumDisplayDevices(string? lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    /// <summary>Notification de l'état de l'écran (allumé / éteint / atténué) : GUID_CONSOLE_DISPLAY_STATE.</summary>
    public static readonly Guid GuidConsoleDisplayState = new("6fe69556-704a-47a0-8f24-c28d936fda47");
    public const uint DEVICE_NOTIFY_WINDOW_HANDLE = 0;
    public const int WM_POWERBROADCAST = 0x0218, PBT_POWERSETTINGCHANGE = 0x8013;

    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr RegisterPowerSettingNotification(IntPtr hRecipient, ref Guid powerSettingGuid, uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnregisterPowerSettingNotification(IntPtr handle);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    public struct POWERBROADCAST_SETTING { public Guid PowerSetting; public uint DataLength; public byte Data; }

    public static long GetExStyle(IntPtr hwnd) => GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();

    /// <summary>Ajoute / retire des bits de style étendu. Rend le code d'erreur Win32 du dernier SetWindowLongPtr (0 = rien à signaler).</summary>
    public static int SetExStyle(IntPtr hwnd, long add, long remove = 0)
    {
        var current = GetExStyle(hwnd);
        var next = (current | add) & ~remove;
        if (next == current) return 0;
        System.Runtime.InteropServices.Marshal.SetLastSystemError(0);
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(next));
        return Marshal.GetLastWin32Error();
    }

    /// <summary>Style étendu en clair (pour le journal) : « 0x08080088 [LAYERED NOACTIVATE TOOLWINDOW TOPMOST] ».</summary>
    public static string DescribeExStyle(long style)
    {
        var names = new List<string>();
        if ((style & WS_EX_LAYERED) != 0) names.Add("LAYERED");
        if ((style & WS_EX_TRANSPARENT) != 0) names.Add("TRANSPARENT");
        if ((style & WS_EX_NOACTIVATE) != 0) names.Add("NOACTIVATE");
        if ((style & WS_EX_TOOLWINDOW) != 0) names.Add("TOOLWINDOW");
        if ((style & WS_EX_TOPMOST) != 0) names.Add("TOPMOST");
        return $"0x{style:x8} [{string.Join(" ", names)}]";
    }

    public const int DWMWA_CLOAKED = 13;

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int attrValue, int attrSize);

    /// <summary>Vrai si DWM a « masqué » la fenêtre (cloaked) : c'est le cas d'une fenêtre qui se trouve sur un AUTRE bureau virtuel. Faux en cas d'échec.</summary>
    public static bool IsCloaked(IntPtr hwnd)
    {
        try { return hwnd != IntPtr.Zero && DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out var v, sizeof(int)) == 0 && v != 0; }
        catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { return false; }
    }

    public static bool SetDwmInt(IntPtr hwnd, int attr, int value) => DwmSetWindowAttribute(hwnd, attr, ref value, sizeof(int)) == 0;

    public static void BringToTopmost(IntPtr hwnd) =>
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    /// <summary>Windows 11 22H2 (build 22621) ou plus : seuil de l'attribut de fond système (acrylique).</summary>
    public static bool SupportsSystemBackdrop => Environment.OSVersion.Version.Build >= 22621;
}
