using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Écran d'accueil du premier lancement (A1) : mêmes 3 cartes que le Mac. Sur Windows il n'y a AUCUNE autorisation à demander (Spotify est lu par le
/// contrôle multimédia de Windows) : la carte « Autoriser Spotify » est remplacée par l'état de la détection de Spotify. Rouvrable par le menu de l'icône.
/// </summary>
internal sealed class WelcomeWindow : Window
{
    public const string Subtitle = "Les paroles de ton morceau, dans une petite fenêtre toujours au-dessus.";
    public const string NoPermissionNote = "Rien à autoriser sur Windows : Spotify est lu par le contrôle multimédia du système, et les paroles s'affichent tout de suite. Lance simplement l'application Spotify de bureau.";

    /// <summary>Les trois cartes (titre, texte) ; la 3e porte le raccourci actuel.</summary>
    public static (string Title, string Body)[] Cards(string hotKey) => new[]
    {
        ("Lance un titre dans Spotify", "Les paroles apparaissent en quelques secondes."),
        ("Survole la fenêtre", "Les boutons de lecture, le style ◐ et les réglages ⚙ apparaissent."),
        ($"{hotKey} : clic-à-travers", "Active ou coupe le clic-à-travers (et montre la fenêtre si elle est cachée), même si l'icône de la zone de notification est cachée. Pour cacher la fenêtre : menu de l'icône de notification."),
    };

    public Action? Start { get; set; }
    private readonly TextBlock _status = new() { FontSize = 12.5, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, VerticalAlignment = VerticalAlignment.Center };

    public WelcomeWindow(string hotKey, Func<bool> spotifyDetected)
    {
        Icon = LyraLyrics.App.Services.AppIcon.Wpf;
        Title = "Bienvenue dans " + AppIdentity.DisplayName;
        Width = 420; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen; Topmost = true; ShowInTaskbar = true;
        Background = new SolidColorBrush(Color.FromRgb(36, 36, 44));
        var accent = new SolidColorBrush(Color.FromRgb(10, 132, 255));
        var stack = new StackPanel { Margin = new Thickness(24, 20, 24, 20) };
        stack.Children.Add(new TextBlock { Text = "Bienvenue dans " + AppIdentity.DisplayName, FontSize = 18, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White });
        stack.Children.Add(new TextBlock { Text = Subtitle, FontSize = 12.5, TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.FromArgb(180, 255, 255, 255)), Margin = new Thickness(0, 6, 0, 8) });
        var n = 0;
        foreach (var (title, body) in Cards(hotKey))
        {
            n++;
            var row = new Grid { Margin = new Thickness(0, 5, 0, 5) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var badge = new Border { Width = 22, Height = 22, CornerRadius = new CornerRadius(11), Background = new SolidColorBrush(Color.FromArgb(140, 10, 132, 255)), VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 0, 12, 0),
                Child = new TextBlock { Text = n.ToString(), Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = 12, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center } };
            var text = new StackPanel();
            text.Children.Add(new TextBlock { Text = title, FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, TextWrapping = TextWrapping.Wrap });
            text.Children.Add(new TextBlock { Text = body, FontSize = 11.5, Foreground = new SolidColorBrush(Color.FromArgb(175, 255, 255, 255)), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) });
            Grid.SetColumn(badge, 0); Grid.SetColumn(text, 1);
            row.Children.Add(badge); row.Children.Add(text);
            var card = new Border { CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255)), Padding = new Thickness(10), Child = row };
            AutomationName(card, $"Étape {n} : {title}. {body}");
            stack.Children.Add(card);
        }
        var buttons = new Grid { Margin = new Thickness(0, 14, 0, 0) };
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(_status, 0);
        var go = new Button { Content = "Commencer", Padding = new Thickness(20, 6, 20, 6), IsDefault = true, Background = accent, Foreground = Brushes.White, BorderThickness = new Thickness(0), FontWeight = FontWeights.SemiBold };
        Grid.SetColumn(go, 1);
        go.Click += (_, _) => { Start?.Invoke(); Close(); };
        A11y.Name(go, "Commencer");
        buttons.Children.Add(_status); buttons.Children.Add(go);
        stack.Children.Add(buttons);
        stack.Children.Add(new TextBlock { Text = NoPermissionNote, FontSize = 11, TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.FromArgb(140, 255, 255, 255)), Margin = new Thickness(0, 10, 0, 0) });
        Content = stack;
        A11y.Name(this, "Bienvenue");
        A11y.Name(_status, "État de la détection de Spotify");
        Refresh(spotifyDetected);
        Activated += (_, _) => Refresh(spotifyDetected);
    }

    private void Refresh(Func<bool> detected) =>
        _status.Text = detected() ? "Spotify détecté" : "Spotify pas encore détecté";

    private static void AutomationName(DependencyObject o, string name) => A11y.Name(o, name);
}
