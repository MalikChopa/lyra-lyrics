namespace LyraLyrics.Core;

// Types échangés par le cœur portable (port de Sources/LyricsCore/Types.swift).
// Les instants sont des secondes sur une horloge monotone fournie par l'appelant.

/// <summary>Titre en cours. <c>Duration</c> en secondes (null = inconnue : synchro acceptée sans contrôle).</summary>
public sealed record TrackInfo(string Title, string Artist, string? Album = null, double? Duration = null, string? SourceId = null, string Player = "")
{
    /// <summary>Clé d'identité : identifiant source, sinon titre + artiste + album.</summary>
    public string Identity => SourceId is not null ? $"{Player}:{SourceId}" : $"{Title}\u001F{Artist}\u001F{Album ?? ""}";
}

public enum PlaybackState { Playing, Paused, Stopped }

/// <summary>Relevé de lecture : position (s), instant monotone auquel elle est valable, état.</summary>
public readonly record struct PlaybackReading(double Position, double At, PlaybackState State);

public sealed record LyricLine(double Time, string Text);

public enum LyricsKind { Synced, Plain, Instrumental }

/// <summary>
/// Paroles d'un titre, EN MÉMOIRE SEULEMENT (D2) : ce type n'est volontairement ni sérialisable ni enregistrable
/// (aucun attribut de sérialisation ; un test vérifie qu'aucun type d'écriture disque ne l'accepte).
/// </summary>
public sealed class Lyrics
{
    public LyricsKind Kind { get; }
    public IReadOnlyList<LyricLine> Lines { get; }
    public string? PlainText { get; }
    public int? LrclibId { get; }
    /// <summary>Pourquoi ce choix (diagnostic, sans texte).</summary>
    public string Provenance { get; }

    private Lyrics(LyricsKind kind, IReadOnlyList<LyricLine>? lines, string? plain, int? id, string provenance)
    { Kind = kind; Lines = lines ?? Array.Empty<LyricLine>(); PlainText = plain; LrclibId = id; Provenance = provenance; }

    public static Lyrics Synced(IReadOnlyList<LyricLine> lines, int? id = null, string provenance = "") => new(LyricsKind.Synced, lines, null, id, provenance);
    public static Lyrics Plain(string text, int? id = null, string provenance = "") => new(LyricsKind.Plain, null, text, id, provenance);
    public static Lyrics Instrumental(int? id = null, string provenance = "") => new(LyricsKind.Instrumental, null, null, id, provenance);

    public bool IsSynced => Kind == LyricsKind.Synced;
}
