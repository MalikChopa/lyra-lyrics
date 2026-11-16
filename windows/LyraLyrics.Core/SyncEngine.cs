namespace LyraLyrics.Core;

public sealed record LineWindow(int Index, string? Previous, string Current, string? Next);

/// <summary>
/// Moteur de synchro (port de SyncEngine.swift) : recherche dichotomique de la ligne pour position + avance (0,15 s) + décalage manuel ;
/// avant la 1re ligne : « ♪ ». Décalage manuel borné à ±5 s par pas de 0,1 s.
/// </summary>
public sealed class SyncEngine
{
    public const double Lead = 0.15;
    public const double OffsetMin = -5.0, OffsetMax = 5.0, OffsetStep = 0.1;
    public const string Placeholder = LrcParser.Placeholder;

    public IReadOnlyList<LyricLine> Lines { get; }
    private double _manualOffset;
    public double ManualOffset { get => _manualOffset; set => _manualOffset = SnappedOffset(value); }

    public SyncEngine(IEnumerable<LyricLine>? lines = null, double manualOffset = 0)
    {
        Lines = (lines ?? Array.Empty<LyricLine>()).OrderBy(l => l.Time).ToList();   // OrderBy est stable
        ManualOffset = manualOffset;
    }

    /// <summary>Borne à ±5 s et arrondit au dixième.</summary>
    public static double SnappedOffset(double value)
    {
        var clamped = Math.Min(Math.Max(value, OffsetMin), OffsetMax);
        return Math.Round(clamped * 10, MidpointRounding.AwayFromZero) / 10;
    }

    public double EffectivePosition(double position) => position + Lead + ManualOffset;

    /// <summary>Indice de la dernière ligne dont l'horodatage ≤ position effective ; −1 avant la première.</summary>
    public int IndexAt(double position)
    {
        var target = EffectivePosition(position);
        int low = 0, high = Lines.Count;
        while (low < high)
        {
            var mid = (low + high) / 2;
            if (Lines[mid].Time <= target) low = mid + 1; else high = mid;
        }
        return low - 1;
    }

    /// <summary>Avec hystérésis : après un recalage silencieux on ne revient jamais à une ligne précédente.</summary>
    public int IndexAt(double position, int previous, bool allowBackward)
    {
        var i = IndexAt(position);
        if (!allowBackward && previous >= 0 && i < previous) return previous;
        return i;
    }

    public LineWindow Window(int index)
    {
        string? Text(int i) => i >= 0 && i < Lines.Count ? Lines[i].Text : null;
        if (index < 0) return new LineWindow(-1, null, Placeholder, Text(0));
        var i = Math.Min(index, Lines.Count - 1);
        return new LineWindow(i, Text(i - 1), Text(i) ?? Placeholder, Text(i + 1));
    }

    public LineWindow WindowAtPosition(double position) => Window(IndexAt(position));
}
