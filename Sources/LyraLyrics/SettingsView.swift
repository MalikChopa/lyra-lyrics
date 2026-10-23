import AppKit
import SwiftUI
import AppSupport
import LyricsCore
import PlayerKit

struct SettingsActions {
    var setStyle: @MainActor (BackgroundStyle) -> Void
    var setSize: @MainActor (Int) -> Void
    var setOpacity: @MainActor (Int) -> Void
    var setFont: @MainActor (LyricFont) -> Void
    var setWeight: @MainActor (LyricWeight) -> Void
    var setGlow: @MainActor (Bool) -> Void
    var setLineCount: @MainActor (Int) -> Void
    var applyTheme: @MainActor (FontTheme) -> Void
    var resetWindowSize: @MainActor () -> Void
    var setArtworkColors: @MainActor (Bool) -> Void
    var setColor: @MainActor (Int) -> Void
    var setClickThrough: @MainActor (Bool) -> Void
    var setDockIcon: @MainActor (Bool) -> Void
    var adjustOffset: @MainActor (Double) -> Void
    var resetOffset: @MainActor () -> Void
    var clearCache: @MainActor () -> Void
    var resetHotKey: @MainActor () -> Void
    var openAbout: @MainActor () -> Void
    var requestSpotifyAccess: @MainActor () -> Void
    /// Bouton × du volet (1.0.1) : en clic-à-travers, le ⚙ de la barre au survol n'est plus cliquable.
    var closeSettings: @MainActor () -> Void
    /// Volet Automatisation des Réglages Système (autorisation refusée).
    var openAutomationSettings: @MainActor () -> Void
}

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
private let txtMid = Color.white.opacity(0.62)
private let link = Color(red: 0.486, green: 0.753, blue: 1)

/// Volet de réglages (maquette `.panel`), dans un `NSPanel` non activant. Ajouts J3 (décisions utilisateur du 2026-10-22) :
/// case « Icône dans le Dock » (décochée par défaut), décalage manuel par titre, « Vider le cache ».
struct SettingsView: View {
    var model: AppModel
    var store: SettingsStore
    var recorder: ShortcutRecorder
    var actions: SettingsActions

    static let width = 300.0

