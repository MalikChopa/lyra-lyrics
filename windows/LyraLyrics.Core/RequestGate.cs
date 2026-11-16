using System.Globalization;

namespace LyraLyrics.Core;

/// <summary>
/// Porte des requêtes LRCLIB (port de RequestGate.swift, valeurs de la 1.0.1). Machine à états pure (horloge injectée en secondes) :
/// une requête à la fois ; ≥ 300 ms entre deux ; au plus 6 requêtes par tentative ; 8 s par requête ; budget de 15 s par titre pour la
/// lenteur sans erreur ; 429 → Retry-After + aléa 0–1 s, sinon 30 s, un seul nouvel essai par tentative ; 5xx/délai : passage immédiat
/// à une autre voie si elle existe, sinon nouvel essai après Retry-After (sinon 2 s + aléa), puis disjoncteur [10, 20, 40, 60, 120] s.
/// </summary>
public sealed class RequestGate
{
    public const double MinSpacingDefault = 0.3;
    public const double PerRequestTimeout = 8.0;
    public const double TitleBudget = 15.0;
    public const int MaxRequestsPerAttempt = 6;
    public const int MaxServerAttempts = 3;
    public const double HalfOpenAfter = 5.0;
    public const double DefaultRateLimitWait = 30.0;
    public const double DefaultServerRetryWait = 2.0;
    public static readonly double[] BreakerPauses = { 10, 20, 40, 60, 120 };
    /// <summary>Plafond d'un Retry-After (W2, identique au Mac) : 300 s. Le serveur reste respecté (bien au-delà du disjoncteur, 120 s au plus),
    /// mais un Retry-After de 86400 ou une date lointaine ne ferme plus la porte de toute l'app pour des heures.</summary>
    public const double MaxRetryAfter = 300.0;
    private static double CapRetryAfter(double seconds) => Math.Min(Math.Max(0, seconds), MaxRetryAfter);

    public enum ClosedReason { RateLimited, Breaker }
    public enum GiveUpReason { RateLimitedAgain, ServerErrors }

    public abstract record Admission
    {
        public sealed record Proceed(double Timeout) : Admission;
        public sealed record Wait(double Seconds) : Admission;
        public sealed record Closed(double Until, ClosedReason Reason) : Admission;
        public sealed record Offline : Admission;
        public sealed record Busy : Admission;
        public sealed record BudgetExhausted : Admission;
        public sealed record AttemptExhausted : Admission;
    }

    public abstract record Outcome
    {
        public sealed record Success : Outcome;
        public sealed record NotFound : Outcome;
        public sealed record BudgetCut : Outcome;
        public sealed record Cancelled : Outcome;
        public sealed record RateLimited(double? RetryAfter) : Outcome;
        public sealed record ServerError(int Status, double? RetryAfter) : Outcome;
        public sealed record Timeout : Outcome;
        public sealed record TransportFailure : Outcome;
    }

    public abstract record Verdict
    {
        public sealed record Proceed : Verdict;
        public sealed record Retry(double After) : Verdict;
        public sealed record GiveUp(GiveUpReason Reason) : Verdict;
    }

    private readonly object _lock = new();
    private readonly Func<double> _random;
    private double? _requestStart;
    private bool _titleFailureCounted;

    public int TitlesBeforeBreaker { get; }
    public double MinSpacing { get; }
    public int FailedTitlesInARow { get; private set; }
    public bool IsOffline { get; set; }
    public bool InFlight { get; private set; }
    public double NotBefore { get; private set; }
    public double? ClosedUntil { get; private set; }
    public ClosedReason? ClosedReasonValue { get; private set; }
    public int BreakerTrips { get; private set; }
    public int ConsecutiveFailures { get; private set; }
    public int AttemptRequests { get; private set; }
    public double BudgetUsed { get; private set; }
    public int RateLimitRetries { get; private set; }
    public int ServerRetries { get; private set; }
    public int RequestLimit { get; private set; } = MaxRequestsPerAttempt;

    public RequestGate(int titlesBeforeBreaker = 1, double minSpacing = MinSpacingDefault, Func<double>? random = null)
    {
        TitlesBeforeBreaker = Math.Max(1, titlesBeforeBreaker);
        MinSpacing = Math.Max(MinSpacingDefault, minSpacing);
        _random = random ?? (() => Random.Shared.NextDouble());
    }

    public void BeginTitle(double? now = null)
    {
        lock (_lock)
        {
            AttemptRequests = 0; BudgetUsed = 0; RateLimitRetries = 0; ServerRetries = 0; _requestStart = null;
            RequestLimit = MaxRequestsPerAttempt; _titleFailureCounted = false;
            if (now is double n && ClosedReasonValue == ClosedReason.Breaker && ClosedUntil is double until && until - n > HalfOpenAfter)
            {
                ClosedUntil = n + HalfOpenAfter;
                NotBefore = Math.Min(NotBefore, n + HalfOpenAfter);
            }
        }
    }

    public void BeginAttempt(int limit = MaxRequestsPerAttempt)
    {
        lock (_lock) { AttemptRequests = 0; BudgetUsed = 0; _requestStart = null; ServerRetries = 0; RequestLimit = Math.Max(1, limit); }
    }

    public double RemainingBudget { get { lock (_lock) return RemainingBudgetLocked(); } }
    private double RemainingBudgetLocked() => Math.Max(0, Math.Round((TitleBudget - BudgetUsed) * 1000, MidpointRounding.AwayFromZero) / 1000);

