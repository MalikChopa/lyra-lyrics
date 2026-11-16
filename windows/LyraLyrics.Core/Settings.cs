using System.Text.Json;

namespace LyraLyrics.Core;

public enum BackgroundStyle { Solid, Glass, Clear }

public static class BackgroundStyleExt
{
    public static string Label(this BackgroundStyle s) => s switch { BackgroundStyle.Solid => "Uni", BackgroundStyle.Glass => "Verre", _ => "Transparent" };
    /// <summary>◐ : Uni → Verre → Transparent → Uni.</summary>
    public static BackgroundStyle Next(this BackgroundStyle s) => s switch { BackgroundStyle.Solid => BackgroundStyle.Glass, BackgroundStyle.Glass => BackgroundStyle.Clear, _ => BackgroundStyle.Solid };
}

public enum LyricFont { System, Serif, Mono, Geometric, Rounded }

public static class LyricFontExt
{
    public static string Label(this LyricFont f) => f switch
    {
        LyricFont.System => "Système (Segoe UI)", LyricFont.Serif => "Serif (Georgia)", LyricFont.Mono => "Mono (Consolas)",
        LyricFont.Geometric => "Géométrique (Bahnschrift)", _ => "Arrondie (Calibri)",
    };
    /// <summary>Liste de familles WPF avec repli.</summary>
    public static string Family(this LyricFont f) => f switch
    {
        LyricFont.System => "Segoe UI Variable Display, Segoe UI", LyricFont.Serif => "Georgia, Cambria, Times New Roman",
        LyricFont.Mono => "Consolas, Cascadia Mono, Courier New", LyricFont.Geometric => "Bahnschrift, Segoe UI", _ => "Calibri, Segoe UI",
    };
}

public enum LyricWeight { Light, Regular, Semibold, Bold }

public static class LyricWeightExt
{
    public static string Label(this LyricWeight w) => w switch { LyricWeight.Light => "Fin", LyricWeight.Regular => "Normal", LyricWeight.Semibold => "Semi-gras", _ => "Gras" };
}

public static class LineCount
{
    public static readonly int[] Allowed = { 1, 3, 5 };
    public const int Default = 3;
    public static int Clamped(int n) => n <= 1 ? 1 : n >= 5 ? 5 : n == 2 ? 3 : n == 4 ? 5 : n;
}

public enum FontTheme { Classic, Elegant, Neon, Minimal, Custom }

public sealed record FontThemeSpec(LyricFont Font, LyricWeight Weight, int ColorIndex, bool Glow, double NeighbourRatio);

public static class FontThemeExt
{
    public static readonly FontTheme[] Ready = { FontTheme.Classic, FontTheme.Elegant, FontTheme.Neon, FontTheme.Minimal };
    public static string Label(this FontTheme t) => t switch { FontTheme.Classic => "Classique", FontTheme.Elegant => "Élégant", FontTheme.Neon => "Néon", FontTheme.Minimal => "Minimal", _ => "Personnalisé" };
    public static FontThemeSpec? Spec(this FontTheme t) => t switch
    {
        FontTheme.Classic => new(LyricFont.System, LyricWeight.Bold, 0, false, 0.66),
        FontTheme.Elegant => new(LyricFont.Serif, LyricWeight.Semibold, 1, false, 0.70),
        FontTheme.Neon => new(LyricFont.Rounded, LyricWeight.Bold, 2, true, 0.62),
        FontTheme.Minimal => new(LyricFont.System, LyricWeight.Light, 0, false, 0.72),
        _ => null,
    };
}

/// <summary>Quand masquer la fenêtre toute seule (1.1.0, C1 ; stocké, pas encore utilisé : W4). Mêmes valeurs que le Mac.</summary>
public enum AutoHideMode { Never, Paused, Idle }

/// <summary>Mise en page de la Scène (1.1.0 ; stockée, pas encore utilisée : W6). Mêmes valeurs que le Mac.</summary>
public enum SceneLayoutMode { LyricsOnly, WithArtwork }

