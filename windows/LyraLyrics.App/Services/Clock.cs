using System.Diagnostics;

namespace LyraLyrics.App.Services;

/// <summary>Horloge monotone en secondes (instants des relevés, de la porte et du moteur de synchro).</summary>
internal static class Clock
{
    public static double Seconds() => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;

    public static async Task Sleep(double seconds, CancellationToken ct)
    {
        try { await Task.Delay(TimeSpan.FromSeconds(Math.Max(0, seconds)), ct).ConfigureAwait(false); }
        catch (OperationCanceledException) { }
    }
}
