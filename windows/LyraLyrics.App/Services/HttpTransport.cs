using System.Net;
using System.Net.Http;
using LyraLyrics.Core;

namespace LyraLyrics.App.Services;

/// <summary>
/// Transport réel vers lrclib.net (D3, D8) : aucun cache, aucun cookie, pas de redirection suivie vers un autre hôte, User-Agent de l'app.
/// Les requêtes sont envoyées une par une par la porte (RequestGate).
/// </summary>
internal sealed class HttpTransport : ILrclibTransport, IDisposable
{
    private readonly HttpClient _http;

    public HttpTransport()
    {
        var handler = new SocketsHttpHandler
        {
            UseCookies = false,
            AllowAutoRedirect = false,
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli,
            ConnectTimeout = TimeSpan.FromSeconds(8),
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
            UseProxy = true,
        };
        _http = new HttpClient(handler, disposeHandler: true) { Timeout = Timeout.InfiniteTimeSpan };
    }

    public async Task<HttpReply> SendAsync(LrclibRequest request, double timeoutSeconds, CancellationToken ct)
    {
        using var msg = new HttpRequestMessage(HttpMethod.Get, request.Url);
        msg.Headers.TryAddWithoutValidation("User-Agent", request.UserAgent);
        msg.Headers.TryAddWithoutValidation("Accept", "application/json");
        msg.Headers.TryAddWithoutValidation("Cache-Control", "no-cache");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Max(0.5, timeoutSeconds)));
        try
        {
            using var response = await _http.SendAsync(msg, HttpCompletionOption.ResponseContentRead, timeout.Token).ConfigureAwait(false);
            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var h in response.Headers) headers[h.Key] = string.Join(",", h.Value);
            foreach (var h in response.Content.Headers) headers[h.Key] = string.Join(",", h.Value);
            var body = await response.Content.ReadAsByteArrayAsync(timeout.Token).ConfigureAwait(false);
            return new HttpReply((int)response.StatusCode, headers, body);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw new LrclibException(LrclibErrorKind.Cancelled); }
        catch (OperationCanceledException) { throw new LrclibException(LrclibErrorKind.Timeout); }
        catch (HttpRequestException e) { throw new LrclibException(LrclibErrorKind.Transport, message: e.GetType().Name); }
    }

    public void Dispose() => _http.Dispose();
}
