using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using LyraLyrics.App.Services;
using LyraLyrics.Core;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Volet de réglages : fenêtre Windows normale (clair, contrôles natifs) plutôt que le volet de verre du Mac, pour la robustesse
/// d'un premier essai (écart assumé). Chaque réglage s'applique tout de suite et se garde dans settings.json.
/// </summary>
internal sealed class SettingsWindow : Window
{
    private readonly SettingsStore _store;
    private readonly AppModel _model;
    private bool _loading;
    private readonly RadioButton[] _styleRadios = new RadioButton[3];
    private readonly RadioButton[] _lineRadios = new RadioButton[3];
    private readonly Slider _size = new() { Minimum = Settings.SizeMin, Maximum = Settings.SizeMax, TickFrequency = 1, IsSnapToTickEnabled = true, MinWidth = 180 };
    private readonly Slider _opacity = new() { Minimum = Settings.OpacityMin, Maximum = Settings.OpacityMax, TickFrequency = 1, IsSnapToTickEnabled = true, MinWidth = 180 };
    private readonly TextBlock _sizeLabel = new(), _opacityLabel = new(), _offsetLabel = new(), _hotKeyLabel = new(), _hotKeyMessage = new() { Foreground = Brushes.Firebrick, TextWrapping = TextWrapping.Wrap };
    private readonly ComboBox _font = new(), _weight = new(), _theme = new();
    private readonly CheckBox _artwork = new() { Content = "Couleurs de la pochette" };
    private readonly CheckBox _clickThrough = new() { Content = "Clic-à-travers (la souris traverse la fenêtre)" };
    // Scène plein écran (W6c+d)
    private readonly ComboBox _sceneScreen = new();
    private readonly RadioButton[] _layoutRadios = new RadioButton[2];
    private static readonly SceneLayoutMode[] LayoutChoices = { SceneLayoutMode.WithArtwork, SceneLayoutMode.LyricsOnly };
    private readonly CheckBox _sceneEffects = new() { Content = "Grain et vignette" };
    private readonly CheckBox _karaoke = new() { Content = "Remplissage karaoké" };
    private readonly CheckBox _animatedBackground = new() { Content = "Fond animé" };
    private List<string> _screenNames = new();
    private string _screenListKey = "";
    private readonly CheckBox _startup = new() { Content = "Lancer au démarrage de Windows" };
    private readonly CheckBox _backdrop = new() { Content = "Flou du système (Windows 11, expérimental)" };
    private readonly ClickableBorder[] _swatches = new ClickableBorder[Settings.Swatches.Length];
    private static readonly string[] SwatchNames = { "blanc", "jaune", "bleu clair", "rose", "vert clair" };
    private readonly Button _recordButton = new() { Content = "Modifier…", Padding = new Thickness(12, 3, 12, 3), Margin = new Thickness(10, 0, 0, 0) };
    private bool _recording;
    private readonly ComboBox _autoHide = new();
    private static readonly (AutoHideMode Mode, string Label)[] AutoHideChoices = { (AutoHideMode.Never, "Jamais"), (AutoHideMode.Paused, "En pause"), (AutoHideMode.Idle, "Quand rien ne joue") };
    private readonly CheckBox _checkUpdates = new() { Content = "Vérifier les mises à jour" };
    private readonly TextBlock _updateText = new() { FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
    private readonly Button _updateButton = new() { Content = "Télécharger", Padding = new Thickness(12, 3, 12, 3), Margin = new Thickness(10, 0, 0, 0) };
    private readonly StackPanel _updateRow = new() { Orientation = Orientation.Horizontal, Margin = new Thickness(18, 4, 0, 0), Visibility = Visibility.Collapsed };
    private readonly TextBlock _manualNote = new() { FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap };

    public Func<HotKeyCombo, bool>? TryHotKey { get; set; }
    public string? HotKeyError { get; set; }
    public Action? ResetSize { get; set; }
    public Action? OpenAbout { get; set; }
    public Action? OpenManualSearch { get; set; }
    public Action? OpenWelcome { get; set; }
    public Action? OpenUpdate { get; set; }
    public Action? OpenScene { get; set; }

    public SettingsWindow(SettingsStore store, AppModel model)
    {
        Icon = LyraLyrics.App.Services.AppIcon.Wpf;
        _store = store; _model = model;
        Title = AppIdentity.DisplayName + " : réglages";
        Width = 440; SizeToContent = SizeToContent.Height; MaxHeight = SystemParameters.WorkArea.Height * 0.95;
        ResizeMode = ResizeMode.NoResize; WindowStartupLocation = WindowStartupLocation.CenterScreen; ShowInTaskbar = true; Topmost = true;
        var scroll = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var panel = new StackPanel { Margin = new Thickness(20, 16, 20, 16) };
        scroll.Content = panel;
        Content = scroll;

        // Style
        panel.Children.Add(Header("Fond"));
        var styleRow = new StackPanel { Orientation = Orientation.Horizontal };
        var styles = new[] { BackgroundStyle.Solid, BackgroundStyle.Glass, BackgroundStyle.Clear };
        for (var i = 0; i < 3; i++)
        {
            var style = styles[i];
            var r = new RadioButton { Content = style.Label(), GroupName = "style", Margin = new Thickness(0, 0, 18, 0) };
            A11y.Name(r, "Style du fond : " + style.Label());
            r.Checked += (_, _) => { if (!_loading) _store.Update(s => s.Style = style); };
            _styleRadios[i] = r; styleRow.Children.Add(r);
        }
        panel.Children.Add(styleRow);
        panel.Children.Add(Row("Opacité du fond", _opacity, _opacityLabel));
        _opacity.ValueChanged += (_, _) => { if (!_loading) _store.Update(s => s.BackgroundOpacity = (int)_opacity.Value); };

        // Texte
        panel.Children.Add(Header("Texte"));
        panel.Children.Add(Row("Taille max", _size, _sizeLabel));
        _size.ValueChanged += (_, _) => { if (!_loading) _store.Update(s => s.Size = (int)_size.Value); };
        foreach (var t in FontThemeExt.Ready.Append(FontTheme.Custom)) _theme.Items.Add(t.Label());
        _theme.SelectionChanged += (_, _) =>
        {
            if (_loading || _theme.SelectedIndex < 0) return;
            var theme = _theme.SelectedIndex < FontThemeExt.Ready.Length ? FontThemeExt.Ready[_theme.SelectedIndex] : FontTheme.Custom;
            if (theme != FontTheme.Custom) _store.Update(s => s.Apply(theme));
        };
        panel.Children.Add(Row("Thème de police", _theme));
        foreach (var f in Enum.GetValues<LyricFont>()) _font.Items.Add(f.Label());
        _font.SelectionChanged += (_, _) => { if (!_loading && _font.SelectedIndex >= 0) _store.Update(s => s.Font = (LyricFont)_font.SelectedIndex); };
        panel.Children.Add(Row("Police", _font));
        foreach (var w in Enum.GetValues<LyricWeight>()) _weight.Items.Add(w.Label());
        _weight.SelectionChanged += (_, _) => { if (!_loading && _weight.SelectedIndex >= 0) _store.Update(s => s.FontWeight = (LyricWeight)_weight.SelectedIndex); };
        panel.Children.Add(Row("Graisse", _weight));

        var colors = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 0; i < Settings.Swatches.Length; i++)
        {
            var index = i;
            var sw = new ClickableBorder
            {
                Width = 24, Height = 24, CornerRadius = new CornerRadius(12), Margin = new Thickness(0, 0, 8, 0), Cursor = Cursors.Hand,
                Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(Settings.Swatches[i])), BorderThickness = new Thickness(2), BorderBrush = Brushes.Transparent,
            };
            sw.Activated = () => _store.Update(s => s.ColorIndex = index);
            sw.MouseLeftButtonUp += (_, _) => sw.Activated();
            A11y.Name(sw, "Couleur de la ligne courante : " + SwatchNames[Math.Min(i, SwatchNames.Length - 1)]);
            _swatches[i] = sw; colors.Children.Add(sw);
        }
        panel.Children.Add(Row("Couleur de la ligne courante", colors));
        _artwork.Checked += (_, _) => ArtworkChanged(); _artwork.Unchecked += (_, _) => ArtworkChanged();
        panel.Children.Add(Pad(_artwork));

