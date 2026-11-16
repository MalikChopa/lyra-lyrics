using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>Pochette décodée : image nette (pochette de gauche), image floutée 160 px (fond), luminance maximale du flou (réglage du voile).</summary>
internal sealed class SceneArt
{
    public required BitmapSource Panel { get; init; }
    public required BitmapSource Blurred { get; init; }
    public required double Luminance { get; init; }

    public static SceneArt Decode(byte[] bytes)
    {
        using var ms = new MemoryStream(bytes);
        var bmp = new BitmapImage();
        bmp.BeginInit();
        bmp.CacheOption = BitmapCacheOption.OnLoad;
        bmp.DecodePixelWidth = 1024;                 // assez pour une pochette à 35 % de l'écran en 4K ; jamais la taille d'origine (mémoire)
        bmp.StreamSource = ms;
        bmp.EndInit();
        bmp.Freeze();
        var conv = new FormatConvertedBitmap(bmp, PixelFormats.Bgra32, null, 0);
        int w = conv.PixelWidth, h = conv.PixelHeight;
        var px = new byte[w * h * 4];
        conv.CopyPixels(px, w * 4, 0);
        for (var i = 0; i < w * h; i++) (px[i * 4], px[i * 4 + 2]) = (px[i * 4 + 2], px[i * 4]);       // BGRA -> RGBA (ordre du Core)
        var small = SceneArtworkMath.AspectFillSquare(px, w, h);
        var blurred = SceneArtworkMath.Blur(small);
        var lum = SceneArtworkMath.MaxLuminance(blurred, SceneArtworkMath.Side, SceneArtworkMath.Side);
        for (var i = 0; i < SceneArtworkMath.Side * SceneArtworkMath.Side; i++) (blurred[i * 4], blurred[i * 4 + 2]) = (blurred[i * 4 + 2], blurred[i * 4]);   // retour en BGRA
        var wb = new WriteableBitmap(SceneArtworkMath.Side, SceneArtworkMath.Side, 96, 96, PixelFormats.Bgra32, null);
        wb.WritePixels(new Int32Rect(0, 0, SceneArtworkMath.Side, SceneArtworkMath.Side), blurred, SceneArtworkMath.Side * 4, 0);
        wb.Freeze();
        return new SceneArt { Panel = bmp, Blurred = wb, Luminance = lum };
    }
}
