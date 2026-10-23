#if DEBUG
import AppKit
import SwiftUI
import AppSupport

/// `--snapshot <dossier>` (DEBUG uniquement) : rend les vues de l'app elle-même en PNG (3 styles, volet, états, À propos,
/// lignes longues) sur un faux bureau dessiné par nous (celui de la maquette). Aucune capture d'écran : rien d'un autre processus.
/// LIMITES : le flou du verre (`NSVisualEffectView`) est fait par le Window Server et n'apparaît PAS dans `cacheDisplay` ;
/// l'ombre portée de la fenêtre non plus. Le Verre montré = teinte + dégradé + bordure, sans le flou de ce qui est derrière.
@MainActor
final class SnapshotRunner {
    private let c: AppController
    private var dir = ""
    static let canvas = NSSize(width: 1200, height: 1100)

    init(controller: AppController) { c = controller }

    func run(directory: String) {
        let resolved = URL(fileURLWithPath: directory).standardizedFileURL.path
        guard resolved.hasPrefix("/tmp/") || resolved.hasPrefix("/private/tmp/") else {
            DiagLog.shared.write(["snapshot": "refus", "raison": "dossier hors /tmp : les captures ne vont jamais dans le projet"]); exit(2)
        }
        dir = resolved
        SnapshotFlags.skipBlur = true
        LineStackView.snapshotMode = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            await self.all()
            DiagLog.shared.write(["snapshot": "fin", "dossier": self.dir])
            exit(0)
        }
    }

    private func settle(_ ms: Int = 500) async { try? await Task.sleep(for: .milliseconds(ms)) }

    /// J5 : un PNG par état du §3.6 (nommés `etat-NN-nom`), atteints par scénario du faux lecteur (comme `Fixtures/selftests/etats.txt`).
    private func states() async {
        guard let fp = c.fakePlayer else { return }
        c.change { $0.style = .glass; $0.size = 26; $0.backgroundOpacity = 38 }
        func wait(_ mode: DisplayMode, _ seconds: Double) async {
            var t = 0.0
            while c.model.mode != mode && t < seconds { try? await Task.sleep(for: .milliseconds(100)); t += 0.1 }
            await settle(400)
        }
        await settle(300)
        await shot("etat-01-rien", bright: false, panels: [.main])
        fp.perform("play", track: "lenteur"); await settle(2200)
        await shot("etat-02-recherche", bright: false, panels: [.main])
        fp.perform("play", track: "phares"); fp.perform("seek", track: "3.0"); await wait(.synced, 8); fp.perform("pause"); await settle(500)
        c.model.hovering = true; await settle(300)
        await shot("etat-03-synchronisees-survol", bright: false, panels: [.main])
        c.model.hovering = false
        fp.perform("play", track: "brume"); await wait(.unsynced, 8)
        await shot("etat-04-non-synchronisees", bright: false, panels: [.main])
        fp.perform("play", track: "phares"); fp.perform("seek", track: "3.0"); await wait(.synced, 8); fp.perform("pause"); await settle(500)
        c.model.hovering = true; await settle(300)
        await shot("etat-05-en-pause-barre", bright: false, panels: [.main])
        c.model.hovering = false
        fp.perform("play", track: "instrumental"); await wait(.instrumental, 8)
        await shot("etat-06-instrumental", bright: false, panels: [.main])
        fp.perform("play", track: "sans-paroles"); await wait(.unavailable, 8)
        await shot("etat-07-indisponibles", bright: false, panels: [.main])
        fp.perform("play", track: "occupe"); await wait(.busy, 8)
        await shot("etat-08-service-occupe", bright: false, panels: [.main])
        await wait(.synced, 10)
        c.model.setOnline(false); fp.perform("play", track: "autre"); await wait(.offline, 6)
        await shot("etat-09-hors-connexion", bright: false, panels: [.main])
        c.model.setOnline(true); await wait(.synced, 10)
        fp.perform("stop"); await wait(.nothing, 3)
        fp.perform("perm-needed"); await wait(.permission, 3)
        await shot("etat-10-autorisation-necessaire", bright: false, panels: [.main])
        c.model.musicPermissionAnswered(.denied); await settle(500)
        await shot("etat-11-autorisation-refusee", bright: false, panels: [.main])
        c.model.musicPermissionAnswered(.granted); await settle(300)
        fp.perform("play", track: "phares"); await wait(.synced, 8)
        fp.perform("unreadable"); await wait(.unreadable, 3)
        await shot("etat-12-titre-illisible", bright: false, panels: [.main])
        fp.perform("stop"); await wait(.nothing, 3)
        // volet de réglages qui défile : zone visible simulée de 500 pt, avec la ligne « Synchro réduite » de Spotify
        c.model.spotifyAccess = .notDetermined
        c.settingsController.open(); c.settingsController.visibleHeightOverride = 500; c.settingsController.resizeToFit(); await settle(700)
        await shot("volet-defile-500", bright: false, panels: [.main, .settings])
        c.settingsController.visibleHeightOverride = nil; c.settingsController.resizeToFit(); await settle(500)
        await shot("volet-complet-spotify", bright: false, panels: [.main, .settings])
        c.settingsController.close(); c.model.spotifyAccess = nil
    }

    private func all() async {
        let fp = c.fakePlayer
        await states()
        // État de départ : « Phares sur la mer » à 3 s (ligne 2 courante), figé.
        fp?.perform("play", track: "phares"); fp?.perform("seek", track: "3.0"); fp?.perform("pause")
        c.change { $0.style = .glass; $0.size = 26; $0.backgroundOpacity = 38; $0.artworkColors = false }
        for bright in [false, true] {
            for style in BackgroundStyle.allCases {
                c.setStyle(style)
                await settle()
                await shot("snap-\(bright ? "clair" : "sombre")-\(style.rawValue)", bright: bright, panels: [.main])
            }
        }
        // survol (barre et crédit visibles), Verre, sombre
        c.setStyle(.glass); c.model.hovering = true; await settle()
        await shot("snap-sombre-glass-survol", bright: false, panels: [.main])
        // volet de réglages ouvert à droite
        c.settingsController.open(); await settle(700)
        await shot("snap-volet-sombre", bright: false, panels: [.main, .settings])
        await shot("snap-volet-clair", bright: true, panels: [.main, .settings])
        c.settingsController.close(); c.model.hovering = false
        // états
        fp?.perform("play", track: "sans-paroles"); await settle()
        await shot("snap-etat-indisponible", bright: false, panels: [.main])
        fp?.perform("stop"); await settle()
        await shot("snap-etat-rien", bright: false, panels: [.main])
        // J3 : texte seul → bloc « non synchronisées », instrumental, service occupé (429 du catalogue), hors connexion, volet J3
        fp?.perform("play", track: "brume"); await settle(900)
        await shot("snap-etat-non-synchronisees", bright: false, panels: [.main])
        fp?.perform("play", track: "instrumental"); await settle(900)
        await shot("snap-etat-instrumental", bright: false, panels: [.main])
        fp?.perform("play", track: "occupe"); await settle(900)
        await shot("snap-etat-occupe", bright: false, panels: [.main])
        c.model.setOnline(false); fp?.perform("play", track: "autre"); await settle(700)
        await shot("snap-etat-hors-connexion", bright: false, panels: [.main])
        c.model.setOnline(true); await settle(900)
        c.settingsController.open(); await settle(700)
        await shot("snap-volet-j3", bright: false, panels: [.main, .settings])
        c.settingsController.close(); await settle()
        // À propos
        c.openAbout(); await settle(700)
        await shot("snap-apropos", bright: false, panels: [.main, .about])
        c.aboutController.close()
        // lignes longues, taille 44
        c.change { $0.size = 44 }
        fp?.perform("play", track: "longues"); fp?.perform("seek", track: "6.0"); fp?.perform("pause"); await settle(700)
        await shot("snap-longues-80-taille44", bright: false, panels: [.main])
        fp?.perform("play", track: "tres-longues"); fp?.perform("seek", track: "3.0"); fp?.perform("pause"); await settle(700)
        await shot("snap-longues-250-taille44", bright: false, panels: [.main])
        c.change { $0.size = 26 }
        // police, couleur, opacité (une vue de contrôle)
        fp?.perform("play", track: "phares"); fp?.perform("seek", track: "3.0"); fp?.perform("pause")
        c.change { $0.font = .newYork; $0.colorIndex = 1; $0.backgroundOpacity = 70; $0.style = .solid }; await settle(700)
        await shot("snap-newyork-jaune-uni-70", bright: false, panels: [.main])
        c.change { $0.font = .system; $0.colorIndex = 0; $0.backgroundOpacity = 38; $0.style = .glass }
        await features()
    }

    /// Attend (3 s au plus) la palette de la pochette du titre en cours.
    private func waitPalette() async {
        var t = 0.0
        while c.model.palette == nil && t < 3 { try? await Task.sleep(for: .milliseconds(100)); t += 0.1 }
        await settle(700)
    }

    private func at(_ track: String, seek: String = "14.0") async {
        guard let fp = c.fakePlayer else { return }
        fp.perform("play", track: track); fp.perform("seek", track: seek)
        var t = 0.0
        while c.model.mode != .synced && t < 6 { try? await Task.sleep(for: .milliseconds(100)); t += 0.1 }
        fp.perform("pause")
        await settle(500)
    }

    /// pochettes, 1 et 5 lignes, thèmes, boutons de la barre, fenêtre redimensionnée. Texte et pochettes INVENTÉS.
    private func features() async {
        c.change { $0.style = .glass; $0.size = 26; $0.backgroundOpacity = 38; $0.artworkColors = true; $0.lineCount = 3; $0.apply(theme: .classic) }
        await at("phares"); await waitPalette()
        await shot("b14-artwork-red", bright: false, panels: [.main])
        c.model.hovering = true; await settle(400)
        await shot("b14-hero", bright: false, panels: [.main])
        c.change { $0.style = .solid }; await settle(500)
        await shot("b14-artwork-red-solid", bright: false, panels: [.main])
        c.change { $0.style = .glass }
        c.model.hovering = false
        await at("autre", seek: "9.0"); await waitPalette()
        await shot("b14-artwork-blue", bright: false, panels: [.main])
        await at("phares"); await waitPalette()
        c.change { $0.lineCount = 1 }; await settle(600)
        await shot("b14-lines-1", bright: false, panels: [.main])
        c.change { $0.lineCount = 5 }; await settle(600)
        await shot("b14-lines-5", bright: false, panels: [.main])
        c.change { $0.lineCount = 3; $0.artworkColors = false }
        for (name, theme) in [("elegant", FontTheme.elegant), ("neon", .neon), ("minimal", .minimal)] {
            c.change { $0.apply(theme: theme); $0.style = name == "neon" ? .solid : .glass }; await settle(700)
            await shot("b14-theme-\(name)", bright: false, panels: [.main])
        }
        c.change { $0.apply(theme: .classic); $0.style = .glass; $0.artworkColors = true; $0.size = 44 }; await settle(500)
        c.change { $0.windowWidth = 330; $0.windowHeight = 140 }; await settle(700)
        await shot("b14-resized-small", bright: false, panels: [.main])
        c.change { $0.windowWidth = 760; $0.windowHeight = 300 }; await settle(700)
        await shot("b14-resized-large", bright: false, panels: [.main])
        c.change { $0.windowWidth = nil; $0.windowHeight = nil; $0.size = 26 }; await settle(500)
        c.model.hovering = true
        c.settingsController.open(); await settle(800)
        await shot("b14-settings", bright: false, panels: [.main, .settings])
        c.settingsController.close(); c.model.hovering = false
    }

    enum Which { case main, settings, about }

    private func shot(_ name: String, bright: Bool, panels: [Which]) async {
        let scale = 2.0
        let size = Self.canvas
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        // faux bureau
        let desktop = ImageRenderer(content: MockDesktopView(bright: bright).frame(width: size.width, height: size.height))
        desktop.scale = scale
        desktop.nsImage?.draw(in: NSRect(origin: .zero, size: size))
        // fenêtre principale centrée à (50 %, 52 % depuis le haut) comme la maquette
        let mainPanel = c.panelController.panel
        let mh = mainPanel.frame.height
        let mw = mainPanel.frame.width
        let mainRect = NSRect(x: size.width / 2 - mw / 2, y: size.height * 0.48 - mh / 2, width: mw, height: mh)
        for which in panels {
            switch which {
            case .main: draw(panel: mainPanel, in: mainRect)
            case .settings:
                let sp = c.settingsController.panel
                let r = NSRect(x: mainRect.maxX + SettingsPanelController.gap, y: max(8, mainRect.maxY - sp.frame.height), width: sp.frame.width, height: sp.frame.height)
                draw(panel: sp, in: r)
            case .about:
                let ap = c.aboutController.panel
                draw(panel: ap, in: NSRect(x: size.width / 2 - ap.frame.width / 2, y: size.height / 2 - ap.frame.height / 2, width: ap.frame.width, height: ap.frame.height))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) {
            let path = "\(dir)/\(name).png"
            try? png.write(to: URL(fileURLWithPath: path))
            DiagLog.shared.write(["snapshot": name, "fichier": path, "px": "\(rep.pixelsWide)x\(rep.pixelsHigh)", "fenetreH": Int(mh)])
        }
    }

    private func draw(panel: NSPanel, in rect: NSRect) {
        guard let view = panel.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Faux bureau de la maquette (dégradés radiaux, barre de menus, deux fausses fenêtres), clair ou sombre.
struct MockDesktopView: View {
    var bright: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Color(hex: bright ? "#f2efe8" : "#14142b")
                radial(bright ? "#ffe29a" : "#5b3df5", cx: 0.15, cy: 0.20, rx: 0.60 * w, ry: 0.70 * h)
                radial(bright ? "#b9e3ff" : "#ff5f9e", cx: 0.85, cy: 0.25, rx: 0.55 * w, ry: 0.60 * h)
                radial(bright ? "#ffc9a8" : "#18c1c9", cx: 0.60, cy: 0.95, rx: 0.70 * w, ry: 0.70 * h)
                HStack(spacing: 18) {
                    Text("Éditeur").bold(); Text("Fichier"); Text("Édition"); Text("Présentation"); Spacer()
                    Text("♪ ven. 22 oct. 10:42")
                }
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.9)).padding(.horizontal, 14)
                .frame(width: w, height: 26).background(.black.opacity(0.28))
                fakeWindow(x: 0.05 * w, y: 0.09 * h, width: 520, height: 330) {
                    Text("func fenetreFlottante() {\n    let panneau = NSPanel(...)\n    panneau.level = .screenSaver\n    panneau.collectionBehavior = [\n        .canJoinAllSpaces,\n        .fullScreenAuxiliary\n    ]\n    // un texte derrière la vitre :\n    // le flou le rend illisible, joli.\n    panneau.orderFrontRegardless()\n}")
                        .font(.system(size: 12, design: .monospaced)).lineSpacing(12 * 1.7 - 14.5).foregroundStyle(Color(hex: "#33364a"))
                        .padding(.horizontal, 18).padding(.vertical, 14)
                }
                fakeWindow(x: w - 0.06 * w - 430, y: 0.24 * h, width: 430, height: 300) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes de projet").font(.system(size: 18, weight: .bold)).foregroundStyle(Color(hex: "#16161d"))
                        Text("Texte de document fictif pour voir comment la vitre dépolie floute ce qui passe derrière la fenêtre de paroles.")
                            .font(.system(size: 13)).lineSpacing(13 * 1.7 - 16).foregroundStyle(Color(hex: "#3a3a46"))
                        ForEach([0.92, 0.78, 0.86, 0.55], id: \.self) { f in
                            RoundedRectangle(cornerRadius: 5).fill(Color(hex: "#e1e1ea")).frame(width: 390 * f, height: 10).padding(.vertical, 4.5)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 16)
                }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
        }
    }

    private func radial(_ hex: String, cx: Double, cy: Double, rx: Double, ry: Double) -> some View {
        GeometryReader { geo in
            Circle().fill(RadialGradient(colors: [Color(hex: hex), Color(hex: hex).opacity(0)], center: .center, startRadius: 0, endRadius: 1))
                .frame(width: 2, height: 2)
                .scaleEffect(x: rx, y: ry)
                .position(x: cx * geo.size.width, y: cy * geo.size.height)
        }
    }

    private func fakeWindow<C: View>(x: Double, y: Double, width: Double, height: Double, @ViewBuilder content: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: "#ff5f57")).frame(width: 12, height: 12)
                Circle().fill(Color(hex: "#febc2e")).frame(width: 12, height: 12)
                Circle().fill(Color(hex: "#28c840")).frame(width: 12, height: 12)
                Spacer()
            }.padding(.leading, 12).frame(height: 34).background(Color(hex: "#ececf0"))
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: width, height: height)
        .background(Color(red: 250 / 255, green: 250 / 255, blue: 252 / 255).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black).shadow(color: .black.opacity(0.35), radius: 25, y: 18).opacity(0.0001))
        .offset(x: x, y: y)
    }
}
#endif
