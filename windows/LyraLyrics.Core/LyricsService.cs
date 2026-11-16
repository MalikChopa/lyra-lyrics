using System.Security.Cryptography;
using System.Text;

namespace LyraLyrics.Core;

/// <summary>Ce que le service rapporte au modèle. Jamais de texte dans les diagnostics ; le texte ne circule que dans <see cref="Found"/>, en mémoire.</summary>
public abstract record LyricsServiceEvent
{
    public sealed record Searching : LyricsServiceEvent;
    public sealed record Retrying : LyricsServiceEvent;
    public sealed record Busy(double RetryIn, string Reason) : LyricsServiceEvent;
    public sealed record Offline : LyricsServiceEvent;
    public sealed record Found(Lyrics Lyrics, bool Cached) : LyricsServiceEvent;
    public sealed record NotFound(string Reason) : LyricsServiceEvent;
    public sealed record Stalled(string Reason) : LyricsServiceEvent;
}

/// <summary>Résultat de recherche manuelle (1.1.0, B1) : métadonnées seulement, JAMAIS de paroles.</summary>
public sealed record ManualCandidate(int Id, string Title, string Artist, string? Album, double? Duration, bool Synced, bool Instrumental);

public abstract record ManualSearchOutcome
{
    public sealed record Results(IReadOnlyList<ManualCandidate> Candidates) : ManualSearchOutcome;
    public sealed record Failed(string Message) : ManualSearchOutcome;
}

/// <summary>
/// Service des paroles (port de LyricsService.swift) : LookupRunner + LyricsCache (mémoire) + LookupIndex (disque, sans texte).
/// Requêtes séquentielles ; un changement de titre annule la recherche en cours.
/// </summary>
public sealed class LyricsService
{
    /// <summary>Révision des règles de recherche, comprise dans la clé de l'index disque.</summary>
    public const string MatchingRevision = "2";

    private readonly LookupRunner _runner;
    private readonly LrclibClient _client;
    /// <summary>Résultats de la dernière recherche manuelle (30 au plus), gardés EN MÉMOIRE pour que « choisir » n'ait pas besoin d'une seconde requête.</summary>
    private Dictionary<int, LrclibRecord> _lastSearch = new();
    private readonly LyricsCache _cache = new();
    private readonly LookupIndex _index;
    private readonly string? _indexPath;
    private readonly Func<string, string> _hasher;
    private readonly Action<Dictionary<string, string>> _log;
    private CancellationTokenSource? _current;
    private readonly object _lock = new();

    public LyricsService(LrclibClient client, string? indexPath, Func<string, string> hasher, Func<double> clock,
                         Func<double, CancellationToken, Task> sleep, int titlesBeforeBreaker = 3, double minSpacing = RequestGate.MinSpacingDefault,
                         LookupRunner.Config? config = null, Action<Dictionary<string, string>>? log = null, Func<DateTimeOffset>? now = null)
    {
        _log = log ?? (_ => { });
        _client = client;
        _runner = new LookupRunner(client, new RequestGate(titlesBeforeBreaker, minSpacing), clock, sleep, config, _log);
        _indexPath = indexPath;
        _index = indexPath is null ? new LookupIndex() : LookupIndex.Load(indexPath);
        _hasher = hasher;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _index.Purge(_now());
    }

    private readonly Func<DateTimeOffset> _now;

    public int IndexCount => _index.Count;
    public int CacheCount => _cache.Count;
    public bool IsOffline => _runner.IsOffline;

