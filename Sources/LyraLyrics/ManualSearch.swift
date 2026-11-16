import AppKit
import SwiftUI
import Observation
import AppSupport
import LyricsCore

/// État du panneau « Mauvaises paroles ? » (B1). Les résultats sont des métadonnées (titre, artiste, album, durée, synchro) : jamais de paroles.
@MainActor
@Observable
final class ManualSearchModel {
    var title = ""
    var artist = ""
    var results: [ManualCandidate] = []
    var status: String?
    var busy = false
    var searched = false
    /// Version actuellement utilisée (identifiant LRCLIB), pour la marquer dans la liste.
    var chosenID: Int?
    @ObservationIgnored var searchCount = 0
}

struct ManualSearchView: View {
    var app: AppModel
    var search: ManualSearchModel
    var onSearch: @MainActor () -> Void
    var onChoose: @MainActor (ManualCandidate) -> Void
    var onRevert: @MainActor () -> Void
    var onClose: @MainActor () -> Void
    private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)

    var body: some View {
        @Bindable var s = search
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mauvaises paroles ?").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.14)))
                }.buttonStyle(.plain).accessibilityLabel("Fermer la recherche")
            }
            Text("Cherche une autre version sur LRCLIB et choisis-la : elle sera utilisée tout de suite et retenue pour ce titre.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.62)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Titre", text: $s.title).textFieldStyle(.roundedBorder).accessibilityLabel("Titre à chercher")
                TextField("Artiste", text: $s.artist).textFieldStyle(.roundedBorder).accessibilityLabel("Artiste à chercher")
                Button { onSearch() } label: {
                    Text("Chercher").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(accent))
                }.buttonStyle(.plain).disabled(search.busy).accessibilityLabel("Chercher")
            }
            .onSubmit { onSearch() }
            if let status = search.status {
                Text(status).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(search.results) { r in
                        Button { onChoose(r) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text([r.artist, r.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                                }
                                Spacer(minLength: 6)
                                Text(Self.duration(r.duration)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.62))
                                Text(r.instrumental ? "instrumental" : (r.synced ? "synchro" : "texte"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(r.synced ? Color(red: 0.55, green: 0.95, blue: 0.65) : .white.opacity(0.7))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(.white.opacity(0.12)))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(search.chosenID == r.id ? accent.opacity(0.35) : .white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(r.title), \(r.artist), \(Self.duration(r.duration)), \(r.synced ? "synchronisées" : "texte seul")")
                    }
                }
            }
            .frame(height: 190)
            HStack {
                if app.isManualChoice {
                    Button { onRevert() } label: { Text("Revenir au choix automatique").font(.system(size: 11.5)).foregroundStyle(Color(red: 0.486, green: 0.753, blue: 1)) }
                        .buttonStyle(.plain).accessibilityLabel("Revenir au choix automatique")
                }
                Spacer()
                Text("Paroles : LRCLIB").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(18).frame(width: 470)
        .background {
            if app.reduceTransparency {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 24 / 255, green: 24 / 255, blue: 32 / 255).opacity(0.98))
            } else {
                GlassCard(tint: Color(red: 24 / 255, green: 24 / 255, blue: 32 / 255), tintOpacity: 0.6, radius: 20, gradientStart: 0.18, gradientEnd: 0.05, border: 0.2, highlight: 0.3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mauvaises paroles ?")
    }

    static func duration(_ d: Double?) -> String {
        guard let d, d > 0 else { return "—" }
        let s = Int(d.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

@MainActor
final class ManualSearchController {
    let panel: KeyablePanel
    let search = ManualSearchModel()
    private let model: AppModel
    private let parent: PanelController
    private var host: PanelHostingView<ManualSearchView>!
    var isOpen: Bool { panel.isVisible }

    init(parent: PanelController, model: AppModel) {
        self.parent = parent
        self.model = model
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 420), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        OverlayConfig.apply(to: panel)
        panel.hasShadow = true
        host = PanelHostingView(rootView: ManualSearchView(
            app: model, search: search,
            onSearch: { [unowned self] in self.runSearch() },
            onChoose: { [unowned self] c in self.choose(c) },
            onRevert: { [unowned self] in self.model.revertToAutomatic(); self.search.chosenID = nil; self.search.status = "Choix automatique rétabli." },
            onClose: { [unowned self] in self.close() }))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        panel.onEscape = { [weak self] in self?.close() }
    }

    func open() {
        // Champs préremplis avec le titre en cours (ou gardés si l'utilisateur les avait changés pour ce titre).
        if let t = model.track { search.title = t.title; search.artist = t.artist }
        search.results = []; search.status = nil; search.searched = false
        search.chosenID = model.lyrics?.lrclibID
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        let v = parent.screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.midY - size.height / 2 + 30))
        panel.orderFrontRegardless()
        panel.makeKey()
    }
    func close() { panel.orderOut(nil) }

    func runSearch() {
        guard !search.busy else { return }
        search.busy = true; search.status = "Recherche…"; search.searchCount += 1
        let (t, a) = (search.title, search.artist)
        Task { @MainActor in
            let outcome = await model.searchVersions(title: t, artist: a)
            search.busy = false; search.searched = true
            switch outcome {
            case .results(let list):
                search.results = list
                search.status = list.isEmpty ? "Aucune version trouvée. Essaie un autre titre ou un autre artiste." : nil
            case .failed(let reason):
                search.results = []; search.status = reason
            }
            host.layoutSubtreeIfNeeded()
            panel.setContentSize(host.fittingSize)
        }
    }

    func choose(_ c: ManualCandidate) {
        Task { @MainActor in
            let ok = await model.chooseVersion(id: c.id)
            search.chosenID = ok ? c.id : search.chosenID
            search.status = ok ? "Version choisie, retenue pour ce titre." : "Cette version n'est plus disponible : relance la recherche."
        }
    }
}
