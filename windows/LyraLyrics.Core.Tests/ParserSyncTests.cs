namespace LyraLyrics.Core.Tests;

public class LrcParserTests
{
    [Fact]
    public void Formats_Offset_Metadata_MultiTimestamps_EmptyLine_WordTags_Disorder()
    {
        var r = LrcParser.ParseDetailed(Fixtures.Text("lrc/formats.lrc"));
        Assert.Equal(500, r.OffsetMillis);
        Assert.Equal("Artiste fictif", r.Metadata["ar"]);
        Assert.Equal("Formats mêlés", r.Metadata["ti"]);
        Assert.Equal("01:00", r.Metadata["length"]);
        Assert.False(r.Metadata.ContainsKey("offset"));
        (double, string)[] expected =
        {
            (4.623, "Ligne au millième, placée en désordre"), (12.0, "Ligne au centième"), (19.5, "Ligne sans fraction"), (29.6, "Ligne au dixième"),
            (39.5, "Refrain répété deux fois"), (44.5, "♪"), (49.5, "Refrain répété deux fois"), (54.5, "Mot à mot"),
            (62.0, "Deux-points comme séparateur"), (4199.5, "Soixante-dix minutes"),
        };
        Assert.Equal(expected.Length, r.Lines.Count);
        for (var i = 0; i < expected.Length; i++)
        {
            Assert.InRange(Math.Abs(r.Lines[i].Time - expected[i].Item1), 0, 0.0005);
            Assert.Equal(expected[i].Item2, r.Lines[i].Text);
        }
        Assert.DoesNotContain(r.Lines, l => l.Text.Contains("sans horodatage") || l.Text.Contains("Refrain]"));
    }

    [Fact]
    public void BomAndCrlf()
    {
        var lines = LrcParser.Parse(Fixtures.Text("lrc/bom-crlf.lrc"));
        Assert.Equal(new[] { "Avec BOM et CRLF", "Deuxième ligne", "Espaces autour" }, lines.Select(l => l.Text));
        Assert.Equal(new[] { 1.0, 3.0, 5.0 }, lines.Select(l => l.Time));
    }

    [Fact]
    public void Bom_IsStrippedEvenWhenFileReadKeepsIt()
    {
        var raw = "﻿[00:01.00]Un\r\n[00:02.00]Deux";
        Assert.Equal(2, LrcParser.Parse(raw).Count);
    }

    [Fact]
    public void EmptyOrCorrupt_GivesNoLine()
    {
        Assert.Empty(LrcParser.Parse(Fixtures.Text("lrc/empty.lrc")));
        Assert.Empty(LrcParser.Parse(Fixtures.Text("lrc/corrupt.lrc")));
        Assert.Empty(LrcParser.Parse("[12:xx.00] mauvais"));
    }

    [Fact]
    public void NegativeOffset_Milliseconds_NoNegativeTimestamp()
    {
        var r = LrcParser.ParseDetailed("[offset:-250]\n[00:00.100]Début\n[00:01.000]Suite");
        Assert.Equal(-250, r.OffsetMillis);
        Assert.Equal(new[] { 0.35, 1.25 }, r.Lines.Select(l => l.Time));
        Assert.Equal(0, LrcParser.Parse("[offset:+900]\n[00:00.10]Début")[0].Time);
    }

    [Fact]
    public void PlainTextWithoutPlaceholder()
    {
        var lines = LrcParser.Parse("[00:01.00]Un\n[00:02.00]\n[00:03.00]Deux");
        Assert.Equal("Un\nDeux", LrcParser.PlainText(lines));
    }
}

public class SyncTests
{
    private static readonly LyricLine[] Lines = { new(0, "zéro"), new(5, "cinq"), new(10, "dix"), new(20, "vingt") };