    /// <summary>SHA-256 salé (sel aléatoire par installation ; D4 : obscurcissement léger, pas une protection).</summary>
    public static Func<string, string> SaltedHasher(string salt) => material =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(salt + "\u001F" + material)));

    public static string NewSalt() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(16));

    public void SetOnline(bool online) => _runner.SetOnline(online);

    /// <summary>« Vider le cache » : index disque vidé (et fichier réécrit), cache mémoire vidé.</summary>
    public void ClearAll()
    {
        _index.Clear(); _cache.Clear();
        SaveIndex();
        _log(new() { ["lookup"] = "cache-vide", ["index"] = "0" });
    }

    public void Cancel()
    {
        lock (_lock) { _current?.Cancel(); _current = null; }
    }

    public Task LookupAsync(TrackInfo track, Action<LyricsServiceEvent> report) => Start(track, false, report);

    /// <summary>Bouton « Réessayer » : oublie le « non trouvé » noté pour ce titre (index et cache) et recommence de zéro.</summary>
    public Task RetryAsync(TrackInfo track, Action<LyricsServiceEvent> report)
    {
        _index.Remove(IndexKey(track));
        _cache.Remove(track.Identity);
        _log(new() { ["lookup"] = "reessayer" });
        return Start(track, true, report);
    }

    // ---- Recherche manuelle et choix de la version (1.1.0, B1)

    /// <summary>Recherche libre (titre, artiste) : UNE requête par action de l'utilisateur ; métadonnées seulement dans le résultat.</summary>
    public async Task<ManualSearchOutcome> SearchAsync(string title, string artist, CancellationToken ct = default)
    {
        var t = title.Trim(); var a = artist.Trim();
        if (t.Length == 0 && a.Length == 0) return new ManualSearchOutcome.Results(Array.Empty<ManualCandidate>());
        SearchQuery query = t.Length == 0 || a.Length == 0 ? new SearchQuery.Combined(t + a) : new SearchQuery.Fields(t, a);
        try
        {
            var records = await _client.SearchAsync(query, 8, ct).ConfigureAwait(false);
            var top = records.Take(30).ToList();
            lock (_lock) _lastSearch = top.GroupBy(r => r.Id).ToDictionary(g => g.Key, g => g.First());
            _log(new() { ["lookup"] = "recherche-manuelle", ["resultats"] = records.Count.ToString() });
            return new ManualSearchOutcome.Results(top.Select(r => new ManualCandidate(r.Id, r.TrackName, r.ArtistName, r.AlbumName, r.Duration, r.Candidate.HasSynced, r.Instrumental)).ToList());
        }
        catch (LrclibException e)
        {
            return new ManualSearchOutcome.Failed(e.Kind switch
            {
                LrclibErrorKind.Offline => "Hors connexion",
                LrclibErrorKind.Timeout => "Le service met trop de temps à répondre",
                LrclibErrorKind.Cancelled => "Recherche annulée",
                _ => "Le service ne répond pas pour l'instant",
            });
        }
        catch (OperationCanceledException) { return new ManualSearchOutcome.Failed("Recherche annulée"); }
        catch (Exception) { return new ManualSearchOutcome.Failed("Recherche impossible"); }
    }

    /// <summary>Choisit une version : utilisée tout de suite et mémorisée pour ce titre (identifiant seulement, sans limite de 24 h). Faux si elle n'est plus en mémoire.</summary>
    public bool Choose(int id, TrackInfo track, Action<LyricsServiceEvent> report)
    {
        LrclibRecord? record;
        lock (_lock) _lastSearch.TryGetValue(id, out record);
        if (record is null || LrclibClient.LyricsFrom(record, track, "choix manuel", trustDuration: true) is not { } lyrics) return false;
        Cancel();
        _index.RecordManual(IndexKey(track), id, _now());
        SaveIndex();
        _cache.Store(lyrics, track.Identity);
        _log(new() { ["lookup"] = "choix-manuel" });   // D6 : jamais l'identifiant LRCLIB dans le journal
        report(new LyricsServiceEvent.Found(lyrics, false));
        return true;
    }

    /// <summary>« Revenir au choix automatique » : oublie le choix et refait la recherche normale.</summary>
    public Task RevertToAutomaticAsync(TrackInfo track, Action<LyricsServiceEvent> report)
    {
        _index.RemoveManual(IndexKey(track));
        SaveIndex();
        _log(new() { ["lookup"] = "choix-manuel-retire" });
        return RetryAsync(track, report);
    }

    public bool HasManualChoice(TrackInfo track) => _index.ManualChoice(IndexKey(track)) is not null;

    private Task Start(TrackInfo track, bool forced, Action<LyricsServiceEvent> report)
    {
        CancellationToken ct;
        lock (_lock)
        {
            _current?.Cancel();
            _current = new CancellationTokenSource();
            ct = _current.Token;
        }
        return Task.Run(() => RunAsync(track, forced, report, ct));
    }

    private string IndexKey(TrackInfo track) => LookupIndex.KeyFor(track, m => _hasher(MatchingRevision + "\u001F" + m));

    private async Task RunAsync(TrackInfo track, bool forced, Action<LyricsServiceEvent> report, CancellationToken ct)
    {
        try
        {
            var key = track.Identity;
            if (!forced && _cache.Fetch(key) is { } hit)
            {
                _log(new() { ["lookup"] = "cache", ["resultat"] = Kind(hit) });
                report(new LyricsServiceEvent.Found(hit, true));
                return;
            }
            var indexKey = IndexKey(track);
            if (!forced && _index.ManualChoice(indexKey) is int pinned)
            {
                // Choix manuel mémorisé : une requête get/{id} ; en cas d'échec, la recherche normale prend le relais.
                report(new LyricsServiceEvent.Searching());
                try
                {
                    var record = await _client.GetAsync(pinned, 8, ct).ConfigureAwait(false);
                    if (LrclibClient.LyricsFrom(record, track, "choix manuel", trustDuration: true) is { } chosen)
                    {
                        if (ct.IsCancellationRequested) return;
                        _log(new() { ["lookup"] = "livre", ["resultat"] = "choix manuel" });
                        _cache.Store(chosen, key);
                        report(new LyricsServiceEvent.Found(chosen, false));
                        return;
                    }
                }
                catch (LrclibException) { }
                if (ct.IsCancellationRequested) return;
            }
            int? knownId = null;
            switch (forced ? null : _index.Lookup(indexKey, _now()))
            {
                case LookupIndex.Outcome.NotFound:
                    _log(new() { ["lookup"] = "index", ["resultat"] = "non trouvé (< 24 h)" });
                    report(new LyricsServiceEvent.NotFound("index : non trouvé il y a moins de 24 h"));
                    return;
                case LookupIndex.Outcome.Found f:
                    _log(new() { ["lookup"] = "index", ["resultat"] = "trouvé (identifiant connu)" });   // D6 : jamais l'identifiant LRCLIB
                    knownId = f.Id;
                    break;
            }
            var outcome = await _runner.RunAsync(track, knownId, e =>
            {
                switch (e)
                {
                    case LookupEvent.Searching: report(new LyricsServiceEvent.Searching()); break;
                    case LookupEvent.Retrying: report(new LyricsServiceEvent.Retrying()); break;
                    case LookupEvent.Busy b: report(new LyricsServiceEvent.Busy(b.RetryIn, b.Reason)); break;
                    case LookupEvent.Offline: report(new LyricsServiceEvent.Offline()); break;
                }
            }, ct).ConfigureAwait(false);
            if (ct.IsCancellationRequested) return;
            switch (outcome)
            {
                case LookupOutcome.Found found:
                    _log(new() { ["lookup"] = "livre", ["resultat"] = Kind(found.Lyrics) });   // D6 : ni identifiant LRCLIB ni provenance
                    _cache.Store(found.Lyrics, key);
                    if (found.Lyrics.LrclibId is int id) { _index.Record(indexKey, new LookupIndex.Outcome.Found(id), _now()); SaveIndex(); }
                    report(new LyricsServiceEvent.Found(found.Lyrics, false));
                    break;
                case LookupOutcome.NotFound nf:
                    if (nf.Definitive) { _index.Record(indexKey, new LookupIndex.Outcome.NotFound(), _now()); SaveIndex(); }
                    report(new LyricsServiceEvent.NotFound(nf.Reason));
                    break;
                case LookupOutcome.Stalled st:
                    _log(new() { ["lookup"] = "service-occupe", ["raison"] = st.Reason });
                    report(new LyricsServiceEvent.Stalled(st.Reason));
                    break;
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception e)
        {
            // Constat 9 : jamais de « Recherche… » sans fin. Pile sans message (le message pourrait citer une donnée de piste).
            _log(new() { ["lookup"] = "erreur-interne", ["type"] = e.GetType().FullName ?? e.GetType().Name, ["pile"] = StackOnly(e) });
            try { report(new LyricsServiceEvent.Stalled("erreur interne")); } catch { }
        }
    }

    private static string StackOnly(Exception e) => string.Join(" <- ", (e.StackTrace ?? "").Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0).Take(6));

    private static string Kind(Lyrics l) => l.IsSynced ? "synced" : (l.Kind == LyricsKind.Plain ? "plain" : "instrumental");

    private void SaveIndex()
    {
        if (_indexPath is null) return;
        try { _index.Save(_indexPath); }
        catch (Exception e) { _log(new() { ["lookup"] = "index-ecriture-echec", ["type"] = e.GetType().Name }); }
    }
}
