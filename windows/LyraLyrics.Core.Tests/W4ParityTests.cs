using System.Text;
using System.Text.Json;

namespace LyraLyrics.Core.Tests;

/// <summary>W4 : fixtures PARTAGÉES avec Swift (<c>Tests/AppSupportTests/W4FixtureTests.swift</c>, <c>Tests/LyricsCoreTests/W4FixtureTests.swift</c>).</summary>
public class W4ParityTests
{
    private static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);

    private static string? Str(JsonElement e, string name) => e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    private static AutoHideMode Mode(string s) => s switch { "never" => AutoHideMode.Never, "paused" => AutoHideMode.Paused, "idle" => AutoHideMode.Idle, _ => throw new ArgumentException(s) };
    private static PlaybackActivity Act(string s) => s switch { "nothing" => PlaybackActivity.Nothing, "paused" => PlaybackActivity.Paused, "playing" => PlaybackActivity.Playing, _ => throw new ArgumentException(s) };
    private static string? Label(AutoHideState.Action? a) => a is null ? null : a == AutoHideState.Action.Hide ? "hide" : "show";

    [Fact]
    public void AutoHide_Conditions_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/autohide.json");
        var cases = doc.RootElement.GetProperty("conditions").EnumerateArray().ToList();
        foreach (var c in cases)
            Assert.Equal(c.GetProperty("expected").GetBoolean(), AutoHideState.Condition(Mode(Str(c, "mode")!), Act(Str(c, "activity")!)));
        Assert.Equal(9, cases.Count);
    }

    [Fact]
    public void AutoHide_Scenarios_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/autohide.json");
        var failures = new List<string>();
        var scenarios = doc.RootElement.GetProperty("scenarios").EnumerateArray().ToList();
        foreach (var sc in scenarios)
        {
            var state = new AutoHideState();
            var i = 0;
            foreach (var step in sc.GetProperty("steps").EnumerateArray())
            {
                i++;
                if (Str(step, "op") == "manual") { state.ManualChange(step.GetProperty("windowShown").GetBoolean()); continue; }
                var got = Label(state.Evaluate(Mode(Str(step, "mode")!), Act(Str(step, "activity")!), step.GetProperty("windowShown").GetBoolean()));
                var want = Str(step, "expect");
                if (got != want) failures.Add($"{Str(sc, "name")} pas {i - 1} : {got ?? "null"}, attendu {want ?? "null"}");
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.True(scenarios.Count >= 12);
    }

    [Fact]
    public void UpdateCheck_Parse_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/update-check.json");
        var failures = new List<string>();
        var cases = doc.RootElement.GetProperty("parse").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var r = UpdateCheck.Parse(Encoding.UTF8.GetBytes(Str(c, "payload")!));
            var wantTag = Str(c, "tag"); var wantUrl = Str(c, "url");
            if (r?.Tag != wantTag) failures.Add($"{Str(c, "name")} : tag {r?.Tag ?? "null"}, attendu {wantTag ?? "null"}");
            if (wantUrl is not null && r?.Url.OriginalString != wantUrl) failures.Add($"{Str(c, "name")} : url {r?.Url}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.True(cases.Count >= 30);
    }

    [Fact]
    public void UpdateCheck_VersionsDueTrustedOutcome_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/update-check.json");
        var root = doc.RootElement;
        var failures = new List<string>();
        foreach (var c in root.GetProperty("newer").EnumerateArray())
            if (UpdateCheck.IsNewer(Str(c, "remote")!, Str(c, "local")!) != c.GetProperty("expected").GetBoolean()) failures.Add("newer " + c);
        foreach (var c in root.GetProperty("due").EnumerateArray())
        {
            double? last = c.GetProperty("last").ValueKind == JsonValueKind.Null ? null : c.GetProperty("last").GetDouble();
            if (UpdateCheck.IsDue(last, c.GetProperty("now").GetDouble()) != c.GetProperty("expected").GetBoolean()) failures.Add("due " + c);
        }
        foreach (var c in root.GetProperty("trusted").EnumerateArray())
        {
            var ok = Uri.TryCreate(Str(c, "url"), UriKind.Absolute, out var u) && UpdateCheck.IsTrusted(u);
            if (ok != c.GetProperty("expected").GetBoolean()) failures.Add("trusted " + c);
        }
        foreach (var c in root.GetProperty("outcome").EnumerateArray())
        {
            var got = UpdateCheck.Evaluate(Encoding.UTF8.GetBytes(Str(c, "payload")!), Str(c, "local")!) switch
            {
                UpdateCheck.Outcome.Newer n => "newer:" + n.Release.Tag, UpdateCheck.Outcome.UpToDate => "upToDate", _ => "failed",
            };
            if (got != Str(c, "expected")) failures.Add($"outcome {Str(c, "name")} : {got}");
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.Equal(root.GetProperty("endpoint").GetString(), UpdateCheck.Endpoint.AbsoluteUri);
        Assert.Equal(UpdateCheck.Host, root.GetProperty("host").GetString());
    }

    [Fact]
    public void LookupManual_Scenarios_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/lookup-manual.json");
        var failures = new List<string>();
        var scenarios = doc.RootElement.GetProperty("scenarios").EnumerateArray().ToList();
        foreach (var sc in scenarios)
        {
            var index = new LookupIndex();
            var name = Str(sc, "name");
            var i = -1;
            foreach (var step in sc.GetProperty("steps").EnumerateArray())
            {
                i++;
                var op = Str(step, "op")!;
                var at = T0.AddSeconds(step.TryGetProperty("at", out var a) ? a.GetDouble() : 0);
                string Key() => Str(step, "key")!;
                int Id() => step.GetProperty("id").GetInt32();
                switch (op)
                {
                    case "record": index.Record(Key(), new LookupIndex.Outcome.Found(Id()), at); break;
                    case "recordNotFound": index.Record(Key(), new LookupIndex.Outcome.NotFound(), at); break;
                    case "recordManual": index.RecordManual(Key(), Id(), at); break;
                    case "recordRange":
                        for (var n = step.GetProperty("from").GetInt32(); n < step.GetProperty("to").GetInt32(); n++) index.Record(Str(step, "prefix") + n, new LookupIndex.Outcome.Found(n), at);
                        break;
                    case "recordManualRange":
                        for (var n = step.GetProperty("from").GetInt32(); n < step.GetProperty("to").GetInt32(); n++) index.RecordManual(Str(step, "prefix") + n, n, at);
                        break;
                    case "removeManual": index.RemoveManual(Key()); break;
                    case "remove": index.Remove(Key()); break;
                    case "purge": index.Purge(at); break;
                    case "clear": index.Clear(); break;
                    case "lookup":
                    {
                        var got = index.Lookup(Key(), at) switch { null => null, LookupIndex.Outcome.NotFound => "notFound", LookupIndex.Outcome.Found f => "found:" + f.Id, _ => "?" };
                        if (got != Str(step, "expect")) failures.Add($"{name} pas {i} lookup : {got ?? "null"}");
                        break;
                    }
                    case "manualChoice":
                    {
                        var got = index.ManualChoice(Key());
                        int? want = step.GetProperty("expect").ValueKind == JsonValueKind.Null ? null : step.GetProperty("expect").GetInt32();
                        if (got != want) failures.Add($"{name} pas {i} manualChoice : {got?.ToString() ?? "null"}");
                        break;
                    }
                    case "count":
                        if (index.Count != step.GetProperty("expect").GetInt32()) failures.Add($"{name} pas {i} count : {index.Count}");
                        break;
                    default: failures.Add($"{name} : op inconnue {op}"); break;
                }
            }
        }
        Assert.True(failures.Count == 0, string.Join("\n", failures));
        Assert.True(scenarios.Count >= 7);
    }
}
