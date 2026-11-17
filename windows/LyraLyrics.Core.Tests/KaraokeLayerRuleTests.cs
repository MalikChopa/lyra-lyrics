using LyraLyrics.Core;
using Xunit;

namespace LyraLyrics.Core.Tests;

/// <summary>Règle sur laquelle repose le remplissage en deux couches : part remplie de chaque ligne rendue pour une part totale donnée (Schedule non animé = « état figé à f »).</summary>
public class KaraokeLayerRuleTests
{
    private static double Part(double[] cum, int i, double f) => KaraokeFill.Schedule(cum, i, f, 4, false, false).Start;

    [Fact]
    public void DeuxLignesEgales_LaSecondeAttendLaPremiere()
    {
        var cum = KaraokeFill.Cumulative(new[] { 100.0, 100.0 });
        Assert.Equal(0.5, Part(cum, 0, 0.25), 6);
        Assert.Equal(0.0, Part(cum, 1, 0.25), 6);
        Assert.Equal(1.0, Part(cum, 0, 0.75), 6);
        Assert.Equal(0.5, Part(cum, 1, 0.75), 6);
    }

    [Fact]
    public void Bornes_RienPuisTout()
    {
        var cum = KaraokeFill.Cumulative(new[] { 30.0, 70.0 });
        Assert.Equal(0.0, Part(cum, 0, 0), 6); Assert.Equal(0.0, Part(cum, 1, 0), 6);
        Assert.Equal(1.0, Part(cum, 0, 1), 6); Assert.Equal(1.0, Part(cum, 1, 1), 6);
    }

    [Fact]
    public void UneSeuleLigne_SuitLaPartTotale()
    {
        var cum = KaraokeFill.Cumulative(new[] { 250.0 });
        foreach (var f in new[] { 0.0, 0.1, 0.5, 0.99, 1.0 }) Assert.Equal(f, Part(cum, 0, f), 6);
    }
}
