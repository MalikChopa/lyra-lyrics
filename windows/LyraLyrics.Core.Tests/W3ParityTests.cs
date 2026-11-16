using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>W3 : fixtures PARTAGÉES avec Swift (<c>Tests/AppSupportTests/W3FixtureTests.swift</c>) : réglages et palette de pochette.</summary>
public class W3ParityTests
{
    private static bool Same(JsonElement? got, JsonElement want)
    {
        if (want.ValueKind == JsonValueKind.Null) return got is null || got.Value.ValueKind == JsonValueKind.Null;
        if (got is not { } g) return false;
        return want.ValueKind switch
        {
            JsonValueKind.String => g.ValueKind == JsonValueKind.String && string.Equals(g.GetString(), want.GetString(), StringComparison.OrdinalIgnoreCase),
            JsonValueKind.Number => g.ValueKind == JsonValueKind.Number && Math.Abs(g.GetDouble() - want.GetDouble()) < 1e-9,
            JsonValueKind.True or JsonValueKind.False => g.ValueKind == want.ValueKind,
            _ => false,
        };
    }

    private static Dictionary<string, JsonElement> Fields(Settings s)
    {
        using var d = JsonDocument.Parse(s.Encode());
        return d.RootElement.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
    }

    [Fact]
    public void SettingsDefaults_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/settings-defaults.json");
        var root = doc.RootElement;
        var fields = Fields(new Settings());
        var failures = new List<string>();
        var expectedKeys = new HashSet<string>();
        foreach (var p in root.GetProperty("common").EnumerateObject())
        {
            fields.TryGetValue(p.Name, out var got);
            if (!Same(fields.ContainsKey(p.Name) ? got : null, p.Value)) failures.Add($"{p.Name} = {(fields.ContainsKey(p.Name) ? got.ToString() : "absent")}, attendu {p.Value}");
            if (p.Value.ValueKind != JsonValueKind.Null) expectedKeys.Add(p.Name);
        }
        foreach (var k in root.GetProperty("sameKeyOwnDefault").EnumerateArray()) expectedKeys.Add(k.GetString()!);
        foreach (var k in root.GetProperty("windowsOnly").EnumerateArray()) expectedKeys.Add(k.GetString()!);
        if (!fields.Keys.ToHashSet().SetEquals(expectedKeys)) failures.Add("clés écrites : " + string.Join(",", fields.Keys.ToHashSet().SymmetricExcept(expectedKeys)));
        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [Fact]
    public void SettingsDecoding_SharedFixture_IsTolerant()
    {
        using var doc = Fixtures.Json("golden/settings-defaults.json");
        var failures = new List<string>();
        var n = 0;
        foreach (var c in doc.RootElement.GetProperty("decode").EnumerateArray())
        {
            n++;
            var name = c.GetProperty("name").GetString();
            var (s, outcome) = Settings.Decode(System.Text.Encoding.UTF8.GetBytes(c.GetProperty("input").GetString()!));
            var got = outcome switch { Settings.DecodeOutcome.Ok => "ok", Settings.DecodeOutcome.Corrupt => "corrupt", Settings.DecodeOutcome.Missing => "missing", _ => "newerVersion" };
            if (got != c.GetProperty("outcome").GetString()) failures.Add($"{name} : issue {got}");
            var fields = Fields(s);
            foreach (var e in c.GetProperty("expect").EnumerateObject())
                if (!Same(fields.TryGetValue(e.Name, out var v) ? v : null, e.Value)) failures.Add($"{name} : {e.Name} = {(fields.TryGetValue(e.Name, out var v2) ? v2.ToString() : "absent")}, attendu {e.Value}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.True(n >= 10);
    }

    [Fact]
    public void Settings_RoundTrip_KeepsEveryField_AndUnknownFieldsNeverResetTheFile()
    {
        var s = new Settings
        {
            WelcomeSeen = true, LaunchAtLogin = true, AutoHide = AutoHideMode.Paused, CheckUpdates = false, LastUpdateCheck = 1790000000.25,
            SceneScreen = "main", SceneEffects = false, AnimatedBackground = true, KaraokeFill = true, SceneLayout = SceneLayoutMode.LyricsOnly, Size = 33,
        };
        var (back, outcome) = Settings.Decode(s.Encode());
        Assert.Equal(Settings.DecodeOutcome.Ok, outcome);
        Assert.True(back.WelcomeSeen && back.LaunchAtLogin && !back.CheckUpdates && back.AnimatedBackground && back.KaraokeFill && !back.SceneEffects);
        Assert.Equal(AutoHideMode.Paused, back.AutoHide); Assert.Equal(1790000000.25, back.LastUpdateCheck);
        Assert.Equal("main", back.SceneScreen); Assert.Equal(SceneLayoutMode.LyricsOnly, back.SceneLayout); Assert.Equal(33, back.Size);
        // Un champ d'une version future dans un fichier de version 2 : le reste est lu, rien n'est remis à zéro.
        var withUnknown = System.Text.Encoding.UTF8.GetString(s.Encode()).Replace("\"size\": 33,", "\"size\": 33, \"champFutur\": {\"x\": [1]},");
        var (b2, o2) = Settings.Decode(System.Text.Encoding.UTF8.GetBytes(withUnknown));
        Assert.Equal(Settings.DecodeOutcome.Ok, o2); Assert.Equal(33, b2.Size); Assert.True(b2.WelcomeSeen);
    }

    [Fact]
    public void Palette_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/palette.json");
        var failures = new List<string>();
        var n = 0;
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            n++;
            var name = c.GetProperty("name").GetString();
            var px = new List<byte>();
            foreach (var f in c.GetProperty("fill").EnumerateArray())
            {
                var rgba = f.GetProperty("rgba").EnumerateArray().Select(x => (byte)x.GetInt32()).ToArray();
                for (var i = 0; i < f.GetProperty("count").GetInt32(); i++) px.AddRange(rgba);
            }
            var p = ArtworkPalette.FromRgba(px.ToArray(), c.GetProperty("width").GetInt32(), c.GetProperty("height").GetInt32());
            var want = c.GetProperty("expect");
            if (want.ValueKind == JsonValueKind.Null) { if (p is not null) failures.Add($"{name} : palette inattendue"); continue; }
            if (p is null) { failures.Add($"{name} : palette nulle"); continue; }
            var got = new Dictionary<string, string> { ["dominant"] = p.Dominant.Hex, ["secondary"] = p.Secondary.Hex, ["tint"] = p.Tint.Hex, ["accent"] = p.Accent.Hex };
            foreach (var kv in got) if (kv.Value != want.GetProperty(kv.Key).GetString()) failures.Add($"{name} : {kv.Key} = {kv.Value}, attendu {want.GetProperty(kv.Key)}");
            if (p.AccentContrast < ArtworkPalette.MinContrast) failures.Add($"{name} : contraste {p.AccentContrast}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.True(n >= 16);
    }
}

internal static class SetExt
{
    public static IEnumerable<string> SymmetricExcept(this HashSet<string> a, HashSet<string> b) => a.Except(b).Concat(b.Except(a)).OrderBy(x => x);
}

/// <summary>W3 : règles pures d'accessibilité, de l'attente S22 et du défilement non synchronisé.</summary>
public class W3PureTests
{
    [Fact]
    public void LineLook_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/linelook.json");
        var n = 0;
        foreach (var row in doc.RootElement.GetProperty("rows").EnumerateArray())
        {
            n++;
            int off = row[0].GetInt32(); double ratio = row[1].GetDouble();
            Assert.Equal(row[2].GetDouble(), LineLook.Scale(off, ratio), 9);
            Assert.Equal(row[3].GetDouble(), LineLook.Opacity(off), 9);
            Assert.Equal(row[4].GetDouble(), LineLook.Blur(off), 9);
            Assert.Equal(row[5].GetDouble(), LineLook.Opacity(off, true), 9);
        }
        Assert.True(n >= 10);
    }

    [Fact]
    public void Transparency_RegistryValue_AndEffectiveStyle()
    {
        Assert.False(AccessibilityPrefs.TransparencyFromRegistry(0));
        Assert.True(AccessibilityPrefs.TransparencyFromRegistry(1));
        Assert.True(AccessibilityPrefs.TransparencyFromRegistry(null));
        Assert.True(AccessibilityPrefs.TransparencyFromRegistry("0"));            // type inattendu : on ne coupe pas la transparence sur une valeur illisible
        var plain = new AccessibilityPrefs(true, false);
        Assert.Equal(BackgroundStyle.Solid, plain.EffectiveStyle(BackgroundStyle.Glass));
        Assert.Equal(BackgroundStyle.Solid, plain.EffectiveStyle(BackgroundStyle.Clear));
        Assert.Equal(BackgroundStyle.Solid, plain.EffectiveStyle(BackgroundStyle.Solid));
        Assert.Equal(BackgroundStyle.Clear, AccessibilityPrefs.Default.EffectiveStyle(BackgroundStyle.Clear));
    }

    [Fact]
    public void ShimmerBars_AreCentred_AndProportional()
    {
        var bars = ShimmerLayout.Bars(400, 70);
        Assert.Equal(3, bars.Count);
        Assert.Equal(312, bars[0].W, 9); Assert.Equal(368, bars[1].W, 9); Assert.Equal(240, bars[2].W, 9);
        Assert.All(bars, b => Assert.Equal(200, b.X + b.W / 2, 9));
        var used = 3 * 11 + 2 * 12;
        Assert.Equal((70 - used) / 2.0, bars[0].Y, 9);
        Assert.Equal(bars[0].Y + 23, bars[1].Y, 9);
        Assert.Equal(70 - (70 - used) / 2.0, bars[2].Y + bars[2].H, 9);
    }

    [Fact]
    public void UnsyncedScroll_Offsets_AndNextPlan()
    {
        var (from, to) = UnsyncedScrollMath.Offsets(0.25, 400, 8);
        Assert.Equal(-92, from, 9); Assert.Equal(-392, to, 9);
        var (f0, t0) = UnsyncedScrollMath.Offsets(0, -50, 8);                       // texte qui tient : aucun défilement
        Assert.Equal(8, f0, 9); Assert.Equal(8, t0, 9);
        Assert.Equal(240, UnsyncedScrollMath.Span(null)); Assert.Equal(240, UnsyncedScrollMath.Span(0)); Assert.Equal(180, UnsyncedScrollMath.Span(180));
        var start = new UnsyncedScrollPlan(0, 0, 0);
        var p = UnsyncedScrollMath.Next(start, 0, 10, 10, 200, playing: true, force: false)!.Value;       // lecture qui démarre
        Assert.Equal(0.05, p.Progress, 9); Assert.Equal(190, p.Remaining, 9); Assert.Equal(1, p.Stamp);
        Assert.Null(UnsyncedScrollMath.Next(p, 10, 70, 70, 200, true, false));                            // même trajectoire : pas de nouveau plan
        Assert.NotNull(UnsyncedScrollMath.Next(p, 10, 70, 100, 200, true, false));                        // saut de 30 s
        var paused = UnsyncedScrollMath.Next(p, 10, 70, 70, 200, false, false)!.Value;                    // pause
        Assert.Equal(0, paused.Remaining); Assert.Equal(0.35, paused.Progress, 9);
        var end = UnsyncedScrollMath.Next(paused, 70, 71, 199.99, 200, true, false)!.Value;               // presque fini : durée minimale
        Assert.Equal(UnsyncedScrollMath.MinRemaining, end.Remaining, 9);
        var (pr, rem) = UnsyncedScrollMath.Advance(new UnsyncedScrollPlan(0.2, 100, 3), 25);              // 25 s après l'armement
        Assert.Equal(0.4, pr, 9); Assert.Equal(75, rem, 9);
        Assert.Equal((0.2, 0.0), UnsyncedScrollMath.Advance(new UnsyncedScrollPlan(0.2, 0, 3), 25));
        Assert.Equal(UnsyncedScrollMath.MinRemaining, UnsyncedScrollMath.Advance(new UnsyncedScrollPlan(0.2, 100, 3), 500).Remaining, 9);
    }
}
