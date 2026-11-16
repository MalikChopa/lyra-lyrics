using System.Diagnostics;
using LyraLyrics.Core;

namespace LyraLyrics.App.Services;

/// <summary>
/// Ouvre un lien dans le navigateur. Deux seules destinations existent : la page de la version annoncée (SEULEMENT si <see cref="UpdateCheck.IsTrusted"/>)
/// et la page des signalements du dépôt (adresse fixe). Une adresse venue d'une réponse du réseau n'est jamais ouverte sans ce contrôle.
/// </summary>
internal static class LinkOpener
{
    public static bool OpenRelease(Uri url)
    {
        if (!UpdateCheck.IsTrusted(url)) { Log.Write("app", "lien de version refusé (hôte ou dépôt inattendu)"); return false; }
        return Launch(url, "page de la nouvelle version");
    }

    public static bool OpenIssues() => Launch(UpdateCheck.IssuesPage, "page des signalements");

    private static bool Launch(Uri url, string what)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true });
            Log.Write("app", "lien ouvert : " + what);
            return true;
        }
        catch (Exception e) { Log.WriteException("erreur", "ouverture du lien (" + what + ")", e); return false; }
    }
}
