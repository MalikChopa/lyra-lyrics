using System.Globalization;

namespace LyraLyrics.Core;

/// <summary>Ce que le déroulé d'un titre rapporte pendant qu'il tourne.</summary>
public abstract record LookupEvent
{
    public sealed record Searching : LookupEvent;
    /// <summary>Fin d'une attente (429, disjoncteur, reprise espacée) : nouvel essai pour le titre courant.</summary>
    public sealed record Retrying : LookupEvent;
    /// <summary>Attente avant un nouvel essai : « Service occupé », nouvel essai dans RetryIn s.</summary>
    public sealed record Busy(double RetryIn, string Reason) : LookupEvent;
    public sealed record Offline : LookupEvent;
}

public abstract record LookupOutcome
{
    public sealed record Found(Lyrics Lyrics) : LookupOutcome;
    /// <summary>Aucune parole. <c>Definitive</c> : toutes les requêtes ont abouti (404 ou liste sans candidat).</summary>
    public sealed record NotFound(string Reason, bool Definitive) : LookupOutcome;
    /// <summary>Erreurs passagères qui durent après toutes les reprises : jamais « indisponible ».</summary>
    public sealed record Stalled(string Reason) : LookupOutcome;
    public sealed record Cancelled : LookupOutcome;
}

public abstract record LookupStep
{
    public sealed record GetById(int Id) : LookupStep;
    public sealed record Get : LookupStep;
    public sealed record Search(SearchQuery Query, string Label) : LookupStep;

    public string Name => this switch { GetById => "get/{id}", Get => "get", Search s => s.Label, _ => "?" };
    public bool IsGet => this is not Search;
}

/// <summary>
/// Déroulé de recherche d'UN titre (port de LookupRunner.swift, 1.0.1), pur : transport, horloge et attente injectés.
/// Ordre : get/{id} (index) si connu, get exact, puis search de plus en plus large. Une erreur du serveur n'aboutit jamais à « indisponible ».
/// </summary>
public sealed class LookupRunner
{
    public sealed class Config
    {
        public double[] Backoff { get; set; } = { 5, 10, 20, 40, 60, 60 };
        public int RetryLimit { get; set; } = 3;
        public double DeferredDefaultWait { get; set; } = RequestGate.DefaultServerRetryWait;
    }

    private readonly LrclibClient _client;
    private readonly RequestGate _gate;
    private readonly Config _config;
    private readonly Func<double> _clock;
    private readonly Func<double, CancellationToken, Task> _sleeper;
    private readonly Action<Dictionary<string, string>> _log;
    private readonly List<TaskCompletionSource> _onlineWaiters = new();
    private readonly object _lock = new();

    public LookupRunner(LrclibClient client, RequestGate gate, Func<double> clock, Func<double, CancellationToken, Task> sleep,
                        Config? config = null, Action<Dictionary<string, string>>? log = null)
    {
        _client = client; _gate = gate; _config = config ?? new Config(); _clock = clock; _sleeper = sleep; _log = log ?? (_ => { });
    }

    public bool IsOffline => _gate.IsOffline;

    /// <summary>Hors connexion : aucune requête ; au retour, la recherche du titre courant reprend.</summary>
    public void SetOnline(bool online)
    {
        List<TaskCompletionSource> waiters;
        lock (_lock)
        {
            _gate.IsOffline = !online;
            if (!online) return;
            waiters = _onlineWaiters.ToList();
            _onlineWaiters.Clear();
        }
        foreach (var w in waiters) w.TrySetResult();
    }

    /// <summary>Requêtes prévues pour un titre, dans l'ordre (sans doublon).</summary>
    public static List<LookupStep> Plan(TrackInfo track)
    {
        var title = TrackMatcher.QueryTitle(track.Title);
        var shortTitle = TrackMatcher.ShortQueryTitle(track.Title);
        var artist = track.Artist.Trim();
        var steps = new List<LookupStep> { new LookupStep.Get() };
        if (artist.Length == 0)
        {
            steps.Add(new LookupStep.Search(new SearchQuery.Combined(title), "search (q)"));
            return steps;
        }
        var primary = TrackMatcher.PrimaryArtist(artist);
        steps.Add(new LookupStep.Search(new SearchQuery.Fields(title, artist), "search"));
        if (primary != artist) steps.Add(new LookupStep.Search(new SearchQuery.Fields(title, primary), "search (1er artiste)"));
        steps.Add(new LookupStep.Search(new SearchQuery.Combined($"{title} {TrackMatcher.WithoutThe(primary)}"), "search (q)"));
        if (shortTitle != title) steps.Add(new LookupStep.Search(new SearchQuery.Fields(shortTitle, primary), "search (titre court)"));
        return steps;
    }