    public Admission Admit(double now)
    {
        lock (_lock)
        {
            if (IsOffline) return new Admission.Offline();
            if (InFlight) return new Admission.Busy();
            if (ClosedUntil is double until)
            {
                if (now < until) return new Admission.Closed(until, ClosedReasonValue ?? ClosedReason.Breaker);
                ClosedUntil = null; ClosedReasonValue = null;
            }
            var remaining = RemainingBudgetLocked();
            if (remaining <= 0.001) return new Admission.BudgetExhausted();
            if (AttemptRequests >= RequestLimit) return new Admission.AttemptExhausted();
            if (NotBefore - now > 0.0005) return new Admission.Wait(Math.Round((NotBefore - now) * 1000, MidpointRounding.AwayFromZero) / 1000);
            return new Admission.Proceed(Math.Min(PerRequestTimeout, remaining));
        }
    }

    public void RequestStarted(double now)
    {
        lock (_lock) { InFlight = true; _requestStart = now; AttemptRequests++; }
    }

    public Verdict RequestFinished(double now, Outcome outcome, bool fallbackAvailable = false)
    {
        lock (_lock)
        {
            InFlight = false;
            var duration = Math.Max(0, now - (_requestStart ?? now));
            _requestStart = null;
            NotBefore = now + MinSpacing;
            switch (outcome)
            {
                case Outcome.Success or Outcome.NotFound:
                    BudgetUsed += duration;
                    BreakerTrips = 0; ConsecutiveFailures = 0; FailedTitlesInARow = 0;
                    ClosedUntil = null; ClosedReasonValue = null;
                    return new Verdict.Proceed();
                case Outcome.BudgetCut:
                    BudgetUsed = TitleBudget;
                    return new Verdict.Proceed();
                case Outcome.Cancelled:
                    return new Verdict.Proceed();
                case Outcome.RateLimited rl:
                {
                    ConsecutiveFailures++;
                    BreakerTrips++;
                    RateLimitRetries++;
                    var wait = CapRetryAfter(rl.RetryAfter ?? DefaultRateLimitWait) + _random();
                    ClosedUntil = now + wait; ClosedReasonValue = ClosedReason.RateLimited; NotBefore = now + wait;
                    return RateLimitRetries > 1 ? new Verdict.GiveUp(GiveUpReason.RateLimitedAgain) : new Verdict.Retry(wait);
                }
                case Outcome.ServerError se:
                    return ServerFailure(now, se.RetryAfter, fallbackAvailable);
                default:   // Timeout, TransportFailure
                    return ServerFailure(now, null, fallbackAvailable);
            }
        }
    }

    private Verdict ServerFailure(double now, double? retryAfter, bool fallbackAvailable)
    {
        ConsecutiveFailures++;
        if (fallbackAvailable)
        {
            NotBefore = now + MinSpacing;
            return new Verdict.Proceed();
        }
        ServerRetries++;
        if (TitlesBeforeBreaker > 1)
        {
            if (ServerRetries < MaxServerAttempts)
            {
                var wait = retryAfter is double ra ? CapRetryAfter(ra) : DefaultServerRetryWait + _random();
                NotBefore = now + wait;
                return new Verdict.Retry(wait);
            }
            if (!_titleFailureCounted) { FailedTitlesInARow++; _titleFailureCounted = true; }
            if (FailedTitlesInARow < TitlesBeforeBreaker) return new Verdict.GiveUp(GiveUpReason.ServerErrors);
        }
        else if (BreakerTrips == 0 && ServerRetries == 1)
        {
            var wait = retryAfter is double ra ? CapRetryAfter(ra) : DefaultServerRetryWait + _random();
            NotBefore = now + wait;
            return new Verdict.Retry(wait);
        }
        var pause = BreakerPauses[Math.Min(BreakerTrips, BreakerPauses.Length - 1)];
        BreakerTrips++;
        ClosedUntil = now + pause; ClosedReasonValue = ClosedReason.Breaker; NotBefore = now + pause;
        return new Verdict.GiveUp(GiveUpReason.ServerErrors);
    }

    // ---- Retry-After

    private static readonly string[] HttpDateFormats =
    {
        "ddd, dd MMM yyyy HH:mm:ss 'GMT'", "dddd, dd-MMM-yy HH:mm:ss 'GMT'", "ddd MMM d HH:mm:ss yyyy", "ddd MMM  d HH:mm:ss yyyy",
    };

    private static readonly System.Text.RegularExpressions.Regex NumericSeconds =
        new(@"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$", System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    /// <summary>Retry-After en secondes (entier ou décimal, signe et exposant admis) ou en date HTTP → secondes d'attente bornées à
    /// [0, MaxRetryAfter]. « inf », « nan », hexadécimal et texte illisible → null (W2, identique au Mac).</summary>
    public static double? ParseRetryAfter(string? value, DateTimeOffset now)
    {
        var v = value?.Trim();
        if (string.IsNullOrEmpty(v)) return null;
        if (NumericSeconds.IsMatch(v))
            return double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds) ? CapRetryAfter(seconds) : null;
        if (DateTimeOffset.TryParseExact(v, HttpDateFormats, CultureInfo.GetCultureInfo("en-US"),
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AllowWhiteSpaces, out var date))
            return CapRetryAfter((date - now).TotalSeconds);
        return null;
    }
}