    [Fact]
    public void PlayPauseReset()
    {
        var e = new PositionEstimator();
        Assert.Equal(0, e.Estimate(100));
        Assert.Equal(PositionEstimator.Recalibration.Initial, e.Apply(new(10, 100, PlaybackState.Playing)));
        Assert.Equal(15, e.Estimate(105));
        Assert.True(e.IsPlaying);
        e.Apply(new(15.1, 105.1, PlaybackState.Paused));
        Assert.Equal(15.1, e.Estimate(120));
        Assert.False(e.IsPlaying);
        e.Apply(new(15.1, 130, PlaybackState.Playing));
        Assert.Equal(16.1, e.Estimate(131), 9);
        e.Reset();
        Assert.False(e.Primed);
        Assert.Equal(0, e.Estimate(200));
    }

    [Fact]
    public void SeekVersusSilent()
    {
        var e = new PositionEstimator();
        e.Apply(new(10, 100, PlaybackState.Playing));
        Assert.Equal(PositionEstimator.Recalibration.Silent, e.Apply(new(15.6, 105, PlaybackState.Playing)));
        Assert.Equal(15.6, e.Estimate(105));
        Assert.Equal(PositionEstimator.Recalibration.Seek, e.Apply(new(40, 106, PlaybackState.Playing)));
        Assert.Equal(PositionEstimator.Recalibration.Seek, e.Apply(new(40.2, 107, PlaybackState.Playing)));
        Assert.Equal(PositionEstimator.Recalibration.Seek, e.LastRecalibration);
    }

    [Fact]
    public void LeadBinarySearchAndBounds()
    {
        var s = new SyncEngine(Lines);
        Assert.Equal(1, s.IndexAt(4.85));       // 4,85 + 0,15 = 5
        Assert.Equal(0, s.IndexAt(4.84));
        Assert.Equal(-1, s.IndexAt(-1));
        var before = s.Window(-1);
        Assert.Equal("♪", before.Current); Assert.Null(before.Previous); Assert.Equal("zéro", before.Next);
        Assert.Equal(3, s.IndexAt(999));
        var after = s.WindowAtPosition(999);
        Assert.Equal("vingt", after.Current); Assert.Null(after.Next); Assert.Equal("dix", after.Previous);
        Assert.Equal(new LineWindow(2, "cinq", "dix", "vingt"), s.WindowAtPosition(10));
        Assert.Equal("♪", new SyncEngine().Window(3).Current);
    }

    [Fact]
    public void Hysteresis()
    {
        var s = new SyncEngine(Lines);
        Assert.Equal(1, s.IndexAt(4.7, 1, false));
        Assert.Equal(0, s.IndexAt(4.7, 1, true));
        Assert.Equal(2, s.IndexAt(12, 1, false));
    }

    [Fact]
    public void ManualOffset_Snapped_Clamped_Applied()
    {
        var s = new SyncEngine(Lines, 0.26);
        Assert.Equal(0.3, s.ManualOffset);
        s.ManualOffset = 7; Assert.Equal(5, s.ManualOffset);
        s.ManualOffset = -9; Assert.Equal(-5, s.ManualOffset);
        s.ManualOffset = 1.0; Assert.Equal(1, s.IndexAt(3.85));
        s.ManualOffset = -1.0; Assert.Equal(0, s.IndexAt(5.84));
        Assert.Equal(0, SyncEngine.SnappedOffset(-0.04));
    }

    [Fact]
    public void EstimatorToEngine_LineChangeInstants()
    {
        var e = new PositionEstimator();
        e.Apply(new(0, 1000, PlaybackState.Playing));
        var s = new SyncEngine(Lines);
        Assert.Equal(1, s.IndexAt(e.Estimate(1009.849)));
        Assert.Equal(2, s.IndexAt(e.Estimate(1009.851)));
    }
}

public class SmtcClockTests
{
    private static readonly DateTimeOffset T0 = new(2026, 10, 27, 20, 0, 0, TimeSpan.Zero);