/// <summary>Position mémorisée : coin haut-gauche en pixels indépendants de l'appareil (DIP) sur le bureau virtuel.</summary>
public sealed record WindowPosition(double Left, double Top);

/// <summary>
/// Réglages versionnés (port de Settings.swift), stockés en JSON dans %APPDATA%\LyraLyrics\settings.json. Aucun texte de paroles.
/// Décodage tolérant : champ absent ou invalide → valeur par défaut ; valeur hors plage → ramenée dans la plage.
/// </summary>
public sealed class Settings
{
    /// <summary>Version 2 (comme le Mac 1.1.0) : « Remplissage karaoké » ramené à désactivé une seule fois pour un fichier de version 1.</summary>
    public const int CurrentVersion = 2;
    public const int SizeMin = 18, SizeMax = 44, OpacityMin = 0, OpacityMax = 85;
    public static readonly string[] Swatches = { "#ffffff", "#ffe27a", "#8fd3ff", "#ffb3d1", "#a8f0b4" };

    public int Version { get; set; } = CurrentVersion;
    public BackgroundStyle Style { get; set; } = BackgroundStyle.Glass;
    public int Size { get; set; } = 26;
    public int BackgroundOpacity { get; set; } = 38;
    public LyricFont Font { get; set; } = LyricFont.System;
    public int ColorIndex { get; set; }
    public bool ClickThrough { get; set; }
    public HotKeyCombo HotKey { get; set; } = HotKeyCombo.Default;
    public WindowPosition? Position { get; set; }
    public int LineCountValue { get; set; } = LineCount.Default;
    public LyricWeight FontWeight { get; set; } = LyricWeight.Bold;
    public bool Glow { get; set; }
    public double NeighbourRatio { get; set; } = 0.66;
    public bool ArtworkColors { get; set; } = true;
    public double? WindowWidth { get; set; }
    public double? WindowHeight { get; set; }
    /// <summary>Flou acrylique du système (Windows 11 build ≥ 22621). Désactivé par défaut dans le build de test (non testable hors du PC).</summary>
    public bool SystemBackdrop { get; set; }
    // ---- Champs 1.1.0 du Mac (mêmes noms et mêmes défauts, fixture golden/settings-defaults.json). Stockés ; fonctions à venir :
    // welcomeSeen (accueil, W4), launchAtLogin (intention ; l'état réel est relu dans le registre, W4), autoHide et checkUpdates/lastUpdateCheck (W4),
    // sceneScreen/sceneEffects/sceneLayout (Scène, W6), animatedBackground et karaokeFill (S24, W6).
    public bool WelcomeSeen { get; set; }
    public bool LaunchAtLogin { get; set; }
    public AutoHideMode AutoHide { get; set; } = AutoHideMode.Idle;
    public bool CheckUpdates { get; set; } = true;
    /// <summary>Date (secondes depuis 1970) de la dernière vérification de mise à jour ; null = jamais.</summary>
    public double? LastUpdateCheck { get; set; }
    /// <summary>Scène : « window » (écran de la fenêtre, défaut), « main » (principal) ou « name:&lt;nom&gt; ».</summary>
    public string SceneScreen { get; set; } = "window";
    public bool SceneEffects { get; set; } = true;
    public bool AnimatedBackground { get; set; }
    public bool KaraokeFill { get; set; }
    public SceneLayoutMode SceneLayout { get; set; } = SceneLayoutMode.WithArtwork;

    /// <summary>Sel aléatoire de l'index disque (D4), généré au premier lancement.</summary>
    public string IndexSalt { get; set; } = "";

    public FontTheme Theme
    {
        get
        {
            var current = new FontThemeSpec(Font, FontWeight, ColorIndex, Glow, NeighbourRatio);
            return FontThemeExt.Ready.FirstOrDefault(t => t.Spec() == current, FontTheme.Custom);
        }
    }

    public void Apply(FontTheme theme)
    {
        if (theme.Spec() is not { } s) return;
        Font = s.Font; FontWeight = s.Weight; ColorIndex = s.ColorIndex; Glow = s.Glow; NeighbourRatio = s.NeighbourRatio;
    }

    public string ColorHex => Swatches[Math.Clamp(ColorIndex, 0, Swatches.Length - 1)];

