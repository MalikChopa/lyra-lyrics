namespace LyraLyrics.Core.Tests;

/// <summary>W6c+d : règles propres à Windows (le Mac les fait avec Core Animation) : particules, grain, vignette, règles de sobriété.</summary>
public class W6cdTests
{
    [Fact]
    public void Particles_BudgetStaysUnderThirty_AndEveryParticleIsSlowAndSmall()
    {
        Assert.Equal(27, GapParticles.Budget);
        Assert.True(GapParticles.Budget <= GapParticles.Maximum);
        for (var i = 0; i < GapParticles.Budget; i++)
        {
            var p = GapParticles.At(i);
            var speed = Math.Sqrt(p.Vx * p.Vx + p.Vy * p.Vy);
            Assert.InRange(speed, GapParticles.SpeedMean - GapParticles.SpeedRange - 1e-9, GapParticles.SpeedMean + GapParticles.SpeedRange + 1e-9);
            Assert.True(p.Vy < 0, "toujours vers le haut");
            Assert.InRange(p.XFraction, 0, 1);
            Assert.InRange(p.Diameter, GapParticles.DotSide * (GapParticles.ScaleMean - GapParticles.ScaleRange) - 1e-9, GapParticles.DotSide * (GapParticles.ScaleMean + GapParticles.ScaleRange) + 1e-9);
            Assert.Equal(i / GapParticles.BirthRate, p.Delay, 9);
        }
        Assert.Equal(GapParticles.At(5), GapParticles.At(5));
        Assert.NotEqual(GapParticles.At(5), GapParticles.At(6));
    }

    [Fact]
    public void Particles_AlphaFadesToZeroBeforeTheEndOfLife()
    {
        Assert.Equal(0.55, GapParticles.OpacityAt(0), 9);
        Assert.Equal(0, GapParticles.OpacityAt(GapParticles.Lifetime), 9);
        Assert.Equal(0, GapParticles.OpacityAt(100), 9);
        Assert.Equal(0.55, GapParticles.OpacityAt(-3), 9);
        Assert.True(GapParticles.OpacityAt(4) < GapParticles.OpacityAt(2));
    }

    [Fact]
    public void Grain_IsVeryLight_AndPremultiplied()
    {
        var tile = SceneGrain.Tile();
        Assert.Equal(SceneGrain.Side * SceneGrain.Side * 4, tile.Length);
        var light = 0; var dark = 0;
        for (var i = 0; i < tile.Length; i += 4)
        {
            var a = tile[i + 3];
            Assert.InRange(a, 0, SceneGrain.MaxAlpha);
            Assert.True(tile[i] <= a, "prémultiplié : la couleur ne dépasse jamais l'opacité");
            Assert.Equal(tile[i], tile[i + 1]); Assert.Equal(tile[i], tile[i + 2]);
            if (tile[i] > 0) light++; else dark++;
        }
        Assert.True(light > 10000 && dark > 10000, $"clair {light}, sombre {dark} : les deux doivent exister");
        Assert.Equal(tile, SceneGrain.Tile());                       // reproductible pour une graine donnée
        Assert.True(SceneGrain.MaxAlpha / 255.0 < 0.04, "moins de 4 %");
    }

    [Fact]
    public void Card_OnlyWithoutTheArtworkLayout_AndAboutThreeSeconds()
    {
        Assert.False(SceneCard.Allowed(true));
        Assert.True(SceneCard.Allowed(false));
        Assert.InRange(SceneCard.Total(false), 3.0, 3.5);
        Assert.InRange(SceneCard.Total(true), 2.0, 2.2);
    }

    [Fact]
    public void Vignette_IsSubtle()
    {
        Assert.True(SceneGrain.VignetteAlpha <= 0.4);
        Assert.InRange(SceneGrain.VignetteClearUntil, 0.5, 0.6);
    }

    [Fact]
    public void LyricPosition_AddsLeadAndManualOffset()
    {
        var m = new PlaybackModel(() => 100, new NoEffects());
        var lead = new SyncEngine().EffectivePosition(0);
        Assert.Equal(lead, m.LyricPosition, 6);
    }

    private sealed class NoEffects : IPlaybackEffects
    {
        public void StartLookup(TrackInfo track, string identity) { }
        public void RetryLookup(TrackInfo track, string identity) { }
        public void RevertToAutomatic(TrackInfo track, string identity) { }
        public void CancelLookup() { }
        public void SetServiceOnline(bool online) { }
        public void ClearCache() { }
        public void Log(string zone, string message) { }
    }
}