    private sealed record Deferred(LookupStep Step, double ReadyAt);

    private sealed class Collected
    {
        private readonly Dictionary<int, LrclibRecord> _pool = new();
        private readonly Dictionary<int, string> _via = new();
        public int Count => _pool.Count;
        public void Add(IEnumerable<LrclibRecord> records, string via)
        {
            foreach (var r in records) { _pool[r.Id] = r; _via.TryAdd(r.Id, via); }
        }
        public TrackMatcher.Decision Decision(TrackInfo track) =>
            TrackMatcher.Choose(track, _pool.Values.OrderBy(r => r.Id).Select(r => r.Candidate).ToList());
        public Lyrics? LyricsFor(TrackMatcher.Decision d, TrackInfo track)
        {
            if (d.Candidate is null || !_pool.TryGetValue(d.Candidate.Id, out var record)) return null;
            var origin = _via.GetValueOrDefault(record.Id, "get");
            return LrclibClient.LyricsFrom(record, track, origin.StartsWith("get") ? origin : $"{origin}, id {d.Candidate.Id}, score {(int)d.Score}");
        }
    }

    private abstract record StepResult
    {
        public sealed record Records(IReadOnlyList<LrclibRecord> Items) : StepResult;
        public sealed record NotFound : StepResult;
        public sealed record RateLimited(string? RetryAfter) : StepResult;
        public sealed record Server(int Status, string? RetryAfter) : StepResult;
        public sealed record Timeout : StepResult;
        public sealed record Failure(string Text) : StepResult;
        public sealed record Invalid : StepResult;
        public sealed record Cancelled : StepResult;
    }

    /// <summary>Raison de choix sans identifiant LRCLIB (D6) : « id 123, score 17, durée +1 s » devient « score 17, durée +1 s ».</summary>
    internal static string SafeReason(string reason) => System.Text.RegularExpressions.Regex.Replace(reason, @"\bid \d+,?\s*", "").Trim();

    private static string F1(double v) => v.ToString("0.0", CultureInfo.InvariantCulture);