    [Fact]
    public void PlayingExtrapolatesFromLastUpdatedTime()
        => Assert.Equal(12.5, SmtcClock.Extrapolate(10, T0, T0.AddSeconds(2.5), 1.0, true, 0, 200), 9);

    [Fact]
    public void PausedKeepsPosition()
        => Assert.Equal(10, SmtcClock.Extrapolate(10, T0, T0.AddSeconds(30), 1.0, false, 0, 200));

    [Fact]
    public void RespectsPlaybackRate()
        => Assert.Equal(15, SmtcClock.Extrapolate(10, T0, T0.AddSeconds(2.5), 2.0, true, 0, 200), 9);

    [Fact]
    public void ClampedToEndTime()
        => Assert.Equal(200, SmtcClock.Extrapolate(190, T0, T0.AddSeconds(60), 1.0, true, 0, 200));

    [Fact]
    public void UnknownEndIsIgnored()
        => Assert.Equal(70, SmtcClock.Extrapolate(10, T0, T0.AddSeconds(60), 1.0, true, 0, 0), 9);

    [Fact]
    public void FutureOrDefaultLastUpdatedDoesNotMove()
    {
        Assert.Equal(10, SmtcClock.Extrapolate(10, T0.AddSeconds(5), T0, 1.0, true, 0, 200));
        Assert.Equal(10, SmtcClock.Extrapolate(10, default, T0, 1.0, true, 0, 200));
    }

    [Fact]
    public void ZeroOrInvalidRateFallsBackToOne()
        => Assert.Equal(12, SmtcClock.Extrapolate(10, T0, T0.AddSeconds(2), 0.0, true, 0, 200), 9);

    [Fact]
    public void NeverBelowStart()
        => Assert.Equal(5, SmtcClock.Extrapolate(1, T0, T0, 1.0, true, 5, 200));

    [Fact]
    public void DurationAndPlausibility()
    {
        Assert.Equal(200, SmtcClock.Duration(0, 200));
        Assert.Null(SmtcClock.Duration(0, 0));
        Assert.True(SmtcClock.IsPlausible(201, 200));
        Assert.False(SmtcClock.IsPlausible(300, 200));
        Assert.True(SmtcClock.IsPlausible(300, null));
    }

    [Fact]
    public void SequenceOfSnapshots_FeedsEstimator_SeekDetected()
    {
        // Séquence simulée : instantané à t=0 (pos 10), instantané à t=5 (pos 15,2 : silencieux), saut à t=8 (pos 90 : seek).
        var est = new PositionEstimator();
        double Mono(double s) => 1000 + s;
        est.Apply(new(SmtcClock.Extrapolate(10, T0, T0, 1, true, 0, 200), Mono(0), PlaybackState.Playing));
        var k1 = est.Apply(new(SmtcClock.Extrapolate(15.2, T0.AddSeconds(5), T0.AddSeconds(5), 1, true, 0, 200), Mono(5), PlaybackState.Playing));
        var k2 = est.Apply(new(SmtcClock.Extrapolate(90, T0.AddSeconds(8), T0.AddSeconds(8.1), 1, true, 0, 200), Mono(8.1), PlaybackState.Playing));
        Assert.Equal(PositionEstimator.Recalibration.Silent, k1);
        Assert.Equal(PositionEstimator.Recalibration.Seek, k2);
    }

    [Theory]
    [InlineData("Spotify.exe", true)]
    [InlineData("SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify", true)]
    [InlineData("chrome.exe", false)]
    [InlineData("MSEdge", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void SpotifySessionSelection(string? aumid, bool expected) => Assert.Equal(expected, SmtcClock.IsSpotifySession(aumid));

    [Fact]
    public void AdvertisementHeuristic()
    {
        Assert.True(SmtcClock.LooksLikeAdvertisement("Advertisement", "Spotify"));
        Assert.False(SmtcClock.LooksLikeAdvertisement("Phares sur la mer", "Artiste fictif"));
    }
}
