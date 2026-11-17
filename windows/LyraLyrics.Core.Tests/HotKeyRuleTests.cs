using System.Text.Json;
using Xunit;

namespace LyraLyrics.Core.Tests;

/// <summary>règle du raccourci global, fixture PARTAGÉE avec Swift (<c>Tests/AppSupportTests/HotKeyRuleTests.swift</c>).</summary>
public class HotKeyRuleTests
{
    [Fact]
    public void HotKey_SharedFixture()
    {
        using var doc = Fixtures.Json("golden/hotkey.json");
        var cases = doc.RootElement.GetProperty("cases").EnumerateArray().ToList();
        foreach (var c in cases)
        {
            var want = c.GetProperty("expect");
            var got = HotKeyRule.Decide(c.GetProperty("windowShown").GetBoolean(), c.GetProperty("clickThrough").GetBoolean());
            Assert.Equal(new HotKeyRule.Outcome(want.GetProperty("clickThrough").GetBoolean(), want.GetProperty("showWindow").GetBoolean()), got);
        }
        Assert.Equal(4, cases.Count);
    }

    [Theory]
    [InlineData(true, true)] [InlineData(true, false)] [InlineData(false, true)] [InlineData(false, false)]
    public void HotKey_never_hides_the_window(bool shown, bool clickThrough) => Assert.Equal(!shown, HotKeyRule.Decide(shown, clickThrough).ShowWindow);
}
