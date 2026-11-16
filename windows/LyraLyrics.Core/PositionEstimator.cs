namespace LyraLyrics.Core;

/// <summary>
/// Estimateur de position (port de PositionEstimator.swift) : (p0, t0, état) ; estimate(now) = p0 + (now − t0) en lecture, p0 figé en pause.
/// Écart &gt; 0,75 s : recalage franc (seek) ; sinon recalage silencieux.
/// </summary>
public sealed class PositionEstimator
{
    public const double SeekThreshold = 0.75;
    public enum Recalibration { Initial, Seek, Silent }

    public double P0 { get; private set; }
    public double T0 { get; private set; }
    public PlaybackState State { get; private set; } = PlaybackState.Stopped;
    public bool Primed { get; private set; }
    public Recalibration LastRecalibration { get; private set; } = Recalibration.Initial;

    public bool IsPlaying => Primed && State == PlaybackState.Playing;

    public double Estimate(double now)
    {
        if (!Primed) return 0;
        return State == PlaybackState.Playing ? Math.Max(0, P0 + (now - T0)) : P0;
    }

    public Recalibration Apply(PlaybackReading reading)
    {
        Recalibration kind;
        if (!Primed) kind = Recalibration.Initial;
        else
        {
            var predicted = Estimate(reading.At);
            kind = Math.Abs(reading.Position - predicted) > SeekThreshold ? Recalibration.Seek : Recalibration.Silent;
        }
        P0 = Math.Max(0, reading.Position);
        T0 = reading.At;
        State = reading.State;
        Primed = true;
        LastRecalibration = kind;
        return kind;
    }

    public void Reset() { P0 = 0; T0 = 0; State = PlaybackState.Stopped; Primed = false; LastRecalibration = Recalibration.Initial; }
}