        var lineRow = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 0; i < 3; i++)
        {
            var n = LineCount.Allowed[i];
            var r = new RadioButton { Content = n.ToString(), GroupName = "lines", Margin = new Thickness(0, 0, 18, 0) };
            A11y.Name(r, n == 1 ? "1 ligne visible" : n + " lignes visibles");
            r.Checked += (_, _) => { if (!_loading) _store.Update(s => s.LineCountValue = n); };
            _lineRadios[i] = r; lineRow.Children.Add(r);
        }
        panel.Children.Add(Row("Lignes visibles", lineRow));

        // Scène plein écran (mêmes réglages et mêmes textes que le Mac)
        panel.Children.Add(Header("Scène plein écran"));
        var openScene = new Button { Content = "Ouvrir la Scène", Padding = new Thickness(12, 3, 12, 3), HorizontalAlignment = HorizontalAlignment.Left };
        openScene.Click += (_, _) => OpenScene?.Invoke();
        panel.Children.Add(openScene);
        panel.Children.Add(Note("Double-clic sur la fenêtre pour y entrer ; Échap, double-clic ou le bouton en haut à droite pour en sortir. Espace : lecture/pause ; ← → : précédent/suivant.", new Thickness(0, 4, 0, 0)));
        _sceneScreen.SelectionChanged += (_, _) => SceneScreenPicked();
        panel.Children.Add(Row("Écran", _sceneScreen));
        var layoutRow = new StackPanel { Orientation = Orientation.Horizontal };
        for (var i = 0; i < LayoutChoices.Length; i++)
        {
            var mode = LayoutChoices[i];
            var label = mode == SceneLayoutMode.WithArtwork ? "Avec la pochette" : "Paroles seules";
            var r = new RadioButton { Content = label, GroupName = "sceneLayout", Margin = new Thickness(0, 0, 18, 0) };
            A11y.Name(r, "Mise en page de la Scène : " + label);
            r.Checked += (_, _) => { if (!_loading) _store.Update(s => s.SceneLayout = mode); };
            _layoutRadios[i] = r; layoutRow.Children.Add(r);
        }
        panel.Children.Add(Row("Mise en page", layoutRow));
        _sceneEffects.Checked += (_, _) => SceneEffectsChanged(); _sceneEffects.Unchecked += (_, _) => SceneEffectsChanged();
        panel.Children.Add(Pad(_sceneEffects));
        _animatedBackground.Checked += (_, _) => AnimatedChanged(); _animatedBackground.Unchecked += (_, _) => AnimatedChanged();
        panel.Children.Add(Pad(_animatedBackground));
        panel.Children.Add(Note("La pochette, très floue, dérive lentement derrière les paroles (si « Couleurs de la pochette » est actif).", new Thickness(18, 0, 0, 0)));
        _karaoke.Checked += (_, _) => KaraokeChanged(); _karaoke.Unchecked += (_, _) => KaraokeChanged();
        panel.Children.Add(Pad(_karaoke));
        panel.Children.Add(Note("La ligne courante se remplit de gauche à droite pendant qu'elle est chantée.", new Thickness(18, 0, 0, 0)));

        // Fenêtre
        panel.Children.Add(Header("Fenêtre"));
        _clickThrough.Checked += (_, _) => ClickThroughChanged(); _clickThrough.Unchecked += (_, _) => ClickThroughChanged();
        panel.Children.Add(Pad(_clickThrough));
        var hot = new StackPanel { Orientation = Orientation.Horizontal };
        hot.Children.Add(_hotKeyLabel); hot.Children.Add(_recordButton);
        _recordButton.Click += (_, _) => StartRecording();
        panel.Children.Add(Row("Raccourci cacher / montrer", hot));
        panel.Children.Add(_hotKeyMessage);
        var resetSize = new Button { Content = "Taille par défaut (460 × 190)", Padding = new Thickness(12, 3, 12, 3), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 6, 0, 0) };
        resetSize.Click += (_, _) => ResetSize?.Invoke();
        panel.Children.Add(resetSize);
        _startup.Checked += (_, _) => StartupChanged(); _startup.Unchecked += (_, _) => StartupChanged();
        panel.Children.Add(Pad(_startup));
        _backdrop.Checked += (_, _) => BackdropChanged(); _backdrop.Unchecked += (_, _) => BackdropChanged();
        panel.Children.Add(Pad(_backdrop));
        panel.Children.Add(new TextBlock { Text = "Le flou du système recrée la fenêtre ; si elle devient noire ou invisible, décoche l'option (menu de l'icône de notification).", FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap });

        foreach (var c in AutoHideChoices) _autoHide.Items.Add(c.Label);
        _autoHide.SelectionChanged += (_, _) => { if (!_loading && _autoHide.SelectedIndex >= 0) { var mode = AutoHideChoices[_autoHide.SelectedIndex].Mode; _store.Update(s => s.AutoHide = mode); } };
        panel.Children.Add(Row("Masquer la fenêtre", _autoHide));
        panel.Children.Add(new TextBlock { Text = "Se cache en douceur, et revient seule. Un masquage ou un affichage fait par toi n'est jamais annulé.", FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap });

        // Synchro
        panel.Children.Add(Header("Synchronisation (titre en cours)"));
        var offsetRow = new StackPanel { Orientation = Orientation.Horizontal };
        var minus = new Button { Content = "−0,1 s", Padding = new Thickness(10, 3, 10, 3) };
        var plus = new Button { Content = "+0,1 s", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 0, 0) };
        var zero = new Button { Content = "0", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(6, 0, 10, 0) };
        minus.Click += (_, _) => { _model.AdjustOffset(-SyncEngine.OffsetStep); UpdateOffsetLabel(); };
        plus.Click += (_, _) => { _model.AdjustOffset(SyncEngine.OffsetStep); UpdateOffsetLabel(); };
        zero.Click += (_, _) => { _model.SetManualOffset(0); UpdateOffsetLabel(); };
        offsetRow.Children.Add(minus); offsetRow.Children.Add(plus); offsetRow.Children.Add(zero); offsetRow.Children.Add(_offsetLabel);
        panel.Children.Add(Row("Décalage", offsetRow));

        // Données
        panel.Children.Add(Header("Données"));
        var cacheRow = new StackPanel { Orientation = Orientation.Horizontal };
        var cacheMessage = new TextBlock { Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Foreground = Brushes.Gray };
        var clear = new Button { Content = "Vider le cache", Padding = new Thickness(12, 3, 12, 3) };
        clear.Click += (_, _) => { _model.ClearCache(); cacheMessage.Text = "Cache vidé"; };
        cacheRow.Children.Add(clear); cacheRow.Children.Add(cacheMessage);
        panel.Children.Add(cacheRow);
        panel.Children.Add(new TextBlock { Text = "Le cache ne garde jamais de paroles : seulement l'identifiant LRCLIB de chaque titre déjà cherché, 24 h.", FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 0) });
        var manual = new Button { Content = "Mauvaises paroles ?", Padding = new Thickness(12, 3, 12, 3), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 12, 0, 0) };
        manual.Click += (_, _) => OpenManualSearch?.Invoke();
        manual.IsEnabled = _model.Track is not null;
        panel.Children.Add(manual);
        panel.Children.Add(_manualNote);

        // Mises à jour
        panel.Children.Add(Header("Mises à jour"));
        _checkUpdates.Checked += (_, _) => { if (!_loading) _store.Update(s => s.CheckUpdates = true); };
        _checkUpdates.Unchecked += (_, _) => { if (!_loading) _store.Update(s => s.CheckUpdates = false); };
        panel.Children.Add(_checkUpdates);
        panel.Children.Add(new TextBlock { Text = "Une requête par jour au plus vers github.com (api.github.com), sans rien envoyer de toi.", FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(18, 2, 0, 0) });
        _updateRow.Children.Add(_updateText); _updateRow.Children.Add(_updateButton);
        _updateButton.Click += (_, _) => OpenUpdate?.Invoke();
        panel.Children.Add(_updateRow);
        var welcome = new Button { Content = "Bienvenue…", Padding = new Thickness(12, 3, 12, 3), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 14, 0, 0) };
        welcome.Click += (_, _) => OpenWelcome?.Invoke();
        panel.Children.Add(welcome);
        var about = new Button { Content = "À propos et droits…", Padding = new Thickness(12, 3, 12, 3), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 14, 0, 0) };
        about.Click += (_, _) => OpenAbout?.Invoke();
        panel.Children.Add(about);

        // Accessibilité : un nom français pour chaque contrôle (les libellés voisins ne sont pas lus comme étiquettes des curseurs et listes).
        A11y.Name(_opacity, "Opacité du fond, en pour cent"); A11y.Name(_size, "Taille maximale du texte, en points");
        A11y.Name(_theme, "Thème de police"); A11y.Name(_font, "Police"); A11y.Name(_weight, "Graisse de la police");
        A11y.Name(_artwork, "Couleurs de la pochette"); A11y.Name(_clickThrough, "Clic-à-travers : la souris traverse la fenêtre");
        A11y.Name(_startup, "Lancer au démarrage de Windows"); A11y.Name(_backdrop, "Flou du système, Windows 11, expérimental");
        A11y.Name(_recordButton, "Modifier le raccourci cacher ou montrer", "Puis appuie sur la nouvelle combinaison de touches");
        A11y.Name(_hotKeyLabel, "Raccourci actuel"); A11y.Name(_hotKeyMessage, "Message sur le raccourci"); A11y.Name(_offsetLabel, "Décalage actuel");
        A11y.Name(resetSize, "Remettre la taille par défaut de la fenêtre"); A11y.Name(minus, "Avancer les paroles : moins 0,1 seconde");
        A11y.Name(plus, "Retarder les paroles : plus 0,1 seconde"); A11y.Name(zero, "Remettre le décalage à zéro");
        A11y.Name(_autoHide, "Masquer la fenêtre : jamais, en pause, ou quand rien ne joue");
        A11y.Name(manual, "Mauvaises paroles ? Chercher une autre version"); A11y.Name(_manualNote, "Version des paroles");
        A11y.Name(_checkUpdates, "Vérifier les mises à jour, une requête par jour au plus");
        A11y.Name(_updateText, "Nouvelle version disponible"); A11y.Name(_updateButton, "Télécharger la nouvelle version : ouvre sa page sur GitHub");
        A11y.Name(welcome, "Rouvrir l'écran de bienvenue");
        A11y.Name(clear, "Vider le cache des paroles"); A11y.Name(about, "Ouvrir À propos et droits"); A11y.Name(cacheMessage, "Résultat");
        A11y.Name(_sceneScreen, "Écran de la Scène : écran de la fenêtre, écran principal, ou un écran par son nom");
        A11y.Name(_sceneEffects, "Grain et vignette de la Scène"); A11y.Name(_animatedBackground, "Fond animé : la pochette floue dérive derrière les paroles");
        A11y.Name(_karaoke, "Remplissage karaoké : la ligne courante se remplit de gauche à droite"); A11y.Name(openScene, "Ouvrir la Scène plein écran");
        A11y.Name(this, AppIdentity.DisplayName + " : réglages");

        PreviewKeyDown += OnPreviewKeyDown;
        _store.Changed += LoadFromSettings;
        Closed += (_, _) => _store.Changed -= LoadFromSettings;
        Loaded += (_, _) => { LoadFromSettings(); UpdateOffsetLabel(); };
    }

    private static TextBlock Note(string text, Thickness margin) => new() { Text = text, FontSize = 11, Foreground = Brushes.Gray, TextWrapping = TextWrapping.Wrap, Margin = margin };
    private static TextBlock Header(string text) => new() { Text = text, FontWeight = FontWeights.Bold, FontSize = 14, Margin = new Thickness(0, 16, 0, 6) };
    private static FrameworkElement Pad(FrameworkElement e) { e.Margin = new Thickness(0, 6, 0, 2); return e; }

    private static FrameworkElement Row(string label, UIElement control, TextBlock? valueLabel = null)
    {
        var g = new Grid { Margin = new Thickness(0, 5, 0, 5) };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var l = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap };
        Grid.SetColumn(l, 0); Grid.SetColumn(control, 1);
        g.Children.Add(l); g.Children.Add(control);
        if (valueLabel is not null)
        {
            valueLabel.VerticalAlignment = VerticalAlignment.Center; valueLabel.Margin = new Thickness(8, 0, 0, 0); valueLabel.MinWidth = 40;
            Grid.SetColumn(valueLabel, 2); g.Children.Add(valueLabel);
        }
        return g;
    }

    private void LoadFromSettings()
    {
        var s = _store.Current;
        _loading = true;
        try
        {
            var styles = new[] { BackgroundStyle.Solid, BackgroundStyle.Glass, BackgroundStyle.Clear };
            for (var i = 0; i < 3; i++) _styleRadios[i].IsChecked = styles[i] == s.Style;
            _opacity.Value = s.BackgroundOpacity; _opacityLabel.Text = s.BackgroundOpacity + " %";
            _size.Value = s.Size; _sizeLabel.Text = s.Size + " pt";
            _font.SelectedIndex = (int)s.Font; _weight.SelectedIndex = (int)s.FontWeight;
            _theme.SelectedIndex = s.Theme == FontTheme.Custom ? _theme.Items.Count - 1 : Array.IndexOf(FontThemeExt.Ready, s.Theme);
            for (var i = 0; i < _swatches.Length; i++) _swatches[i].BorderBrush = i == s.ColorIndex ? Brushes.DodgerBlue : Brushes.Transparent;
            _artwork.IsChecked = s.ArtworkColors;
            for (var i = 0; i < 3; i++) _lineRadios[i].IsChecked = LineCount.Allowed[i] == s.LineCountValue;
            _clickThrough.IsChecked = s.ClickThrough;
            _hotKeyLabel.Text = s.HotKey.Display;
            _startup.IsChecked = StartupRegistration.IsEnabled;
            _autoHide.SelectedIndex = Array.FindIndex(AutoHideChoices, c => c.Mode == s.AutoHide);
            _checkUpdates.IsChecked = s.CheckUpdates;
            _manualNote.Text = _model.IsManualChoice ? "Une version choisie par toi est utilisée pour ce titre." : "Cherche une autre version sur LRCLIB si celle-ci ne correspond pas au morceau.";
            RefreshUpdate();
            LoadSceneScreens(s.SceneScreen);
            for (var i = 0; i < LayoutChoices.Length; i++) _layoutRadios[i].IsChecked = LayoutChoices[i] == s.SceneLayout;
            _sceneEffects.IsChecked = s.SceneEffects; _animatedBackground.IsChecked = s.AnimatedBackground; _karaoke.IsChecked = s.KaraokeFill;
            _backdrop.IsChecked = s.SystemBackdrop;
            _backdrop.IsEnabled = Native.SupportsSystemBackdrop;
            if (!Native.SupportsSystemBackdrop) _backdrop.ToolTip = "Nécessite Windows 11 (build 22621 ou plus).";
        }
        finally { _loading = false; }
    }

    /// <summary>Affiche (ou cache) l'avis de nouvelle version et son bouton « Télécharger ».</summary>
    public void RefreshUpdate()
    {
        if (_model.UpdateRelease is { } r) { _updateText.Text = "Nouvelle version disponible : " + r.Tag; _updateRow.Visibility = Visibility.Visible; }
        else _updateRow.Visibility = Visibility.Collapsed;
    }

    private void UpdateOffsetLabel() => _offsetLabel.Text = (_model.ManualOffset >= 0 ? "+" : "−") + Math.Abs(_model.ManualOffset).ToString("0.0") + " s";

    /// <summary>Liste des écrans : « Écran de la fenêtre », « Écran principal », puis chaque écran par son nom ; un nom enregistré mais débranché reste dans la liste.</summary>
    private void LoadSceneScreens(string setting)
    {
        List<string> names;
        try { names = ScreenCatalog.Names().ToList(); } catch { names = new List<string>(); }
        if (setting.StartsWith("name:", StringComparison.Ordinal) && !names.Contains(setting.Substring(5))) names.Add(setting.Substring(5));
        var key = string.Join("\u001F", names);
        if (key != _screenListKey)
        {
            _screenListKey = key; _screenNames = names;
            _sceneScreen.Items.Clear();
            _sceneScreen.Items.Add("Écran de la fenêtre"); _sceneScreen.Items.Add("Écran principal");
            foreach (var n in names) _sceneScreen.Items.Add(n);
        }
        _sceneScreen.SelectedIndex = setting == SceneScreenChoice.Main ? 1 : setting.StartsWith("name:", StringComparison.Ordinal) ? Math.Max(0, _screenNames.IndexOf(setting.Substring(5))) + 2 : 0;
    }

    private void SceneScreenPicked()
    {
        if (_loading || _sceneScreen.SelectedIndex < 0) return;
        var i = _sceneScreen.SelectedIndex;
        var value = i == 0 ? SceneScreenChoice.Window : i == 1 ? SceneScreenChoice.Main : SceneScreenChoice.Named(_screenNames[Math.Min(i - 2, _screenNames.Count - 1)]);
        _store.Update(s => s.SceneScreen = value);
    }
    private void SceneEffectsChanged() { if (!_loading) _store.Update(s => s.SceneEffects = _sceneEffects.IsChecked == true); }
    private void AnimatedChanged() { if (!_loading) _store.Update(s => s.AnimatedBackground = _animatedBackground.IsChecked == true); }
    private void KaraokeChanged() { if (!_loading) _store.Update(s => s.KaraokeFill = _karaoke.IsChecked == true); }

    private void ArtworkChanged() { if (_loading) return; _store.Update(s => s.ArtworkColors = _artwork.IsChecked == true); _model.RefreshPaletteVisibility(); }
    private void ClickThroughChanged()
    {
        if (_loading) return;
        var on = _clickThrough.IsChecked == true;
        _store.Update(s => s.ClickThrough = on);
        if (on) _model.ShowNotice($"Clic-à-travers activé · {_store.Current.HotKey.Display} pour revenir", 4);
    }
    private void StartupChanged()
    {
        if (_loading) return;
        var want = _startup.IsChecked == true;
        if (!StartupRegistration.Set(want)) { _loading = true; _startup.IsChecked = StartupRegistration.IsEnabled; _loading = false; }
    }
    private void BackdropChanged() { if (!_loading) _store.Update(s => s.SystemBackdrop = _backdrop.IsChecked == true); }

    // ---- Saisie du raccourci

    private void StartRecording()
    {
        _recording = true;
        _recordButton.Content = "Appuie sur la combinaison…";
        _hotKeyMessage.Text = "";
        Focus();
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_recording) return;
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return;
        if (key == Key.Escape) { StopRecording(); return; }
        uint mods = 0;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control)) mods |= HotKeyCombo.ModControl;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Alt)) mods |= HotKeyCombo.ModAlt;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift)) mods |= HotKeyCombo.ModShift;
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows)) mods |= HotKeyCombo.ModWin;
        var vk = (uint)KeyInterop.VirtualKeyFromKey(key);
        var label = key switch { >= Key.D0 and <= Key.D9 => ((int)key - (int)Key.D0).ToString(), Key.Space => "Espace", _ => key.ToString() };
        var combo = new HotKeyCombo(mods, vk, label);
        StopRecording();
        if (!combo.IsValid) { _hotKeyMessage.Text = "Combinaison non valide : ajoute Ctrl, Alt ou Win."; return; }
        if (TryHotKey?.Invoke(combo) == true) { _store.Update(s => s.HotKey = combo); _hotKeyMessage.Text = ""; }
        else _hotKeyMessage.Text = HotKeyError ?? "Ce raccourci n'a pas pu être enregistré.";
    }

    private void StopRecording()
    {
        _recording = false;
        _recordButton.Content = "Modifier…";
    }
}
