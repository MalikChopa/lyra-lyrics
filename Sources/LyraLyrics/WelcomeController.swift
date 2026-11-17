import AppKit
import SwiftUI
import AppSupport
import LyricsCore

/// Accueil du premier lancement (A1) : un petit panneau non activant avec 3 cartes, « Autoriser Spotify » (l'invite du système ne
/// vient QUE de ce clic) et « Commencer ». Montré une seule fois ; rouvrable par le menu « Bienvenue… ».
struct WelcomeActions {
    var allowSpotify: @MainActor () -> Void
    var start: @MainActor () -> Void
}

struct WelcomeView: View {
    var model: AppModel
    var hotKey: String
    var actions: WelcomeActions

    private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bienvenue dans \(AppIdentity.displayName)").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            Text("Les paroles de ton morceau, dans une petite fenêtre toujours au-dessus.").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7))
            card("1", "Lance un titre dans Spotify", "Les paroles apparaissent en quelques secondes.")
            card("2", "Survole la fenêtre", "Les boutons de lecture, le style ◐ et les réglages ⚙ apparaissent.")
            card("3", "\(hotKey) : clic-à-travers", "Active ou coupe le clic-à-travers (et montre la fenêtre si elle est cachée), même si l'icône de la barre de menus est cachée. Pour cacher la fenêtre : menu de la barre de menus.")
            HStack(spacing: 10) {
                Button { actions.allowSpotify() } label: {
                    Text(model.spotifyAccess == .granted ? "Spotify autorisé" : "Autoriser Spotify")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                .buttonStyle(.plain).disabled(model.spotifyAccess == .granted)
                .accessibilityLabel("Autoriser Spotify")
                Spacer(minLength: 0)
                Button { actions.start() } label: {
                    Text("Commencer").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 6).background(Capsule().fill(accent))
                }
                .buttonStyle(.plain).accessibilityLabel("Commencer")
            }
            Text("L'autorisation sert à la synchro précise et aux boutons de lecture ; elle n'est demandée que par ce bouton. Les paroles s'affichent sans elle.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 380)
        .background {
            if model.reduceTransparency {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 24 / 255, green: 24 / 255, blue: 32 / 255).opacity(0.98))
            } else {
                GlassCard(tint: Color(red: 24 / 255, green: 24 / 255, blue: 32 / 255), tintOpacity: 0.6, radius: 20, gradientStart: 0.18, gradientEnd: 0.05, border: 0.2, highlight: 0.3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bienvenue")
    }

    private func card(_ n: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22)
                .background(Circle().fill(accent.opacity(0.55)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(body).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.68)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}

@MainActor
final class WelcomeController {
    let panel: KeyablePanel
    private let host: PanelHostingView<WelcomeView>
    private let parent: PanelController
    private(set) var openCount = 0
    var isOpen: Bool { panel.isVisible }

    init(parent: PanelController, model: AppModel, hotKey: @escaping @MainActor () -> String, actions: WelcomeActions) {
        self.parent = parent
        host = PanelHostingView(rootView: WelcomeView(model: model, hotKey: hotKey(), actions: actions))
        host.sizingOptions = [.intrinsicContentSize]
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 360), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        OverlayConfig.apply(to: panel)
        panel.hasShadow = true
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.close() }
        refreshHotKey = { [weak host] in host?.rootView = WelcomeView(model: model, hotKey: hotKey(), actions: actions) }
    }
    private var refreshHotKey: (() -> Void)?

    func open() {
        refreshHotKey?()
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        let v = parent.screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2 + 40))
        panel.orderFrontRegardless()
        panel.makeKey()
        openCount += 1
    }
    func close() { panel.orderOut(nil) }
}
