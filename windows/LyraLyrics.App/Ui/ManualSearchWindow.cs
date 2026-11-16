using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// « Mauvaises paroles ? » (B1) : recherche libre auprès de LRCLIB (UNE requête par clic sur « Chercher » ou Entrée), résultats en métadonnées seulement
/// (titre, artiste, album, durée, « synchronisées »), choix immédiat et mémorisé pour ce titre, « Revenir au choix automatique ». Mêmes textes que le Mac.
/// </summary>
internal sealed class ManualSearchWindow : Window
{
    public const string Intro = "Cherche une autre version sur LRCLIB et choisis-la : elle sera utilisée tout de suite et retenue pour ce titre.";
    public const string NoResult = "Aucune version trouvée. Essaie un autre titre ou un autre artiste.";
    public const string Chosen = "Version choisie, retenue pour ce titre.";
    public const string Gone = "Cette version n'est plus disponible : relance la recherche.";
    public const string Reverted = "Choix automatique rétabli.";

    private readonly AppModel _model;
    private readonly TextBox _title = new() { MinWidth = 150 }, _artist = new() { MinWidth = 120 };
    private readonly Button _search = new() { Content = "Chercher", Padding = new Thickness(14, 4, 14, 4), IsDefault = true };
    private readonly TextBlock _status = new() { Foreground = new SolidColorBrush(Color.FromArgb(190, 255, 255, 255)), FontSize = 12, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) };
    private readonly StackPanel _results = new();
    private readonly ClickableText _revert = new() { Text = "Revenir au choix automatique", FontSize = 12, Foreground = new SolidColorBrush(Color.FromRgb(124, 192, 255)), Cursor = Cursors.Hand, Visibility = Visibility.Collapsed, TextDecorations = TextDecorations.Underline };
    private bool _busy;
    private int? _chosenId;
    /// <summary>Nombre de requêtes de recherche lancées par cette fenêtre (une par action).</summary>
    public int SearchCount { get; private set; }

    public ManualSearchWindow(AppModel model)
    {
        Icon = LyraLyrics.App.Services.AppIcon.Wpf;
        _model = model;
        Title = "Mauvaises paroles ?";
        Width = 500; SizeToContent = SizeToContent.Height; MaxHeight = SystemParameters.WorkArea.Height * 0.95; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen; Topmost = true; ShowInTaskbar = true;
        Background = new SolidColorBrush(Color.FromRgb(36, 36, 44));
        var stack = new StackPanel { Margin = new Thickness(20, 16, 20, 16) };
        stack.Children.Add(new TextBlock { Text = "Mauvaises paroles ?", FontSize = 16, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White });
        stack.Children.Add(new TextBlock { Text = Intro, FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.FromArgb(165, 255, 255, 255)), Margin = new Thickness(0, 6, 0, 10) });
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(3, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(2, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _artist.Margin = new Thickness(8, 0, 8, 0);
        Grid.SetColumn(_title, 0); Grid.SetColumn(_artist, 1); Grid.SetColumn(_search, 2);
        row.Children.Add(_title); row.Children.Add(_artist); row.Children.Add(_search);
        stack.Children.Add(row);
        stack.Children.Add(_status);
        stack.Children.Add(new ScrollViewer { Content = _results, Height = 230, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 8, 0, 0) });
        var foot = new Grid { Margin = new Thickness(0, 10, 0, 0) };
        foot.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        foot.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var close = new Button { Content = "Fermer", Padding = new Thickness(14, 4, 14, 4), IsCancel = true };
        close.Click += (_, _) => Close();
        Grid.SetColumn(_revert, 0); _revert.VerticalAlignment = VerticalAlignment.Center; Grid.SetColumn(close, 1);
        foot.Children.Add(_revert); foot.Children.Add(close);
        stack.Children.Add(foot);
        stack.Children.Add(new TextBlock { Text = "Paroles : LRCLIB", FontSize = 10, Foreground = new SolidColorBrush(Color.FromArgb(105, 255, 255, 255)), Margin = new Thickness(0, 8, 0, 0) });
        Content = stack;

        _search.Click += async (_, _) => await RunSearchAsync();
        _revert.Activated = Revert;
        _revert.MouseLeftButtonUp += (_, _) => Revert();
        A11y.Name(this, "Mauvaises paroles ? Chercher une autre version");
        A11y.Name(_title, "Titre à chercher"); A11y.Name(_artist, "Artiste à chercher"); A11y.Name(_search, "Chercher");
        A11y.Name(_status, "État de la recherche"); A11y.Name(_results, "Résultats de la recherche"); A11y.Name(close, "Fermer la recherche");
        A11y.Name(_revert, "Revenir au choix automatique");
    }

    /// <summary>À l'ouverture : champs préremplis avec le titre en cours, résultats vidés.</summary>
    public void Prepare()
    {
        if (_model.Track is { } t) { _title.Text = t.Title; _artist.Text = t.Artist; }
        _results.Children.Clear(); _status.Text = ""; _chosenId = _model.Lyrics?.LrclibId;
        RefreshRevert();
        _title.Focus();
    }

    private void RefreshRevert() => _revert.Visibility = _model.IsManualChoice ? Visibility.Visible : Visibility.Collapsed;

    private async Task RunSearchAsync()
    {
        if (_busy) return;
        _busy = true; _search.IsEnabled = false; _status.Text = "Recherche…"; SearchCount++;
        try
        {
            var outcome = await _model.SearchVersionsAsync(_title.Text, _artist.Text);
            _results.Children.Clear();
            switch (outcome)
            {
                case ManualSearchOutcome.Results r:
                    foreach (var c in r.Candidates) _results.Children.Add(Row(c));
                    _status.Text = r.Candidates.Count == 0 ? NoResult : "";
                    break;
                case ManualSearchOutcome.Failed f: _status.Text = f.Message; break;
            }
        }
        finally { _busy = false; _search.IsEnabled = true; }
    }

    public static string DurationText(double? d)
    {
        if (d is not double v || v <= 0) return "—";
        var s = (int)Math.Round(v, MidpointRounding.AwayFromZero);
        return $"{s / 60}:{s % 60:00}";
    }

    private UIElement Row(ManualCandidate c)
    {
        var badgeText = c.Instrumental ? "instrumental" : c.Synced ? "synchronisées" : "texte seul";
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel();
        left.Children.Add(new TextBlock { Text = c.Title, FontSize = 12.5, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White, TextTrimming = TextTrimming.CharacterEllipsis });
        left.Children.Add(new TextBlock { Text = string.Join(" · ", new[] { c.Artist, c.Album ?? "" }.Where(x => x.Length > 0)), FontSize = 11, Foreground = new SolidColorBrush(Color.FromArgb(160, 255, 255, 255)), TextTrimming = TextTrimming.CharacterEllipsis });
        var dur = new TextBlock { Text = DurationText(c.Duration), FontSize = 11, Foreground = new SolidColorBrush(Color.FromArgb(160, 255, 255, 255)), Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        var badge = new Border { CornerRadius = new CornerRadius(9), Padding = new Thickness(7, 2, 7, 2), VerticalAlignment = VerticalAlignment.Center, Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            Child = new TextBlock { Text = badgeText, FontSize = 10, FontWeight = FontWeights.SemiBold, Foreground = c.Synced ? new SolidColorBrush(Color.FromRgb(140, 242, 166)) : new SolidColorBrush(Color.FromArgb(180, 255, 255, 255)) } };
        Grid.SetColumn(left, 0); Grid.SetColumn(dur, 1); Grid.SetColumn(badge, 2);
        grid.Children.Add(left); grid.Children.Add(dur); grid.Children.Add(badge);
        var item = new ClickableBorder
        {
            Child = grid, CornerRadius = new CornerRadius(8), Padding = new Thickness(10, 6, 10, 6), Margin = new Thickness(0, 0, 0, 4), Cursor = Cursors.Hand,
            Background = new SolidColorBrush(c.Id == _chosenId ? Color.FromArgb(90, 10, 132, 255) : Color.FromArgb(18, 255, 255, 255)),
        };
        item.Activated = () => Choose(c, item);
        item.MouseLeftButtonUp += (_, _) => Choose(c, item);
        A11y.Name(item, $"{c.Title}, {c.Artist}, {DurationText(c.Duration)}, {(c.Synced ? "synchronisées" : "texte seul")}");
        return item;
    }

    private void Choose(ManualCandidate c, ClickableBorder row)
    {
        var ok = _model.ChooseVersion(c.Id);
        if (ok) { _chosenId = c.Id; }
        _status.Text = ok ? Chosen : Gone;
        RefreshRevert();
        if (!ok) return;
        foreach (var child in _results.Children.OfType<ClickableBorder>()) child.Background = new SolidColorBrush(Color.FromArgb(18, 255, 255, 255));
        row.Background = new SolidColorBrush(Color.FromArgb(90, 10, 132, 255));
    }

    private void Revert()
    {
        _model.RevertToAutomatic();
        _chosenId = null;
        _status.Text = Reverted;
        RefreshRevert();
    }
}