    public void Clamp()
    {
        Size = Math.Clamp(Size, SizeMin, SizeMax);
        BackgroundOpacity = Math.Clamp(BackgroundOpacity, OpacityMin, OpacityMax);
        ColorIndex = Math.Clamp(ColorIndex, 0, Swatches.Length - 1);
        LineCountValue = LineCount.Clamped(LineCountValue);
        if (WindowWidth is double w && WindowHeight is double h && double.IsFinite(w) && double.IsFinite(h))
        { WindowWidth = Math.Max(w, LyricsMetrics.MinResizeWidth); WindowHeight = Math.Max(h, LyricsMetrics.MinResizeHeight); }
        else { WindowWidth = null; WindowHeight = null; }
        NeighbourRatio = double.IsFinite(NeighbourRatio) ? Math.Clamp(NeighbourRatio, 0.5, 0.85) : 0.66;
        if (!HotKey.IsValid) HotKey = HotKeyCombo.Default;
        if (Position is { } p && (!double.IsFinite(p.Left) || !double.IsFinite(p.Top))) Position = null;
    }

    public enum DecodeOutcome { Ok, Missing, Corrupt, NewerVersion }

    /// <summary>Décode des données stockées. Absentes, illisibles ou d'une version plus récente → défauts.</summary>
    public static (Settings Settings, DecodeOutcome Outcome) Decode(byte[]? data)
    {
        if (data is null) return (new Settings(), DecodeOutcome.Missing);
        try
        {
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return (new Settings(), DecodeOutcome.Corrupt);
            var s = new Settings();
            if (root.TryGetProperty("version", out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var ver) && ver > CurrentVersion)
                return (new Settings(), DecodeOutcome.NewerVersion);
            s.Style = Enum(root, "style", s.Style);
            s.Size = Int(root, "size", s.Size);
            s.BackgroundOpacity = Int(root, "backgroundOpacity", s.BackgroundOpacity);
            s.Font = Enum(root, "font", s.Font);
            s.ColorIndex = Int(root, "colorIndex", s.ColorIndex);
            s.ClickThrough = Bool(root, "clickThrough", s.ClickThrough);
            s.LineCountValue = Int(root, "lineCount", s.LineCountValue);
            s.FontWeight = Enum(root, "fontWeight", s.FontWeight);
            s.Glow = Bool(root, "glow", s.Glow);
            s.NeighbourRatio = Num(root, "neighbourRatio") ?? s.NeighbourRatio;
            s.ArtworkColors = Bool(root, "artworkColors", s.ArtworkColors);
            s.WindowWidth = Num(root, "windowWidth");
            s.WindowHeight = Num(root, "windowHeight");
            s.SystemBackdrop = Bool(root, "systemBackdrop", s.SystemBackdrop);
            s.WelcomeSeen = Bool(root, "welcomeSeen", s.WelcomeSeen);
            s.LaunchAtLogin = Bool(root, "launchAtLogin", s.LaunchAtLogin);
            s.AutoHide = Enum(root, "autoHide", s.AutoHide);
            s.CheckUpdates = Bool(root, "checkUpdates", s.CheckUpdates);
            s.LastUpdateCheck = Num(root, "lastUpdateCheck") is double luc && double.IsFinite(luc) ? luc : null;
            if (root.TryGetProperty("sceneScreen", out var scr) && scr.ValueKind == JsonValueKind.String) s.SceneScreen = scr.GetString() ?? s.SceneScreen;
            s.SceneEffects = Bool(root, "sceneEffects", s.SceneEffects);
            s.AnimatedBackground = Bool(root, "animatedBackground", s.AnimatedBackground);
            s.KaraokeFill = Bool(root, "karaokeFill", s.KaraokeFill);
            s.SceneLayout = Enum(root, "sceneLayout", s.SceneLayout);
            if (root.TryGetProperty("indexSalt", out var salt) && salt.ValueKind == JsonValueKind.String) s.IndexSalt = salt.GetString() ?? "";
            if (root.TryGetProperty("hotKey", out var hk) && hk.ValueKind == JsonValueKind.Object)
            {
                try { s.HotKey = hk.Deserialize<HotKeyCombo>() ?? s.HotKey; } catch (JsonException) { }
            }
            if (root.TryGetProperty("position", out var pos) && pos.ValueKind == JsonValueKind.Object)
            {
                var l = Num(pos, "left"); var t = Num(pos, "top");
                if (l is double ll && t is double tt) s.Position = new WindowPosition(ll, tt);
            }
            // Comme le Mac : un fichier de version 1 (ou sans version) voit le karaoké ramené à « désactivé » une seule fois.
            var storedVersion = root.TryGetProperty("version", out var sv) && sv.ValueKind == JsonValueKind.Number && sv.TryGetInt32(out var sver) ? sver : 1;
            if (storedVersion < 2) s.KaraokeFill = false;
            s.Version = CurrentVersion;
            s.Clamp();
            return (s, DecodeOutcome.Ok);
        }
        catch (JsonException) { return (new Settings(), DecodeOutcome.Corrupt); }

        static int Int(JsonElement r, string n, int d) => r.TryGetProperty(n, out var e) && e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out var i) ? i : d;
        static double? Num(JsonElement r, string n) => r.TryGetProperty(n, out var e) && e.ValueKind == JsonValueKind.Number ? e.GetDouble() : null;
        static bool Bool(JsonElement r, string n, bool d) => r.TryGetProperty(n, out var e) && e.ValueKind is JsonValueKind.True or JsonValueKind.False ? e.GetBoolean() : d;
        static T Enum<T>(JsonElement r, string n, T d) where T : struct, Enum =>
            r.TryGetProperty(n, out var e) && e.ValueKind == JsonValueKind.String && System.Enum.TryParse<T>(e.GetString(), true, out var v) && System.Enum.IsDefined(v) ? v : d;
    }

    public byte[] Encode()
    {
        using var ms = new MemoryStream();
        using (var w = new Utf8JsonWriter(ms, new JsonWriterOptions { Indented = true }))
        {
            w.WriteStartObject();
            w.WriteNumber("version", CurrentVersion);
            w.WriteString("style", Style.ToString());
            w.WriteNumber("size", Size);
            w.WriteNumber("backgroundOpacity", BackgroundOpacity);
            w.WriteString("font", Font.ToString());
            w.WriteNumber("colorIndex", ColorIndex);
            w.WriteBoolean("clickThrough", ClickThrough);
            w.WritePropertyName("hotKey"); JsonSerializer.Serialize(w, HotKey);
            if (Position is { } p) { w.WriteStartObject("position"); w.WriteNumber("left", p.Left); w.WriteNumber("top", p.Top); w.WriteEndObject(); }
            w.WriteNumber("lineCount", LineCountValue);
            w.WriteString("fontWeight", FontWeight.ToString());
            w.WriteBoolean("glow", Glow);
            w.WriteNumber("neighbourRatio", NeighbourRatio);
            w.WriteBoolean("artworkColors", ArtworkColors);
            if (WindowWidth is double ww) w.WriteNumber("windowWidth", ww);
            if (WindowHeight is double wh) w.WriteNumber("windowHeight", wh);
            w.WriteBoolean("systemBackdrop", SystemBackdrop);
            w.WriteBoolean("welcomeSeen", WelcomeSeen);
            w.WriteBoolean("launchAtLogin", LaunchAtLogin);
            w.WriteString("autoHide", AutoHide.ToString());
            w.WriteBoolean("checkUpdates", CheckUpdates);
            if (LastUpdateCheck is double luc) w.WriteNumber("lastUpdateCheck", luc);
            w.WriteString("sceneScreen", SceneScreen);
            w.WriteBoolean("sceneEffects", SceneEffects);
            w.WriteBoolean("animatedBackground", AnimatedBackground);
            w.WriteBoolean("karaokeFill", KaraokeFill);
            w.WriteString("sceneLayout", SceneLayout.ToString());
            w.WriteString("indexSalt", IndexSalt);
            w.WriteEndObject();
        }
        return ms.ToArray();
    }
}
