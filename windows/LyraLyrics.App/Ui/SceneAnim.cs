using System.Windows;
using System.Windows.Media.Animation;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>Animations de la Scène : même courbe que le Mac (easeInEaseOut = Bézier 0,42 · 0 · 0,58 · 1, constantes de <see cref="SceneMotion"/>).</summary>
internal static class SceneAnim
{
    public static KeySpline Spline() => new(SceneMotion.EaseX1, SceneMotion.EaseY1, SceneMotion.EaseX2, SceneMotion.EaseY2);

    /// <summary>Vers <paramref name="to"/> depuis la valeur courante (reprise sans à-coup d'une animation en cours).</summary>
    public static DoubleAnimationUsingKeyFrames To(double to, double seconds, double delay = 0)
    {
        var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(seconds), BeginTime = TimeSpan.FromSeconds(delay), FillBehavior = FillBehavior.HoldEnd };
        a.KeyFrames.Add(new SplineDoubleKeyFrame(to, KeyTime.FromPercent(1), Spline()));
        return a;
    }

    /// <summary>
    /// Aller-retour infini de <paramref name="from"/> à <paramref name="to"/> (demi-période <paramref name="leg"/>), à 30 images par seconde
    /// (mouvement très lent : la moitié des images suffit et coûte moitié moins). Horloge contrôlable : on peut la mettre en pause.
    /// </summary>
    public static AnimationClock PingPong(double from, double to, double leg)
    {
        var a = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromSeconds(leg), AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever };
        a.KeyFrames.Add(new DiscreteDoubleKeyFrame(from, KeyTime.FromPercent(0)));
        a.KeyFrames.Add(new SplineDoubleKeyFrame(to, KeyTime.FromPercent(1), Spline()));
        Timeline.SetDesiredFrameRate(a, 30);
        return (AnimationClock)a.CreateClock(true);
    }

    /// <summary>Animation plus simple : valeur → valeur en <paramref name="seconds"/> (fondus).</summary>
    public static DoubleAnimation Fade(double to, double seconds, double? from = null)
    {
        var a = new DoubleAnimation(to, TimeSpan.FromSeconds(seconds)) { EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut } };
        if (from is { } f) a.From = f;
        return a;
    }
}
