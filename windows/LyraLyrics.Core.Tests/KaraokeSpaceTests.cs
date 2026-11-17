using LyraLyrics.Core;
using Xunit;

namespace LyraLyrics.Core.Tests;

/// <summary>le remplissage karaoké part exactement de la première lettre de chaque ligne rendue et finit à la dernière.</summary>
public class KaraokeSpaceTests
{
    private static KaraokeSpace.Box B(double x, double y, double w, double h) => new(x, y, w, h);

    [Fact]
    public void Frame_enlarges_the_block_by_the_margin()
    {
        var f = KaraokeSpace.Frame(300, 80, 10);
        Assert.Equal(B(-10, -10, 320, 100), f);
    }

    [Fact]
    public void Frame_never_has_negative_size() => Assert.Equal(B(-24, -24, 48, 48), KaraokeSpace.Frame(-5, -1));

    [Theory]
    [InlineData(0, 300)]      // ligne alignée à gauche : première lettre au bord du bloc
    [InlineData(57.5, 185)]   // ligne centrée dans un bloc de 300 : marge gauche 57,5
    [InlineData(120, 60)]     // ligne courte très centrée
    public void Absolute_frame_maps_a_line_rect_to_itself(double left, double width)
    {
        var frame = KaraokeSpace.Frame(300, 80);
        var line = B(left, 4, width, 30);
        var fill = KaraokeSpace.ToFill(line, frame, frame);
        Assert.Equal(line, fill);
        Assert.True(KaraokeSpace.EdgeMatches(fill.X, line.X));
        Assert.True(KaraokeSpace.EdgeMatches(fill.Right, line.Right));
    }

    [Fact]
    public void Wrapped_lines_each_keep_their_own_left_edge()
    {
        var frame = KaraokeSpace.Frame(300, 80);
        var lines = new[] { B(30, 0, 240, 30), B(95, 34, 110, 30) };    // deux lignes centrées de largeurs différentes
        foreach (var l in lines) Assert.Equal(l, KaraokeSpace.ToFill(l, frame, frame));
    }

    [Fact]
    public void Old_mapping_relative_to_the_ink_box_started_late_by_the_left_margin()
    {
        // Ce que faisait le pinceau relatif à la boîte englobante : viewbox = bloc, viewport = boîte des lettres (à 57,5 du bord) ; une zone calculée dans le repère du bloc
        // était donc peinte décalée de la marge gauche (c'est le retard vu sur la capture). La même fonction donne la correction qu'il aurait fallu.
        var block = B(0, 0, 300, 40);
        var ink = B(57.5, 4, 185, 30);
        var painted = KaraokeSpace.ToFill(B(57.5, 4, 185, 30), block, ink);      // où l'identité aurait dû tomber
        Assert.Equal(0, painted.X, 6);                                           // il aurait fallu commencer à 0 dans le contenu du pinceau
        var naive = B(57.5, 4, 185, 30);                                         // zone laissée dans le repère du bloc
        // peinte par le pinceau relatif : x_bloc = ink.X + naive.X * ink.Width / block.Width
        var paintedAt = ink.X + naive.X * ink.Width / block.Width;
        Assert.False(KaraokeSpace.EdgeMatches(paintedAt, naive.X));              // décalée de plus de 1 DIP : le défaut
    }

    [Fact]
    public void Edge_tolerance_is_one_dip()
    {
        Assert.True(KaraokeSpace.EdgeMatches(10, 10.99));
        Assert.False(KaraokeSpace.EdgeMatches(10, 11.2));
        Assert.True(KaraokeSpace.EdgeMatches(10, 11.4, 1.5));
    }

    [Fact]
    public void Union_spans_all_boxes_and_is_null_when_empty()
    {
        Assert.Null(KaraokeSpace.Union(Array.Empty<KaraokeSpace.Box>()));
        Assert.Equal(B(30, 0, 240, 64), KaraokeSpace.Union(new[] { B(30, 0, 240, 30), B(95, 34, 110, 30) }));
    }
}
