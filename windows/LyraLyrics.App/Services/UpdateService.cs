using LyraLyrics.Core;

namespace LyraLyrics.App.Services;

/// <summary>
/// « Nouvelle version disponible » (E1, D12) : UNE requête GET par jour au plus, au lancement, vers l'API publique de GitHub, par le même transport
/// que LRCLIB (aucun cache, aucun cookie, User-Agent de l'app) ; rien d'autre n'est envoyé. Seule la logique pure du Core lit la réponse.
/// Désactivable (réglage « Vérifier les mises à jour »).
/// </summary>
internal sealed class UpdateService
{
    private readonly ILrclibTransport _transport;
    public int RequestCount { get; private set; }

    public UpdateService(ILrclibTransport transport) { _transport = transport; }

    public async Task<UpdateCheck.Outcome> CheckAsync(string localVersion, CancellationToken ct = default)
    {
        try
        {
            var url = UpdateCheck.Endpoint;
            // Une redirection (compte renommé : 301 constaté sur le Mac) est suivie UNE fois, et seulement vers api.github.com en https.
            for (var hop = 0; hop < 2; hop++)
            {
                RequestCount++;
                var reply = await _transport.SendAsync(new LrclibRequest(url, AppIdentity.UserAgent), 8, ct).ConfigureAwait(false);
                if (reply.Status == 200 && reply.BodyBytes.Length < UpdateCheck.MaxBodyBytes) return UpdateCheck.Evaluate(reply.BodyBytes, localVersion);
                if (hop == 0 && (reply.Status is 301 or 302 or 307 or 308) && reply.Header("Location") is { } loc
                    && Uri.TryCreate(url, loc, out var next) && next.Scheme == "https" && string.Equals(next.Host, UpdateCheck.Host, StringComparison.OrdinalIgnoreCase)) { url = next; continue; }
                break;
            }
        }
        catch (Exception) { }
        return new UpdateCheck.Outcome.Failed();
    }
}
