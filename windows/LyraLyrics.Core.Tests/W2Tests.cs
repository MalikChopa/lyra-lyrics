namespace LyraLyrics.Core.Tests;

/// <summary>W2 : correctifs propres au cœur C#.</summary>
public class W2Tests
{
    /// <summary>Constat 18 : deux tâches (changements de titre rapprochés) qui sauvent l'index en même temps écrasaient le même fichier
    /// temporaire ; <c>File.Move</c> pouvait échouer (IOException « index-ecriture-echec »).</summary>
    [Fact]
    public async Task LookupIndex_ConcurrentSaves_NeverFail_AndFileStaysComplete()
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "w2-index-" + Guid.NewGuid().ToString("N"));
        try
        {
            var path = Path.Combine(dir, LookupIndex.FileName);
            var index = new LookupIndex();
            var now = DateTimeOffset.UnixEpoch.AddDays(100);
            for (var i = 0; i < 40; i++) index.Record("cle-" + i, new LookupIndex.Outcome.Found(i + 1), now);
            var errors = new List<Exception>();
            var tasks = Enumerable.Range(0, 16).Select(t => Task.Run(() =>
            {
                for (var n = 0; n < 60; n++)
                {
                    try { index.Save(path); }
                    catch (Exception e) { lock (errors) errors.Add(e); }
                }
            })).ToArray();
            await Task.WhenAll(tasks);
            Assert.Empty(errors);
            Assert.False(File.Exists(path + ".tmp"), "le fichier temporaire ne doit pas rester");
            var reloaded = LookupIndex.Load(path);
            Assert.Equal(40, reloaded.Count);
        }
        finally { try { Directory.Delete(dir, true); } catch { } }
    }
}
