using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Media;

namespace LyraLyrics.App.Ui;

/// <summary>
/// Accessibilité (parité ligne 32 de l'audit) : les « boutons » dessinés à la main (Border, TextBlock) n'ont pas de pair d'automatisation ;
/// ces deux classes en donnent un (type Bouton / Lien, modèle Invoke) pour que Narrator et les lecteurs d'écran les voient et les actionnent.
/// Non vérifié sur Windows : si Narrator ne lit pas la barre, ouvrir « Inspect » (Windows SDK) et regarder l'arbre UIA de la fenêtre.
/// </summary>
internal static class A11y
{
    public static void Name(DependencyObject o, string name, string? help = null)
    {
        AutomationProperties.SetName(o, name);
        if (help is not null) AutomationProperties.SetHelpText(o, help);
    }
}

/// <summary>Bouton dessiné à la main : <see cref="Activated"/> est appelé par la souris (code de la fenêtre) ET par UI Automation (Invoke).</summary>
internal sealed class ClickableBorder : Border
{
    public Action? Activated { get; set; }
    protected override AutomationPeer OnCreateAutomationPeer() => new Peer(this);

    private sealed class Peer : FrameworkElementAutomationPeer, IInvokeProvider
    {
        private readonly ClickableBorder _owner;
        public Peer(ClickableBorder owner) : base(owner) { _owner = owner; }
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Button;
        protected override string GetClassNameCore() => "Button";
        /// <summary>Le glyphe de police d'icônes à l'intérieur n'est pas lu : le bouton porte déjà son nom.</summary>
        protected override List<AutomationPeer>? GetChildrenCore() => null;
        public override object? GetPattern(PatternInterface patternInterface) => patternInterface == PatternInterface.Invoke ? this : base.GetPattern(patternInterface);
        public void Invoke() => _owner.Dispatcher.BeginInvoke(() => _owner.Activated?.Invoke());
    }
}

/// <summary>Texte cliquable (lien « À propos et droits ») exposé comme lien invocable.</summary>
internal sealed class ClickableText : TextBlock
{
    public Action? Activated { get; set; }
    protected override AutomationPeer OnCreateAutomationPeer() => new Peer(this);

    private sealed class Peer : TextBlockAutomationPeer, IInvokeProvider
    {
        private readonly ClickableText _owner;
        public Peer(ClickableText owner) : base(owner) { _owner = owner; }
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Hyperlink;
        public override object? GetPattern(PatternInterface patternInterface) => patternInterface == PatternInterface.Invoke ? this : base.GetPattern(patternInterface);
        public void Invoke() => _owner.Dispatcher.BeginInvoke(() => _owner.Activated?.Invoke());
    }
}