    /// Le contenu défile (barre de défilement) quand le volet est plus haut que la zone visible : `SettingsPanelController`
    /// fixe la hauteur de la fenêtre à min(contenu, zone visible − marges) ; le fond et les coins arrondis restent en place.
    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topTrailing) {
            // × toujours visible (ne défile pas) ; Échap ferme aussi (`KeyablePanel.onEscape`).
            Button { actions.closeSettings() } label: {
                Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 10).padding(.trailing, 10)
            .help("Fermer les réglages (Échap)")
            .accessibilityLabel("Fermer les réglages")
            .accessibilityIdentifier("settings-close")
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if model.reduceTransparency {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 24 / 255, green: 24 / 255, blue: 32 / 255).opacity(0.97))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
            } else {
                GlassCard(tint: Color(red: 24 / 255, green: 24 / 255, blue: 32 / 255), tintOpacity: 0.55, radius: 20,
                          gradientStart: 0.18, gradientEnd: 0.05, border: 0.2, highlight: 0.3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Réglages")
    }

    static let swatchNames = ["Blanc", "Jaune", "Bleu clair", "Rose", "Vert"]

    private var content: some View {
        let s = store.settings
        return VStack(alignment: .leading, spacing: 0) {
            heading("Style de fond", first: true)
            HStack(spacing: 6) {
                ForEach(BackgroundStyle.allCases, id: \.self) { style in
                    StyleTile(style: style, selected: s.style == style) { actions.setStyle(style) }
                }
            }
            heading("Texte")
            row("Lignes") {
                HStack(spacing: 6) {
                    ForEach(LineCount.allowed, id: \.self) { n in
                        PillButton(label: "\(n)", selected: s.lineCount == n, accessibility: "\(n) ligne\(n > 1 ? "s" : "") visible\(n > 1 ? "s" : "")") { actions.setLineCount(n) }
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Thème de police").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.88))
                Spacer(minLength: 0)
                if s.fontTheme == .custom {
                    Text("Personnalisé").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent.opacity(0.95))
                        .accessibilityLabel("Thème de police : personnalisé")
                }
            }.padding(.top, 6).padding(.bottom, 6)
            HStack(spacing: 6) {
                ForEach(FontTheme.ready, id: \.self) { theme in
                    ThemeTile(theme: theme, selected: s.fontTheme == theme) { actions.applyTheme(theme) }
                }
            }.padding(.bottom, 8)
            sliderRow("Taille max", value: Binding(get: { Double(s.size) }, set: { actions.setSize(Int($0.rounded())) }),
                      range: Double(Settings.sizeRange.lowerBound)...Double(Settings.sizeRange.upperBound), text: "\(s.size)")
            sliderRow("Opacité fond", value: Binding(get: { Double(s.backgroundOpacity) }, set: { actions.setOpacity(Int($0.rounded())) }),
                      range: Double(Settings.opacityRange.lowerBound)...Double(Settings.opacityRange.upperBound), text: "\(s.backgroundOpacity)%")
            row("Police") {
                Picker("Police", selection: Binding(get: { s.font }, set: { actions.setFont($0) })) {
                    ForEach(LyricFont.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
            }
            row("Graisse") {
                Picker("Graisse", selection: Binding(get: { s.fontWeight }, set: { actions.setWeight($0) })) {
                    ForEach(LyricWeight.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity)
            }
            row("Couleur") {
                HStack(spacing: 8) {
                    ForEach(Array(Settings.swatches.enumerated()), id: \.offset) { i, hex in
                        Button { actions.setColor(i) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(s.colorIndex == i ? .white : .white.opacity(0.35), lineWidth: 2))
                                .overlay(Circle().strokeBorder(accent, lineWidth: 2).padding(-2).opacity(s.colorIndex == i ? 1 : 0))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Couleur \(Self.swatchNames[min(i, Self.swatchNames.count - 1)])")
                        .accessibilityAddTraits(s.colorIndex == i ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
            }
            Toggle(isOn: Binding(get: { s.glow }, set: { actions.setGlow($0) })) {
                Text("Halo lumineux").font(.system(size: 12.5))
            }
            .toggleStyle(.checkbox).controlSize(.small).padding(.top, 4)
            .accessibilityIdentifier("glow")
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(get: { s.artworkColors }, set: { actions.setArtworkColors($0) })) {
                    Text("Couleurs de la pochette").font(.system(size: 12.5))
                }
                .toggleStyle(.checkbox).controlSize(.small)
                .accessibilityIdentifier("artwork-colors")
                Text("Fond et ligne courante prennent les teintes de la pochette. Avec Spotify, la pochette est téléchargée (une image par titre, gardée en mémoire seulement).")
                    .font(.system(size: 11)).foregroundStyle(txtMid).padding(.leading, 18)
            }.padding(.top, 8)
            HStack(spacing: 10) {
                Button("Taille par défaut") { actions.resetWindowSize() }.buttonStyle(.bordered).controlSize(.small)
                    .disabled(s.manualSize == nil)
                    .accessibilityLabel("Taille par défaut de la fenêtre")
                Spacer(minLength: 0)
            }.padding(.top, 8)
            Text(s.manualSize.map { "Fenêtre : \(Int($0.width)) × \(Int($0.height)) pt. Le texte s'adapte à la fenêtre (jusqu'à « Taille max »). Tire un bord ou un coin pour la redimensionner (inactif en clic-à-travers)." }
                 ?? "Tire un bord ou un coin de la fenêtre pour la redimensionner : le texte s'adapte (jusqu'à « Taille max »). Inactif en clic-à-travers.")
                .font(.system(size: 11)).foregroundStyle(txtMid).fixedSize(horizontal: false, vertical: true)
            heading("Paroles")
            row("Décalage") {
                HStack(spacing: 6) {
                    SmallButton(label: "−0,1") { actions.adjustOffset(-0.1) }
                    Text(Self.offsetText(model.manualOffset)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white).frame(width: 52)
                    SmallButton(label: "+0,1") { actions.adjustOffset(0.1) }
                    if model.manualOffset != 0 {
                        Button("0") { actions.resetOffset() }.accessibilityLabel("Remettre le décalage à zéro").buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(link)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Pour ce titre seulement, de −5 à +5 s (positif : les lignes arrivent plus tôt).")
                .font(.system(size: 11)).foregroundStyle(txtMid).padding(.bottom, 4)
            HStack(spacing: 10) {
                Button("Vider le cache") { actions.clearCache() }.buttonStyle(.bordered).controlSize(.small)
                if let msg = model.cacheMessage { Text(msg).font(.system(size: 11)).foregroundStyle(txtMid) }
                Spacer(minLength: 0)
            }.padding(.vertical, 4)
            Text("Le cache ne garde jamais de paroles : seulement l'identifiant LRCLIB de chaque titre déjà cherché, 24 h.")
                .font(.system(size: 11)).foregroundStyle(txtMid)
            if let access = model.spotifyAccess, access != .granted {
                // 1.0.1 : l'état dit la vérité pour CETTE identité d'app (l'autorisation Automatisation est liée à l'identifiant de bundle).
                // Spotify marche sans autorisation (notification) ; l'accord ajoute la synchro précise et les boutons de lecture.
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.spotifyLine(access)).font(.system(size: 11)).foregroundStyle(txtMid).fixedSize(horizontal: false, vertical: true)
                    switch access {
                    case .notDetermined, .unknown:
                        Button("Autoriser l'accès à Spotify") { actions.requestSpotifyAccess() }.buttonStyle(.bordered).controlSize(.small)
                    case .denied:
                        Button("Ouvrir les Réglages") { actions.openAutomationSettings() }.buttonStyle(.bordered).controlSize(.small)
                    case .notRunning, .granted:
                        EmptyView()
                    }
                }.padding(.top, 10)
            }
            heading("Comportement")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clic-à-travers").font(.system(size: 12.5))
                    Text("Les clics passent à travers la fenêtre. Pour en sortir : \(s.hotKey.display) (ton raccourci), même si l'icône de la barre de menus est cachée (encoche).")
                        .font(.system(size: 11)).foregroundStyle(txtMid).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SwitchToggle(isOn: s.clickThrough, reduceMotion: model.reduceMotion) { actions.setClickThrough(!s.clickThrough) }
            }.padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: Binding(get: { s.showsDockIcon }, set: { actions.setDockIcon($0) })) {
                    Text("Icône dans le Dock").font(.system(size: 12.5))
                }
                .toggleStyle(.checkbox).controlSize(.small)
                .accessibilityIdentifier("dock-icon")
                Text("Avec l'icône, les paroles ne s'affichent plus par-dessus une app en plein écran.")
                    .font(.system(size: 11)).foregroundStyle(txtMid).padding(.leading, 18)
            }.padding(.vertical, 8)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cacher / montrer").font(.system(size: 12.5))
                    Text("Raccourci global (en clic-à-travers : il rend la main)").font(.system(size: 11)).foregroundStyle(txtMid)
                }
                Spacer(minLength: 0)
                ShortcutField(recorder: recorder, combo: s.hotKey)
            }.padding(.vertical, 8)
            if let msg = recorder.message ?? (model.hotKeyAvailable ? nil : model.hotKeyMessage) {
                Text(msg).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.2))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if s.hotKey != defaultHotKey {
                Button("Rétablir le raccourci par défaut") { actions.resetHotKey() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(link)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack {
                Text("Version \(Self.version)")
                Spacer()
                Button { actions.openAbout() } label: { Text("À propos et droits").foregroundStyle(link) }
                    .buttonStyle(.plain)
            }
            .font(.system(size: 11)).foregroundStyle(txtMid).padding(.top, 12)
        }
        .padding(.top, 18).padding(.horizontal, 18).padding(.bottom, 16)
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: true, vertical: true)
        .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { h in
            model.settingsContentHeight = h
            model.onSettingsContentHeight?()
        }
    }

    /// Phrase du volet pour l'état de l'autorisation Automatisation de Spotify.
    static func spotifyLine(_ access: AutomationStatus) -> String {
        switch access {
        case .granted: return "Spotify : autorisé (synchro précise et boutons de lecture)."
        case .notDetermined: return "Spotify : autorisation non demandée. Elle sert à la synchro précise et aux boutons de lecture."
        case .denied: return "Spotify : autorisation refusée. Synchro réduite, boutons de lecture désactivés."
        case .notRunning: return "Spotify : ouvre Spotify pour vérifier l'autorisation."
        case .unknown: return "Spotify : état de l'autorisation inconnu pour l'instant."
        }
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    /// « +1,0 s », « −0,3 s », « 0,0 s » (virgule française).
    static func offsetText(_ v: Double) -> String {
        let s = String(format: v > 0 ? "+%.1f s" : "%.1f s", v).replacingOccurrences(of: ".", with: ",")
        return s.replacingOccurrences(of: "-", with: "−")
    }

    private func heading(_ text: String, first: Bool = false) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.88).foregroundStyle(txtMid)
            .padding(.top, first ? 0 : 14).padding(.bottom, 8)
    }

    private func row<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.88)).frame(width: 78, alignment: .leading)
            content()
        }.padding(.vertical, 4)
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, text: String) -> some View {
        row(label) {
            Slider(value: value, in: range, step: 1).tint(.white.opacity(0.9)).controlSize(.small)
                .accessibilityLabel(label).accessibilityValue(text)
            Text(text).font(.system(size: 11).monospacedDigit()).foregroundStyle(txtMid).frame(width: 34, alignment: .trailing)
        }
    }
}

