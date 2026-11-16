using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>« À propos et droits » : textes de la version Mac, adaptés à Windows (la pochette est lue localement via SMTC : aucune requête vers un serveur d'images).</summary>
internal sealed class AboutWindow : Window
{
    /// <summary>Phrase de transparence réseau (Windows).</summary>
    public const string NetworkSentence =
        "Pour trouver les paroles, le titre, l'artiste, l'album et la durée du morceau en cours sont envoyés à lrclib.net (avec ton adresse IP, comme toute requête web). " +
        "La pochette du morceau Spotify est lue localement via Windows (aucune requête vers un serveur d'images) et gardée en mémoire seulement. " +
        "Rien d'autre ne quitte ton PC : ni statistiques, ni rapport de plantage.";

    /// <summary>Précise où mène le lien (la page publique des signalements du dépôt) : rien n'est envoyé par l'application elle-même.</summary>
    public const string ReportSentence = "Le lien ouvre la page des signalements du projet sur GitHub, dans ton navigateur : l'application n'envoie rien. Évite d'y coller ton journal sans l'avoir relu.";

    public AboutWindow()
    {
        Icon = LyraLyrics.App.Services.AppIcon.Wpf;
        Title = "À propos de " + AppIdentity.DisplayName;
        Width = 480; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true; ShowInTaskbar = true;
        Background = new SolidColorBrush(Color.FromRgb(36, 36, 44));
        var stack = new StackPanel { Margin = new Thickness(26, 22, 26, 22) };
        stack.Children.Add(new TextBlock { Text = AppIdentity.DisplayName, FontSize = 20, FontWeight = FontWeights.Bold, Foreground = Brushes.White });
        stack.Children.Add(new TextBlock { Text = $"Version {AppIdentity.Version} · Windows (version de test)", FontSize = 12, Foreground = new SolidColorBrush(Color.FromArgb(150, 255, 255, 255)), Margin = new Thickness(0, 4, 0, 6) });
        void Para(string text)
        {
            stack.Children.Add(new TextBlock { Text = text, FontSize = 13, TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.FromArgb(220, 255, 255, 255)), Margin = new Thickness(0, 10, 0, 0) });
        }
        Para("Paroles fournies par LRCLIB (lrclib.net), base communautaire.");
        Para("Les paroles appartiennent à leurs auteurs et éditeurs. Elles sont affichées pour un usage personnel ; cette application ne les stocke pas sur un serveur, ne les enregistre pas sur le disque et ne les redistribue pas.");
        Para(NetworkSentence);
        Para("Application indépendante, non affiliée à LRCLIB ou à Spotify.");
        var report = new ClickableText { Text = "Signaler un problème", FontSize = 13, TextDecorations = TextDecorations.Underline, Cursor = System.Windows.Input.Cursors.Hand, Foreground = new SolidColorBrush(Color.FromRgb(124, 192, 255)), Margin = new Thickness(0, 10, 0, 0), HorizontalAlignment = HorizontalAlignment.Left };
        report.Activated = () => Services.LinkOpener.OpenIssues();
        report.MouseLeftButtonUp += (_, _) => Services.LinkOpener.OpenIssues();
        A11y.Name(report, "Signaler un problème", "Ouvre la page des signalements du dépôt sur GitHub, dans le navigateur");
        stack.Children.Add(report);
        Para(ReportSentence);
        Para("Journal local : " + Services.AppPaths.LogFile + " (sans titre ni paroles).");
        var close = new Button { Content = "Fermer", Padding = new Thickness(18, 6, 18, 6), Margin = new Thickness(0, 18, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, IsDefault = true, IsCancel = true };
        close.Click += (_, _) => Close();
        System.Windows.Automation.AutomationProperties.SetName(close, "Fermer la fenêtre À propos");
        System.Windows.Automation.AutomationProperties.SetName(this, "À propos de " + AppIdentity.DisplayName);
        stack.Children.Add(close);
        Content = stack;
    }
}
