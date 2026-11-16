namespace LyraLyrics.Core.Tests;

using A = RequestGate.Admission;
using O = RequestGate.Outcome;
using V = RequestGate.Verdict;

public class RequestGateTests
{
    private static RequestGate Gate() => new(random: () => 0.5);

    [Fact]
    public void OneAtATime()
    {
        var g = Gate();
        Assert.Equal(new A.Proceed(8), g.Admit(0));
        g.RequestStarted(0);
        Assert.Equal(new A.Busy(), g.Admit(1));
        Assert.Equal(new V.Proceed(), g.RequestFinished(1, new O.Success()));
        Assert.Equal(new A.Proceed(8), g.Admit(1.3));
    }

    [Fact]
    public void SpacingAtLeast300ms()
    {
        var g = Gate();
        g.RequestStarted(10); g.RequestFinished(10.5, new O.NotFound());
        Assert.Equal(new A.Wait(0.2), g.Admit(10.6));
        Assert.Equal(new A.Proceed(8), g.Admit(10.8));
    }

    [Fact]
    public void Budget_ConsumedBySlownessOnly()
    {
        var g = Gate();
        g.BeginTitle();
        g.RequestStarted(0); g.RequestFinished(7, new O.NotFound());
        Assert.Equal(new A.Proceed(8), g.Admit(7.3));
        g.RequestStarted(7.3); g.RequestFinished(14.3, new O.Success());
        Assert.Equal(new A.Proceed(1), g.Admit(14.6));
        g.RequestStarted(14.6); g.RequestFinished(15.6, new O.BudgetCut());
        Assert.Equal(new A.BudgetExhausted(), g.Admit(15.9));
        Assert.Equal(0, g.BreakerTrips);
        g.BeginTitle();
        Assert.Equal(new A.Proceed(8), g.Admit(16.2));
        g.RequestStarted(16.2); g.RequestFinished(24.2, new O.Timeout());
        Assert.Equal(0, g.BudgetUsed);
    }

    [Fact]
    public void RateLimited_Seconds_ClosesGate_OneRetry_BudgetSuspended()
    {
        var g = Gate();
        g.BeginTitle();
        g.RequestStarted(100);
        Assert.Equal(new V.Retry(3.5), g.RequestFinished(107, new O.RateLimited(3)));
        Assert.Equal(0, g.BudgetUsed);
        Assert.Equal(new A.Closed(110.5, RequestGate.ClosedReason.RateLimited), g.Admit(108));
        Assert.Equal(new A.Proceed(8), g.Admit(110.5));
        g.RequestStarted(110.5);
        Assert.Equal(new V.GiveUp(RequestGate.GiveUpReason.RateLimitedAgain), g.RequestFinished(111, new O.RateLimited(2)));
        Assert.Equal(new A.Closed(113.5, RequestGate.ClosedReason.RateLimited), g.Admit(112));
        Assert.Equal(2, g.BreakerTrips);
    }

    [Fact]
    public void RateLimited_NoHeader_30sPlusJitter()
    {
        var g = Gate();
        g.RequestStarted(0);
        Assert.Equal(new V.Retry(30.5), g.RequestFinished(1, new O.RateLimited(null)));
        Assert.Equal(31.5, g.ClosedUntil);
    }

    [Fact]
    public void RetryAfterParsing()
    {
        var now = DateTimeOffset.FromUnixTimeSeconds(1_445_412_470);   // 2015-10-21 07:27:50 GMT
        Assert.Equal(10, RequestGate.ParseRetryAfter("Wed, 21 Oct 2015 07:28:00 GMT", now));
        Assert.Equal(10, RequestGate.ParseRetryAfter("Wednesday, 21-Oct-15 07:28:00 GMT", now));
        Assert.Equal(10, RequestGate.ParseRetryAfter("Wed Oct 21 07:28:00 2015", now));
        Assert.Equal(0, RequestGate.ParseRetryAfter("Wed, 21 Oct 2015 07:00:00 GMT", now));
        Assert.Equal(120, RequestGate.ParseRetryAfter("120", now));
        Assert.Equal(2.5, RequestGate.ParseRetryAfter(" 2.5 ", now));
        Assert.Null(RequestGate.ParseRetryAfter("bientôt", now));
        Assert.Null(RequestGate.ParseRetryAfter(null, now));
    }

    [Fact]
    public void BreakerSeries_10_20_40_60_120_120()
    {
        var g = Gate();
        g.BeginTitle();
        var now = 0.0;
        g.RequestStarted(now); now += 1;
        Assert.Equal(new V.Retry(2.5), g.RequestFinished(now, new O.ServerError(503, null)));
        Assert.Equal(new A.Wait(1.5), g.Admit(now + 1));
        now += 2.5;
        g.RequestStarted(now); now += 1;
        Assert.Equal(new V.GiveUp(RequestGate.GiveUpReason.ServerErrors), g.RequestFinished(now, new O.ServerError(503, null)));
        var pauses = new List<double>();
        if (g.Admit(now) is A.Closed c) { pauses.Add(c.Until - now); Assert.Equal(RequestGate.ClosedReason.Breaker, c.Reason); }
        for (var i = 0; i < 5; i++)
        {
            now = g.ClosedUntil!.Value;
            g.BeginAttempt();
            Assert.Equal(new A.Proceed(8), g.Admit(now));
            g.RequestStarted(now); now += 1;
            Assert.Equal(new V.GiveUp(RequestGate.GiveUpReason.ServerErrors), g.RequestFinished(now, new O.ServerError(502, null)));
            if (g.Admit(now) is A.Closed c2) pauses.Add(c2.Until - now);
        }
        Assert.Equal(new double[] { 10, 20, 40, 60, 120, 120 }, pauses);
    }

