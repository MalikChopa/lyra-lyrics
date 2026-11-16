using System.Runtime.InteropServices;
using Drawing = System.Drawing;
using WinForms = System.Windows.Forms;

namespace LyraLyrics.App.Services;

/// <summary>
/// Icône de la zone de notification (WPF n'en fournit pas : <c>System.Windows.Forms.NotifyIcon</c>, déjà dans le runtime de bureau livré).
/// L'icône est celle de l'app (AppIcon.ico embarqué) ; une icône dessinée au lancement sert de secours. Menu : afficher/cacher, clic-à-travers, réglages, à propos, quitter.
/// </summary>
internal sealed class TrayService : IDisposable
{
    private readonly WinForms.NotifyIcon _icon;
    private readonly WinForms.ToolStripMenuItem _toggle = new("Cacher les paroles");
    private readonly WinForms.ToolStripMenuItem _clickThrough = new("Clic-à-travers") { CheckOnClick = false };
    private readonly Drawing.Icon _drawn;
    private readonly IntPtr _hIcon;

    public event Action? ToggleVisibility;
    public event Action? ToggleClickThrough;
    public event Action? OpenSettings;
    public event Action? OpenAbout;
    public event Action? OpenWelcome;
    public event Action? OpenUpdate;
    public event Action? CopyDiagnostic;
    public event Action? Quit;
    public bool IconVisible => _icon.Visible;
    /// <summary>Rappelé à l'ouverture du menu pour rafraîchir les libellés.</summary>
    public Func<(bool Visible, bool ClickThrough)>? State { get; set; }
    /// <summary>Étiquette de la version annoncée (« v1.2.0 »), null s'il n'y en a pas : l'entrée du menu n'apparaît que dans ce cas.</summary>
    public Func<string?>? UpdateTag { get; set; }
    private readonly WinForms.ToolStripMenuItem _update = new("Nouvelle version disponible") { Visible = false };

    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr hIcon);

    public TrayService(string name)
    {
        using var bmp = new Drawing.Bitmap(32, 32);
        using (var g = Drawing.Graphics.FromImage(bmp))
        {
            g.SmoothingMode = Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using var path = new Drawing.Drawing2D.GraphicsPath();
            const int r = 8;
            path.AddArc(1, 1, r * 2, r * 2, 180, 90); path.AddArc(31 - r * 2, 1, r * 2, r * 2, 270, 90);
            path.AddArc(31 - r * 2, 31 - r * 2, r * 2, r * 2, 0, 90); path.AddArc(1, 31 - r * 2, r * 2, r * 2, 90, 90);
            path.CloseFigure();
            using var brush = new Drawing.Drawing2D.LinearGradientBrush(new Drawing.Rectangle(0, 0, 32, 32), Drawing.Color.FromArgb(255, 255, 140, 60), Drawing.Color.FromArgb(255, 130, 70, 220), 45f);
            g.FillPath(brush, path);
            using var pen = new Drawing.Pen(Drawing.Color.White, 3f) { StartCap = Drawing.Drawing2D.LineCap.Round, EndCap = Drawing.Drawing2D.LineCap.Round };
            g.DrawLine(pen, 8, 11, 24, 11);
            g.DrawLine(pen, 8, 17, 24, 17);
            using var dim = new Drawing.Pen(Drawing.Color.FromArgb(150, 255, 255, 255), 3f) { StartCap = Drawing.Drawing2D.LineCap.Round, EndCap = Drawing.Drawing2D.LineCap.Round };
            g.DrawLine(dim, 8, 23, 18, 23);
        }
        _hIcon = bmp.GetHicon();
        _drawn = AppIcon.LoadTray() ?? Drawing.Icon.FromHandle(_hIcon);   // icône de l'app ; l'icône dessinée ci-dessus sert de secours

        var menu = new WinForms.ContextMenuStrip();
        _toggle.Click += (_, _) => ToggleVisibility?.Invoke();
        _clickThrough.Click += (_, _) => ToggleClickThrough?.Invoke();
        var settings = new WinForms.ToolStripMenuItem("Réglages…"); settings.Click += (_, _) => OpenSettings?.Invoke();
        var about = new WinForms.ToolStripMenuItem("À propos et droits…"); about.Click += (_, _) => OpenAbout?.Invoke();
        var welcome = new WinForms.ToolStripMenuItem("Bienvenue…"); welcome.Click += (_, _) => OpenWelcome?.Invoke();
        _update.Click += (_, _) => OpenUpdate?.Invoke();
        var diag = new WinForms.ToolStripMenuItem("Copier le diagnostic"); diag.Click += (_, _) => CopyDiagnostic?.Invoke();
        var quit = new WinForms.ToolStripMenuItem("Quitter " + name); quit.Click += (_, _) => Quit?.Invoke();
        menu.Items.AddRange(new WinForms.ToolStripItem[] { _toggle, _clickThrough, new WinForms.ToolStripSeparator(), settings, welcome, about, diag, _update, new WinForms.ToolStripSeparator(), quit });
        menu.Opening += (_, _) =>
        {
            if (UpdateTag?.Invoke() is { } tag) { _update.Text = "Nouvelle version disponible : " + tag; _update.Visible = true; } else _update.Visible = false;
            if (State?.Invoke() is { } st) { _toggle.Text = st.Visible ? "Cacher les paroles" : "Montrer les paroles"; _clickThrough.Checked = st.ClickThrough; }
        };
        _icon = new WinForms.NotifyIcon { Text = name, Icon = _drawn, Visible = true, ContextMenuStrip = menu };
        _icon.MouseClick += (_, e) => { if (e.Button == WinForms.MouseButtons.Left) ToggleVisibility?.Invoke(); };
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
        _drawn.Dispose();
        if (_hIcon != IntPtr.Zero) DestroyIcon(_hIcon);
    }
}
