using System.Globalization;
using System.Text;
using System.Text.Json;
using Xunit.Abstractions;

namespace LyraLyrics.Core.Tests;

/// <summary>
/// W2 : fixtures PARTAGÉES avec le cœur Swift (<c>Tests/LyricsCoreTests/ParityFixtureTests.swift</c>). Les deux suites lisent les mêmes
/// fichiers de <c>Fixtures/</c> et doivent donner les mêmes résultats.
/// </summary>
public class ParityFixtureTests
{
    private readonly ITestOutputHelper _out;
    public ParityFixtureTests(ITestOutputHelper o) { _out = o; }

    private static bool Close(double a, double b, double eps = 1e-9) => Math.Abs(a - b) < eps;
    private static double? Num(JsonElement e) => e.ValueKind == JsonValueKind.Number ? e.GetDouble() : null;
    private static bool EqualsIgnoreCase(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);

    [Fact]
    public void Normalize_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/normalize.json");
        var root = doc.RootElement;
        var failures = new List<string>();
        var total = 0;
        void CheckStr(string fn, Func<string, string> run)
        {
            foreach (var row in root.GetProperty(fn).EnumerateArray())
            {
                total++;
                var input = row[0].GetString()!; var expected = row[1].GetString()!;
                var got = run(input);
                if (got != expected) failures.Add($"{fn}(« {input} ») → « {got} », attendu « {expected} »");
            }
        }
        CheckStr("normalizeTitle", TrackMatcher.NormalizeTitle);
        CheckStr("titleKey", TrackMatcher.TitleKey);
        CheckStr("queryTitle", TrackMatcher.QueryTitle);
        CheckStr("shortQueryTitle", TrackMatcher.ShortQueryTitle);
        CheckStr("normalizeArtist", TrackMatcher.NormalizeArtist);
        CheckStr("primaryArtist", TrackMatcher.PrimaryArtist);
        CheckStr("withoutThe", TrackMatcher.WithoutThe);
        foreach (var row in root.GetProperty("artistTokens").EnumerateArray())
        {
            total++;
            var input = row[0].GetString()!;
            var expected = row[1].EnumerateArray().Select(x => x.GetString()!).ToList();
            var got = TrackMatcher.ArtistTokens(input).OrderBy(x => x, StringComparer.Ordinal).ToList();
            if (!got.SequenceEqual(expected)) failures.Add($"artistTokens(« {input} ») → [{string.Join(", ", got)}], attendu [{string.Join(", ", expected)}]");
        }
        foreach (var row in root.GetProperty("looksLikeVideoTitle").EnumerateArray())
        {
            total++;
            var input = row[0].GetString()!; var expected = row[1].GetBoolean();
            if (TrackMatcher.LooksLikeVideoTitle(input) != expected) failures.Add($"looksLikeVideoTitle(« {input} ») ≠ {expected}");
        }
        _out.WriteLine($"PARITE normalize.json cas={total}");
        foreach (var f in failures) _out.WriteLine("ÉCHEC : " + f);
        Assert.True(total >= 500, $"total={total}");
        Assert.Empty(failures);
    }

    [Fact]
    public void RetryAfter_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/retry-after.json");
        var now = DateTimeOffset.FromUnixTimeSeconds((long)doc.RootElement.GetProperty("nowEpoch").GetDouble());
        Assert.Equal(RequestGate.MaxRetryAfter, doc.RootElement.GetProperty("maxRetryAfter").GetDouble());
        var failures = new List<string>();
        var count = 0;
        foreach (var row in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            count++;
            var input = row[0].ValueKind == JsonValueKind.Null ? null : row[0].GetString();
            var expected = Num(row[1]);
            var got = RequestGate.ParseRetryAfter(input, now);
            var ok = (got is null && expected is null) || (got is double g && expected is double e && Close(g, e));
            if (!ok) failures.Add($"« {input ?? "null"} » → {got?.ToString(CultureInfo.InvariantCulture) ?? "null"}, attendu {expected?.ToString(CultureInfo.InvariantCulture) ?? "null"}");
        }
        _out.WriteLine($"PARITE retry-after.json cas={count}");
        foreach (var f in failures) _out.WriteLine("ÉCHEC : " + f);
        Assert.Empty(failures);
    }

    [Fact]
    public void Lrc_SharedFixture()
    {
        using var doc = Fixtures.Json("lrc/parse-cases.json");
        var failures = new List<string>();
        var count = 0;
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            count++;
            var name = c.GetProperty("name").GetString()!;
            var r = LrcParser.ParseDetailed(c.GetProperty("text").GetString()!);
            var lines = c.GetProperty("lines").EnumerateArray().Select(l => (T: l[0].GetDouble(), X: l[1].GetString()!)).ToList();
            var same = lines.Count == r.Lines.Count && lines.Zip(r.Lines).All(p => Close(p.First.T, p.Second.Time) && p.First.X == p.Second.Text);
            if (!same) failures.Add($"{name} : lignes {string.Join(" ; ", r.Lines.Select(l => $"{l.Time}|{l.Text}"))}");
            if (r.OffsetMillis != c.GetProperty("offsetMillis").GetInt32()) failures.Add($"{name} : offset {r.OffsetMillis}");
            var meta = c.GetProperty("metadata").EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetString()!);
            if (meta.Count != r.Metadata.Count || meta.Any(kv => !r.Metadata.TryGetValue(kv.Key, out var v) || v != kv.Value)) failures.Add($"{name} : métadonnées");
        }
        _out.WriteLine($"PARITE lrc/parse-cases.json cas={count}");
        foreach (var f in failures) _out.WriteLine("ÉCHEC : " + f);
        Assert.Empty(failures);
    }

    // ---- Porte de requêtes

    [Fact]
    public void Gate_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/gate.json");
        var random = doc.RootElement.GetProperty("random").GetDouble();
        var failures = new List<string>();
        int scenarios = 0, checks = 0;
        foreach (var sc in doc.RootElement.GetProperty("scenarios").EnumerateArray())
        {
            scenarios++;
            var name = sc.GetProperty("name").GetString()!;
            var cfg = sc.GetProperty("gate");
            var gate = new RequestGate(cfg.TryGetProperty("titlesBeforeBreaker", out var tb) ? tb.GetInt32() : 1,
                                       cfg.TryGetProperty("minSpacing", out var ms) ? ms.GetDouble() : RequestGate.MinSpacingDefault, () => random);
            var i = -1;
            foreach (var step in sc.GetProperty("steps").EnumerateArray())
            {
                i++;
                var where = $"{name} [étape {i}]";
                var op = step.GetProperty("op").GetString();
                double Now() => step.GetProperty("now").GetDouble();
                switch (op)
                {
                    case "beginTitle": gate.BeginTitle(step.TryGetProperty("now", out var n) ? n.GetDouble() : null); break;
                    case "beginAttempt": gate.BeginAttempt(step.GetProperty("limit").GetInt32()); break;
                    case "offline": gate.IsOffline = step.GetProperty("value").GetBoolean(); break;
                    case "start": gate.RequestStarted(Now()); break;
                    case "admit":
                    {
                        checks++;
                        var e = step.GetProperty("expect");
                        var got = gate.Admit(Now());
                        if (!AdmissionMatches(got, e)) failures.Add($"{where} : admission {got}, attendu {e}");
                        break;
                    }
                    case "finish":
                    {
                        checks++;
                        var e = step.GetProperty("expect");
                        var o = step.GetProperty("outcome");
                        double? ra = o.TryGetProperty("retryAfter", out var r) ? Num(r) : null;
                        RequestGate.Outcome outcome = o.GetProperty("kind").GetString() switch
                        {
                            "success" => new RequestGate.Outcome.Success(),
                            "notFound" => new RequestGate.Outcome.NotFound(),
                            "budgetCut" => new RequestGate.Outcome.BudgetCut(),
                            "cancelled" => new RequestGate.Outcome.Cancelled(),
                            "rateLimited" => new RequestGate.Outcome.RateLimited(ra),
                            "serverError" => new RequestGate.Outcome.ServerError(o.TryGetProperty("status", out var st) ? st.GetInt32() : 503, ra),
                            "timeout" => new RequestGate.Outcome.Timeout(),
                            _ => new RequestGate.Outcome.TransportFailure(),
                        };
                        var fallback = step.TryGetProperty("fallback", out var fb) && fb.GetBoolean();
                        var got = gate.RequestFinished(Now(), outcome, fallback);
                        if (!VerdictMatches(got, e)) failures.Add($"{where} : verdict {got}, attendu {e}");
                        break;
                    }
                    case "state":
                    {
                        checks++;
                        foreach (var p in step.GetProperty("expect").EnumerateObject())
                        {
                            var v = p.Value;
                            var ok = p.Name switch
                            {
                                "breakerTrips" => gate.BreakerTrips == v.GetInt32(),
                                "failedTitlesInARow" => gate.FailedTitlesInARow == v.GetInt32(),
                                "consecutiveFailures" => gate.ConsecutiveFailures == v.GetInt32(),
                                "attemptRequests" => gate.AttemptRequests == v.GetInt32(),
                                "closedUntil" => v.ValueKind == JsonValueKind.Null ? gate.ClosedUntil is null : gate.ClosedUntil is double cu && Close(cu, v.GetDouble()),
                                "closedReason" => v.ValueKind == JsonValueKind.Null ? gate.ClosedReasonValue is null : EqualsIgnoreCase(gate.ClosedReasonValue?.ToString(), v.GetString()),
                                _ => false,
                            };
                            if (!ok) failures.Add($"{where} : état {p.Name} ≠ {v}");
                        }
                        break;
                    }
                    default: failures.Add($"{where} : opération inconnue"); break;
                }
            }
        }
        _out.WriteLine($"PARITE gate.json scenarios={scenarios} verifications={checks}");
        foreach (var f in failures) _out.WriteLine("ÉCHEC : " + f);
        Assert.Empty(failures);
        Assert.True(scenarios >= 15);
    }

    private static bool AdmissionMatches(RequestGate.Admission a, JsonElement e)
    {
        var kind = e.GetProperty("kind").GetString();
        return a switch
        {
            RequestGate.Admission.Proceed p => kind == "proceed" && Close(p.Timeout, e.GetProperty("timeout").GetDouble()),
            RequestGate.Admission.Wait w => kind == "wait" && Close(w.Seconds, e.GetProperty("seconds").GetDouble()),
            RequestGate.Admission.Closed c => kind == "closed" && Close(c.Until, e.GetProperty("until").GetDouble()) && EqualsIgnoreCase(c.Reason.ToString(), e.GetProperty("reason").GetString()),
            RequestGate.Admission.Offline => kind == "offline",
            RequestGate.Admission.Busy => kind == "busy",
            RequestGate.Admission.BudgetExhausted => kind == "budgetExhausted",
            RequestGate.Admission.AttemptExhausted => kind == "attemptExhausted",
            _ => false,
        };
    }

    private static bool VerdictMatches(RequestGate.Verdict v, JsonElement e)
    {
        var kind = e.GetProperty("kind").GetString();
        return v switch
        {
            RequestGate.Verdict.Proceed => kind == "proceed",
            RequestGate.Verdict.Retry r => kind == "retry" && Close(r.After, e.GetProperty("after").GetDouble()),
            RequestGate.Verdict.GiveUp g => kind == "giveUp" && EqualsIgnoreCase(g.Reason.ToString(), e.GetProperty("reason").GetString()),
            _ => false,
        };
    }

    // ---- Déroulé d'un titre (LookupRunner)

    private static Dictionary<string, object?> WireRecord(JsonElement r)
    {
        bool B(string n, bool d) => r.TryGetProperty(n, out var v) ? v.GetBoolean() : d;
        return Wire.Record(r.GetProperty("id").GetInt32(), r.GetProperty("title").GetString()!, r.GetProperty("artist").GetString()!,
                           duration: r.TryGetProperty("duration", out var du) ? du.GetDouble() : 200, synced: B("synced", true), plain: B("plain", true), instrumental: B("instrumental", false));
    }

    [Fact]
    public async Task Runner_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/runner.json");
        var failures = new List<string>();
        var count = 0;
        foreach (var sc in doc.RootElement.GetProperty("scenarios").EnumerateArray())
        {
            count++;
            var name = sc.GetProperty("name").GetString()!;
            var e = sc.GetProperty("expect");
            var t = sc.GetProperty("track");
            var track = new TrackInfo(t.GetProperty("title").GetString()!, t.GetProperty("artist").GetString()!,
                                      t.TryGetProperty("album", out var al) ? al.GetString() : null, Num(t.GetProperty("duration")), Player: "fake");
            var replies = sc.GetProperty("replies");
            var clock = new VirtualClock();
            var transport = new ScriptedTransport(clock, (call, nth) =>
            {
                var key = call.Path == "/api/get" ? "get" : call.Path.StartsWith("/api/get/", StringComparison.Ordinal) ? "getById" : "search";
                if (!replies.TryGetProperty(key, out var list) || list.GetArrayLength() == 0) return Wire.NotFound;
                var r = list[Math.Min(nth, list.GetArrayLength()) - 1];
                if (r.TryGetProperty("record", out var rec)) return Wire.Ok(WireRecord(rec));
                if (r.TryGetProperty("list", out var l)) return Wire.List(l.EnumerateArray().Select(WireRecord).ToArray());
                if (r.TryGetProperty("error", out var er)) return Wire.Err(er.GetString() == "timeout" ? LrclibErrorKind.Timeout : LrclibErrorKind.Transport);
                var retry = r.TryGetProperty("retryAfter", out var ra) ? ra.GetString() : null;
                return new ScriptedTransport.Reply.Http(r.GetProperty("status").GetInt32(),
                    retry is null ? null : new Dictionary<string, string> { ["Retry-After"] = retry }, Encoding.UTF8.GetBytes("x"));
            });
            var client = new LrclibClient(transport, "Test/0 (test)", new Uri("http://127.0.0.1:1"));
            var tb = sc.TryGetProperty("titlesBeforeBreaker", out var tbe) ? tbe.GetInt32() : 3;
            var runner = new LookupRunner(client, new RequestGate(tb, random: () => 0.5), () => clock.Now, clock.Sleeper);
            var log = new EventLog();
            int? knownId = sc.TryGetProperty("knownID", out var k) && k.ValueKind == JsonValueKind.Number ? k.GetInt32() : null;
            var outcome = await runner.RunAsync(track, knownId, log.Add, CancellationToken.None);

            string kind; int? id = null; bool? definitive = null;
            switch (outcome)
            {
                case LookupOutcome.Found f:
                    id = f.Lyrics.LrclibId;
                    kind = f.Lyrics.Kind switch { LyricsKind.Synced => "foundSynced", LyricsKind.Instrumental => "foundInstrumental", _ => "foundPlain" };
                    break;
                case LookupOutcome.NotFound nf: kind = "notFound"; definitive = nf.Definitive; break;
                case LookupOutcome.Stalled: kind = "stalled"; break;
                default: kind = "cancelled"; break;
            }
            if (kind != e.GetProperty("outcome").GetString()) failures.Add($"{name} : issue {kind}, attendu {e.GetProperty("outcome")}");
            int? expId = e.TryGetProperty("lrclibID", out var ei) ? ei.GetInt32() : null;
            if (id != expId) failures.Add($"{name} : id {id?.ToString() ?? "null"}, attendu {expId?.ToString() ?? "null"}");
            bool? expDef = e.TryGetProperty("definitive", out var ed) ? ed.GetBoolean() : null;
            if (definitive != expDef) failures.Add($"{name} : définitif {definitive?.ToString() ?? "null"}");
            var expPaths = e.GetProperty("paths").EnumerateArray().Select(x => x.GetString()!).ToList();
            if (!transport.Paths.SequenceEqual(expPaths)) failures.Add($"{name} : chemins [{string.Join(", ", transport.Paths)}], attendu [{string.Join(", ", expPaths)}]");
            var expAt = e.GetProperty("at").EnumerateArray().Select(x => x.GetDouble()).ToList();
            var at = transport.Calls.Select(c => c.At).ToList();
            if (at.Count != expAt.Count || !at.Zip(expAt).All(p => Close(p.First, p.Second, 1e-6))) failures.Add($"{name} : instants [{string.Join(", ", at)}], attendu [{string.Join(", ", expAt)}]");
            if (!Close(clock.Now, e.GetProperty("end").GetDouble(), 1e-6)) failures.Add($"{name} : fin {clock.Now}, attendu {e.GetProperty("end")}");
            if ((log.BusyCount > 0) != e.GetProperty("busy").GetBoolean()) failures.Add($"{name} : « service occupé » {log.BusyCount > 0}");
        }
        _out.WriteLine($"PARITE runner.json scenarios={count}");
        foreach (var f in failures) _out.WriteLine("ÉCHEC : " + f);
        Assert.Empty(failures);
        Assert.True(count >= 15);
    }
}