    [Fact]
    public void ServerError_RetryAfter_Timeout_TransportFailure()
    {
        var g = Gate();
        g.RequestStarted(0);
        Assert.Equal(new V.Retry(1), g.RequestFinished(1, new O.ServerError(503, 1)));
        var t = Gate();
        t.RequestStarted(0);
        Assert.Equal(new V.Retry(2.5), t.RequestFinished(8, new O.Timeout()));
        t.RequestStarted(10.5);
        Assert.Equal(new V.GiveUp(RequestGate.GiveUpReason.ServerErrors), t.RequestFinished(18.5, new O.TransportFailure()));
        Assert.Equal(28.5, t.ClosedUntil);
    }

    [Fact]
    public void ResetOnSuccess()
    {
        var g = Gate();
        g.RequestStarted(0); g.RequestFinished(1, new O.ServerError(503, null));
        g.RequestStarted(4); g.RequestFinished(5, new O.ServerError(503, null));
        Assert.Equal(1, g.BreakerTrips);
        g.BeginTitle();
        g.RequestStarted(40); g.RequestFinished(41, new O.Success());
        Assert.True(g.BreakerTrips == 0 && g.ClosedUntil is null);
        g.RequestStarted(50);
        Assert.Equal(new V.Retry(2.5), g.RequestFinished(51, new O.ServerError(500, null)));
    }

    [Fact]
    public void RateLimitCountsInBreaker_NextServerErrorJumpsTo20s()
    {
        var g = Gate();
        g.BeginTitle();
        g.RequestStarted(0); g.RequestFinished(1, new O.RateLimited(1));
        var reopen = g.ClosedUntil!.Value;
        g.BeginAttempt();
        g.RequestStarted(reopen); g.RequestFinished(reopen + 1, new O.ServerError(503, null));
        Assert.Equal(reopen + 1 + 20, g.ClosedUntil);
    }

    [Fact]
    public void Offline_AndMaxSixRequestsPerAttempt()
    {
        var g = Gate();
        g.IsOffline = true;
        Assert.Equal(new A.Offline(), g.Admit(0));
        g.IsOffline = false;
        g.BeginTitle();
        for (var i = 0; i < 6; i++)
        {
            Assert.Equal(new A.Proceed(8), g.Admit(i));
            g.RequestStarted(i); g.RequestFinished(i + 0.1, new O.NotFound());
        }
        Assert.Equal(new A.AttemptExhausted(), g.Admit(10));
        g.BeginAttempt();
        Assert.Equal(new A.Proceed(8), g.Admit(10));
    }

    [Fact]
    public void BreakerNeedsSeveralTitles()
    {
        var g = new RequestGate(titlesBeforeBreaker: 3, random: () => 0.5);
        var now = 0.0;
        for (var title = 1; title <= 3; title++)
        {
            g.BeginTitle();
            g.RequestStarted(now); now += 1;
            Assert.Equal(new V.Retry(1), g.RequestFinished(now, new O.ServerError(503, 1)));
            now += 1;
            g.RequestStarted(now); now += 1;
            Assert.Equal(new V.Retry(1), g.RequestFinished(now, new O.ServerError(503, 1)));
            now += 1;
            g.RequestStarted(now); now += 1;
            Assert.Equal(new V.GiveUp(RequestGate.GiveUpReason.ServerErrors), g.RequestFinished(now, new O.ServerError(503, 1)));
            if (title < 3) { Assert.Null(g.ClosedUntil); g.BeginTitle(); Assert.Equal(new A.Proceed(8), g.Admit(now + 1)); }
            else Assert.Equal(now + 10, g.ClosedUntil);
        }
    }

    [Fact]
    public void FailedTitlesResetOnSuccess()
    {
        var g = new RequestGate(titlesBeforeBreaker: 3, random: () => 0.5);
        var now = 0.0;
        for (var k = 0; k < 2; k++)
        {
            g.BeginTitle();
            for (var j = 0; j < 3; j++) { g.RequestStarted(now); now += 1; g.RequestFinished(now, new O.ServerError(503, 1)); now += 1; }
        }
        Assert.Equal(2, g.FailedTitlesInARow);
        g.BeginTitle(); g.RequestStarted(now); now += 1; g.RequestFinished(now, new O.NotFound());
        Assert.True(g.FailedTitlesInARow == 0 && g.ClosedUntil is null);
    }

    [Fact]
    public void NewTitleShortensBreakerPauseTo5s_RateLimitNeverShortened()
    {
        var g = new RequestGate(random: () => 0.5);
        g.BeginTitle();
        g.RequestStarted(0); g.RequestFinished(1, new O.ServerError(503, null));
        g.RequestStarted(4); g.RequestFinished(5, new O.ServerError(503, null));
        Assert.Equal(15.0, g.ClosedUntil);
        g.BeginTitle(now: 6);
        Assert.Equal(11.0, g.ClosedUntil);
        var r = new RequestGate(random: () => 0.5);
        r.BeginTitle();
        r.RequestStarted(0); r.RequestFinished(1, new O.RateLimited(60));
        var until = r.ClosedUntil;
        r.BeginTitle(now: 2);
        Assert.Equal(until, r.ClosedUntil);
    }

    [Fact]
    public void ServerError_WithFallback_NoWaitNoRetryCount()
    {
        var g = Gate();
        g.BeginTitle();
        g.RequestStarted(0);
        Assert.Equal(new V.Proceed(), g.RequestFinished(1, new O.ServerError(503, 5), fallbackAvailable: true));
        Assert.Equal(0, g.ServerRetries);
        Assert.Equal(new A.Wait(0.3), g.Admit(1));
    }
}
