using System.Text;

namespace LyraLyrics.Core;

/// <summary>
/// Journal fichier à rotation (constat 16) : survit à une erreur passagère (antivirus, fichier ouvert dans un lecteur) : chaque
/// ligne retente l'écriture, et le nombre de lignes perdues est consigné dès que ça remarche. Flux ouvert une fois, vidé à chaque ligne.
/// </summary>
public sealed class RollingLog : IDisposable
{
    private readonly string _path;
    private readonly long _maxBytes;
    private readonly object _gate = new();
    private FileStream? _stream;
    private int _lost;
    private int _totalFailures;

    public RollingLog(string path, long maxBytes = 256 * 1024) { _path = path; _maxBytes = maxBytes; }

    /// <summary>Nombre total d'échecs d'écriture depuis le début (information de diagnostic).</summary>
    public int TotalFailures { get { lock (_gate) return _totalFailures; } }

    public void Write(string line)
    {
        lock (_gate)
        {
            try
            {
                Open();
                if (_lost > 0) { Append($"{Stamp()} [journal] {_lost} ligne(s) perdue(s) (erreur d'écriture passagère)"); _lost = 0; }
                Append(line);
                if (_stream!.Length > _maxBytes) Rotate();
            }
            catch
            {
                _lost++; _totalFailures++;
                CloseQuietly();          // on rouvrira à la ligne suivante
            }
        }
    }

    public static string Stamp() => DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");

    private void Open()
    {
        if (_stream is not null) return;
        var dir = Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        _stream = new FileStream(_path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
    }

    private void Append(string line)
    {
        var bytes = new UTF8Encoding(false).GetBytes(line + Environment.NewLine);
        _stream!.Write(bytes, 0, bytes.Length);
        _stream.Flush();
    }

    private void Rotate()
    {
        CloseQuietly();
        File.Move(_path, _path + ".1", overwrite: true);
    }

    private void CloseQuietly() { try { _stream?.Dispose(); } catch { } _stream = null; }

    /// <summary>Dernières lignes du journal actuel (complétées par le précédent si besoin), pour le diagnostic.</summary>
    public IReadOnlyList<string> ReadTail(int count)
    {
        var lines = new List<string>();
        foreach (var p in new[] { _path + ".1", _path })
        {
            try
            {
                if (!File.Exists(p)) continue;
                using var fs = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var r = new StreamReader(fs, new UTF8Encoding(false));
                string? l;
                while ((l = r.ReadLine()) is not null) lines.Add(l);
            }
            catch { }
        }
        return lines.Count <= count ? lines : lines.GetRange(lines.Count - count, count);
    }

    public void Dispose() { lock (_gate) CloseQuietly(); }
}