    public async Task<LookupOutcome> RunAsync(TrackInfo track, int? knownId, Action<LookupEvent> report, CancellationToken ct)
    {
        _gate.BeginTitle(_clock());
        var fresh = new List<LookupStep>();
        if (knownId is int kid) fresh.Add(new LookupStep.GetById(kid));
        fresh.AddRange(Plan(track));
        var deferred = new List<Deferred>();
        var col = new Collected();
        var rounds = 0;
        var lastTransient = "service occupé";
        report(new LookupEvent.Searching());

        TrackMatcher.Decision Decision() => col.Decision(track);
        Lyrics? LyricsFor(TrackMatcher.Decision d) => col.LyricsFor(d, track);

        bool IsFinal(TrackMatcher.Decision d, LookupStep step)
        {
            if (d.Candidate is not { } c) return false;
            switch (d.Mode)
            {
                case TrackMatcher.Mode.Instrumental: return true;
                case TrackMatcher.Mode.Synced:
                    return TrackMatcher.GetDurationVerdict(track.Duration, c.Duration) switch
                    {
                        TrackMatcher.DurationVerdict.Far => !step.IsGet,     // écart toléré (5 à 15 s) : accepté après une recherche seulement
                        _ => true,
                    };
                case TrackMatcher.Mode.Plain:
                    return !step.IsGet && TrackMatcher.ArtistMatches(c.Artist, track) && TrackMatcher.TitleKey(c.Title) == TrackMatcher.TitleKey(track.Title);
                default: return false;
            }
        }

        LookupOutcome Conclude()
        {
            var d = Decision();
            if (LyricsFor(d) is { } found)
            {
                _log(new()
                {
                    ["lookup"] = "choix", ["resultat"] = found.IsSynced ? "synced" : (found.Kind == LyricsKind.Plain ? "plain" : "instrumental"),
                    ["choix"] = SafeReason(d.Reason), ["candidats"] = col.Count.ToString(),
                });
                return new LookupOutcome.Found(found);
            }
            return new LookupOutcome.NotFound(col.Count == 0 ? $"aucun candidat ({SafeReason(d.Reason)})" : $"aucun titre compatible ({SafeReason(d.Reason)})", deferred.Count == 0);
        }

        while (!ct.IsCancellationRequested)
        {
            switch (_gate.Admit(_clock()))
            {
                case RequestGate.Admission.Offline:
                    report(new LookupEvent.Offline());
                    _log(new() { ["lookup"] = "hors-connexion" });
                    await WaitForOnlineAsync(ct).ConfigureAwait(false);
                    continue;
                case RequestGate.Admission.Busy:
                    await _sleeper(0.05, ct).ConfigureAwait(false);
                    continue;
                case RequestGate.Admission.Wait w:
                    await _sleeper(w.Seconds, ct).ConfigureAwait(false);
                    continue;
                case RequestGate.Admission.Closed closed:
                    await CountdownAsync(closed.Until, closed.Reason.ToString().ToLowerInvariant(), report, ct).ConfigureAwait(false);
                    if (ct.IsCancellationRequested) return new LookupOutcome.Cancelled();
                    _gate.BeginAttempt(_config.RetryLimit);
                    report(new LookupEvent.Retrying());
                    _log(new() { ["lookup"] = "nouvel-essai", ["raison"] = closed.Reason.ToString() });
                    continue;
                case RequestGate.Admission.BudgetExhausted or RequestGate.Admission.AttemptExhausted:
                {
                    if (fresh.Count == 0 && (deferred.Count == 0 || (LyricsFor(Decision()) is not null && deferred.All(x => x.Step.IsGet)))) return Conclude();
                    if (lastTransient == "service occupé") lastTransient = "lenteur ou requêtes épuisées";
                    rounds++;
                    if (await EndAttemptAsync(rounds, lastTransient, report, ct).ConfigureAwait(false) is { } ended) return ended;
                    continue;
                }
                case RequestGate.Admission.Proceed proceed:
                {
                    LookupStep step;
                    if (fresh.Count > 0) { step = fresh[0]; fresh.RemoveAt(0); }
                    else if (deferred.Count > 0)
                    {
                        if (LyricsFor(Decision()) is not null && deferred.All(x => x.Step.IsGet)) return Conclude();
                        var next = deferred[0]; deferred.RemoveAt(0);
                        var wait = next.ReadyAt - _clock();
                        if (wait > 0) await _sleeper(wait, ct).ConfigureAwait(false);
                        step = next.Step;
                    }
                    else return Conclude();

                    var timeout = proceed.Timeout;
                    var started = _clock();
                    _gate.RequestStarted(started);
                    _log(new() { ["lookup"] = "requete", ["etape"] = step.Name, ["timeout"] = F1(timeout) });
                    var result = await PerformAsync(step, track, timeout, ct).ConfigureAwait(false);
                    switch (result)
                    {
                        case StepResult.Records r:
                        {
                            _gate.RequestFinished(_clock(), r.Items.Count == 0 ? new RequestGate.Outcome.NotFound() : new RequestGate.Outcome.Success());
                            col.Add(r.Items, step.Name);
                            var d = Decision();
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = "200", ["ms"] = Ms(started), ["candidats"] = r.Items.Count.ToString(), ["choix"] = SafeReason(d.Reason) });
                            if (IsFinal(d, step)) return Conclude();
                            break;
                        }
                        case StepResult.NotFound:
                            _gate.RequestFinished(_clock(), new RequestGate.Outcome.NotFound());
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = "404", ["ms"] = Ms(started) });
                            break;
                        case StepResult.RateLimited rl:
                        {
                            var seconds = RequestGate.ParseRetryAfter(rl.RetryAfter, DateTimeOffset.UtcNow);
                            var verdict = _gate.RequestFinished(_clock(), new RequestGate.Outcome.RateLimited(seconds));
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = "429", ["ms"] = Ms(started), ["retryAfter"] = rl.RetryAfter ?? "", ["verdict"] = Describe(verdict) });
                            deferred.Insert(0, new Deferred(step, _clock()));
                            lastTransient = "429 (service limité)";
                            if (verdict is RequestGate.Verdict.GiveUp)
                            {
                                rounds++;
                                if (await EndAttemptAsync(rounds, lastTransient, report, ct).ConfigureAwait(false) is { } ended) return ended;
                            }
                            break;
                        }
                        case StepResult.Server s:
                        {
                            var seconds = RequestGate.ParseRetryAfter(s.RetryAfter, DateTimeOffset.UtcNow);
                            var verdict = _gate.RequestFinished(_clock(), new RequestGate.Outcome.ServerError(s.Status, seconds), fallbackAvailable: fresh.Count > 0);
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = s.Status.ToString(), ["ms"] = Ms(started), ["retryAfter"] = s.RetryAfter ?? "", ["verdict"] = Describe(verdict) });
                            deferred.Add(new Deferred(step, _clock() + (seconds ?? _config.DeferredDefaultWait)));
                            lastTransient = $"erreur {s.Status} du service";
                            if (verdict is RequestGate.Verdict.GiveUp)
                            {
                                rounds++;
                                if (await EndAttemptAsync(rounds, lastTransient, report, ct).ConfigureAwait(false) is { } ended) return ended;
                            }
                            break;
                        }
                        case StepResult.Timeout:
                        {
                            var cut = timeout < RequestGate.PerRequestTimeout - 0.001;
                            var verdict = _gate.RequestFinished(_clock(), cut ? new RequestGate.Outcome.BudgetCut() : new RequestGate.Outcome.Timeout(), fallbackAvailable: fresh.Count > 0 && !cut);
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = cut ? "coupée par le budget" : "délai dépassé", ["ms"] = Ms(started), ["verdict"] = Describe(verdict) });
                            deferred.Add(new Deferred(step, _clock() + _config.DeferredDefaultWait));
                            lastTransient = "délai dépassé";
                            if (verdict is RequestGate.Verdict.GiveUp)
                            {
                                rounds++;
                                if (await EndAttemptAsync(rounds, lastTransient, report, ct).ConfigureAwait(false) is { } ended) return ended;
                            }
                            break;
                        }
                        case StepResult.Failure f:
                        {
                            if (ct.IsCancellationRequested) { _gate.RequestFinished(_clock(), new RequestGate.Outcome.Cancelled()); return new LookupOutcome.Cancelled(); }
                            var verdict = _gate.RequestFinished(_clock(), new RequestGate.Outcome.TransportFailure(), fallbackAvailable: fresh.Count > 0);
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = "panne de transport", ["ms"] = Ms(started), ["erreur"] = f.Text, ["verdict"] = Describe(verdict) });
                            deferred.Add(new Deferred(step, _clock() + _config.DeferredDefaultWait));
                            lastTransient = "panne de transport";
                            if (verdict is RequestGate.Verdict.GiveUp)
                            {
                                rounds++;
                                if (await EndAttemptAsync(rounds, lastTransient, report, ct).ConfigureAwait(false) is { } ended) return ended;
                            }
                            break;
                        }
                        case StepResult.Invalid:
                            // JSON illisible : traité comme une réponse sans résultat (pas une panne passagère).
                            _gate.RequestFinished(_clock(), new RequestGate.Outcome.NotFound());
                            _log(new() { ["lookup"] = "reponse", ["etape"] = step.Name, ["statut"] = "200", ["ms"] = Ms(started), ["resultat"] = "JSON illisible" });
                            break;
                        case StepResult.Cancelled:
                            _gate.RequestFinished(_clock(), new RequestGate.Outcome.Cancelled());
                            return new LookupOutcome.Cancelled();
                    }
                    continue;
                }
            }
        }
        return new LookupOutcome.Cancelled();
    }

    // ---- Détails

    private async Task<StepResult> PerformAsync(LookupStep step, TrackInfo track, double timeout, CancellationToken ct)
    {
        try
        {
            switch (step)
            {
                case LookupStep.GetById g: return new StepResult.Records(new[] { await _client.GetAsync(g.Id, timeout, ct).ConfigureAwait(false) });
                case LookupStep.Get: return new StepResult.Records(new[] { await _client.GetAsync(track, timeout, ct).ConfigureAwait(false) });
                case LookupStep.Search s: return new StepResult.Records(await _client.SearchAsync(s.Query, timeout, ct).ConfigureAwait(false));
                default: return new StepResult.Failure("étape inconnue");
            }
        }
        catch (LrclibException e)
        {
            return e.Kind switch
            {
                LrclibErrorKind.NotFound => new StepResult.NotFound(),
                LrclibErrorKind.RateLimited => new StepResult.RateLimited(e.RetryAfter),
                LrclibErrorKind.ServerError => new StepResult.Server(e.Status, e.RetryAfter),
                LrclibErrorKind.Timeout => new StepResult.Timeout(),
                LrclibErrorKind.InvalidJson => new StepResult.Invalid(),
                LrclibErrorKind.Cancelled => new StepResult.Cancelled(),
                _ => ct.IsCancellationRequested ? new StepResult.Cancelled() : new StepResult.Failure(e.Kind.ToString()),
            };
        }
        catch (OperationCanceledException) { return new StepResult.Cancelled(); }
        catch (Exception e)
        {
            if (ct.IsCancellationRequested) return new StepResult.Cancelled();
            var t = e.GetType().Name;
            return new StepResult.Failure(t.Length > 80 ? t[..80] : t);
        }
    }

    /// <summary>Fin d'une tentative sur une erreur passagère : attente (compte à rebours), puis nouvelle tentative (null). Rend un résultat si le déroulé s'arrête.</summary>
    private async Task<LookupOutcome?> EndAttemptAsync(int rounds, string reason, Action<LookupEvent> report, CancellationToken ct)
    {
        if (rounds > _config.Backoff.Length)
        {
            _log(new() { ["lookup"] = "reprises-epuisees", ["raison"] = reason });
            return new LookupOutcome.Stalled(reason);
        }
        var wait = _config.Backoff[rounds - 1];
        _log(new() { ["lookup"] = "reprise-espacee", ["tentative"] = rounds.ToString(), ["secondes"] = wait.ToString("0", CultureInfo.InvariantCulture) });
        await CountdownAsync(_clock() + wait, "reprise", report, ct).ConfigureAwait(false);
        if (ct.IsCancellationRequested) return new LookupOutcome.Cancelled();
        _gate.BeginAttempt(_config.RetryLimit);
        report(new LookupEvent.Retrying());
        return null;
    }

    private async Task CountdownAsync(double until, string reason, Action<LookupEvent> report, CancellationToken ct)
    {
        _log(new() { ["lookup"] = "porte-fermee", ["raison"] = reason, ["secondes"] = F1(until - _clock()) });
        while (!ct.IsCancellationRequested)
        {
            var remaining = until - _clock();
            if (remaining <= 0.0005) return;
            report(new LookupEvent.Busy(remaining, reason));
            await _sleeper(Math.Min(1, remaining), ct).ConfigureAwait(false);
        }
    }

    private async Task WaitForOnlineAsync(CancellationToken ct)
    {
        TaskCompletionSource tcs;
        lock (_lock)
        {
            if (!_gate.IsOffline) return;
            tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            _onlineWaiters.Add(tcs);
        }
        using var reg = ct.Register(() => tcs.TrySetResult());
        await tcs.Task.ConfigureAwait(false);
    }

    private string Ms(double started) => ((long)Math.Round((_clock() - started) * 1000, MidpointRounding.AwayFromZero)).ToString();

    private static string Describe(RequestGate.Verdict v) => v switch
    {
        RequestGate.Verdict.Proceed => "continuer",
        RequestGate.Verdict.Retry r => $"nouvel essai dans {F1(r.After)} s",
        RequestGate.Verdict.GiveUp g => $"abandon ({g.Reason})",
        _ => "?",
    };
}
