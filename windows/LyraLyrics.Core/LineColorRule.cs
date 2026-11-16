namespace LyraLyrics.Core;

/// <summary>Règle de couleur du texte, identique au Mac (ARCHITECTURE §14.7) : la couleur choisie par l'utilisateur gagne ; la pochette ne teinte que le fond.</summary>
public static class LineColorRule
{
    public static string TextHex(string chosenHex, bool artworkColors, string? artworkAccentHex) => chosenHex;
}