private struct PillButton: View {
    var label: String
    var selected: Bool
    var accessibility: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .frame(width: 40, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? accent.opacity(0.35) : .white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? accent.opacity(0.95) : .white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Carte d'un thème de police : « Aa » dans la police, la graisse et le halo du thème.
private struct ThemeTile: View {
    var theme: FontTheme
    var selected: Bool
    var action: () -> Void
    var body: some View {
        let spec = theme.spec
        Button(action: action) {
            VStack(spacing: 5) {
                Text("Aa")
                    .font(FontResolver.swiftUIFont(spec?.font ?? .system, size: 19, weight: spec?.weight ?? .bold))
                    .foregroundStyle(Color(hex: Settings.swatches[spec?.colorIndex ?? 0]))
                    .shadow(color: (spec?.glow ?? false) ? Color(hex: Settings.swatches[spec?.colorIndex ?? 0]).opacity(0.9) : .clear, radius: (spec?.glow ?? false) ? 6 : 0)
                    .frame(height: 26)
                Text(theme.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.top, 6).padding(.bottom, 5).padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? accent.opacity(0.35) : .white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? accent.opacity(0.95) : .white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Thème \(theme.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SmallButton: View {
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Décalage \(label)")
    }
}

private struct StyleTile: View {
    var style: BackgroundStyle
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                swatch.frame(height: 26)
                Text(style.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            .padding(.top, 8).padding(.bottom, 6).padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? accent.opacity(0.35) : .white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? accent.opacity(0.95) : .white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Style \(style.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var swatch: some View {
        let r = RoundedRectangle(cornerRadius: 6, style: .continuous)
        switch style {
        case .glass:
            r.fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(r.strokeBorder(.white.opacity(0.4), lineWidth: 1))
        case .solid:
            r.fill(Color(red: 27 / 255, green: 27 / 255, blue: 34 / 255)).overlay(r.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        case .clear:
            Canvas { ctx, size in
                let cell = 5.0
                for ix in 0..<Int((size.width / cell).rounded(.up)) {
                    for iy in 0..<Int((size.height / cell).rounded(.up)) where (ix + iy) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: Double(ix) * cell, y: Double(iy) * cell, width: cell, height: cell)), with: .color(.white.opacity(0.18)))
                    }
                }
            }
            .clipShape(r)
            .overlay(r.strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
    }
}

private struct SwitchToggle: View {
    var isOn: Bool
    var reduceMotion: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Capsule().fill(isOn ? Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255) : .white.opacity(0.25))
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 18, height: 18).shadow(color: .black.opacity(0.35), radius: 1.5, y: 1).padding(2)
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clic-à-travers").accessibilityValue(isOn ? "activé" : "désactivé").accessibilityAddTraits(.isToggle)
    }
}

private struct ShortcutField: View {
    var recorder: ShortcutRecorder
    var combo: HotKeyCombo
    var body: some View {
        Button { recorder.toggle() } label: {
            Text(recorder.isRecording ? "Appuie sur la combinaison…" : spaced(combo.display))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(recorder.isRecording ? accent.opacity(0.35) : .white.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(recorder.isRecording ? accent : .white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Raccourci cacher ou montrer")
    }
    private func spaced(_ s: String) -> String { s.map(String.init).joined(separator: " ") }
}
