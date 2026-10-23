import AppKit
import SwiftUI
import AppSupport
import LyricsCore
import PlayerKit

struct PanelActions {
    var cycleStyle: @MainActor () -> Void
    var toggleSettings: @MainActor () -> Void
    var openAbout: @MainActor () -> Void
    var requestMusicAccess: @MainActor () -> Void
    /// « Réessayer » (états « Paroles indisponibles » et « Service occupé »).
    var retryLookup: @MainActor () -> Void
}

private let accent = Color(red: 10 / 255, green: 132 / 255, blue: 1)
private let txtMid = Color.white.opacity(0.62)

/// Fond « glisser la fenêtre » : vue AppKit sous le texte. `isMovableByWindowBackground` fait le glisser natif ;
/// `performDrag(with:)` en repli si le `mouseDown` arrive quand même jusqu'ici (§7).
struct DragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// Fenêtre de paroles : trois lignes centrées (courante en avant, voisines 0,66 × à 42 %), états du §3.6, bloc
/// « non synchronisées », barre au survol, crédit.
struct LyricsView: View {
    var model: AppModel
    var store: SettingsStore
    var actions: PanelActions

    var body: some View {
        let s = store.settings
        let style = model.effectiveStyle(s.style)
        let showBar = model.hovering || model.settingsOpen
        ZStack {
            BackgroundView(style: style, opacityPercent: s.backgroundOpacity, tint: s.artworkColors ? model.palette?.tint : nil)
            DragHandle()
            Group {
                switch model.mode {
                case .searching, .synced:
                    LinesStack(model: model, settings: s, clearShadow: style == .clear)
                case .unsynced:
                    UnsyncedBlock(model: model, settings: s, clearShadow: style == .clear)
                case .nothing, .instrumental, .unavailable, .busy, .offline, .permission, .unreadable:
                    let text = model.display.stateText ?? ("", "")
                    StateView(title: text.title, message: Self.message(text.body))
                }
            }
            .padding(.top, LyricsMetrics.paddingTop).padding(.bottom, LyricsMetrics.paddingBottom + (model.stateActionLabel != nil ? 44 : 0)).padding(.horizontal, LyricsMetrics.paddingSide)
            .allowsHitTesting(false)
            if let label = model.stateActionLabel {
                // §3.6/§3.7 : « Autoriser » déclenche l'invite du système ; après un refus, « Ouvrir les Réglages ». 1.0.1 : « Réessayer »
                // dans « Paroles indisponibles » et « Service occupé ».
                Button(action: { model.mode == .permission ? actions.requestMusicAccess() : actions.retryLookup() }) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 10 / 255, green: 132 / 255, blue: 1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.stateActionAccessibilityLabel ?? label)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26)
            }
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Text(notice)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.85)
                    if let action = model.noticeAction {
                        Button(action: { action.perform() }) {
                            Text(action.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 3)
                                .background(Capsule().fill(Color(red: 10 / 255, green: 132 / 255, blue: 1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(action.label)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.62)).overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 10).padding(.horizontal, 12)
                .allowsHitTesting(model.noticeAction != nil)
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(notice)
            }
            VStack {
                HoverBar(model: model, onStyle: actions.cycleStyle, onGear: actions.toggleSettings)
                    .opacity(showBar ? 1 : 0)
                    .offset(y: showBar ? 0 : -4)
                    .allowsHitTesting(showBar)
                Spacer()
                CreditLine(onAbout: actions.openAbout)
                    .opacity(model.hovering ? 1 : 0)
                    .allowsHitTesting(model.hovering)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .animation(model.animation(.easeOut(duration: 0.2)), value: showBar)
        .animation(model.animation(.easeOut(duration: 0.2)), value: model.notice)
        .animation(model.animation(.easeOut(duration: 0.3)), value: style)
        .animation(model.animation(.easeInOut(duration: 0.6)), value: model.palette?.tint)
    }

    /// Corps d'un état : la parenthèse finale (maquette) est atténuée.
    static func message(_ body: String) -> Text {
        guard let r = body.range(of: " (") else { return Text(body) }
        let head = String(body[..<r.lowerBound]) + " "
        let tail = Text(String(body[r.upperBound...].dropLast(0)).hasPrefix("(") ? String(body[r.upperBound...]) : "(" + String(body[r.upperBound...]))
            .foregroundStyle(.white.opacity(0.62 * 0.7))
        return Text("\(Text(head))\(tail)")
    }
}

/// Pile de lignes (1, 3 ou 5) : voir `LineStackView`. Le changement de ligne est un défilement doux fait par des animations de
/// couches Core Animation (exécutées par le serveur de rendu) ; « Réduire les animations » = fondu simple.
private struct LinesStack: View {
    var model: AppModel
    var settings: Settings
    var clearShadow: Bool

    var body: some View {
        let fit = model.fit
        let style = LineStackStyle(font: settings.font, weight: settings.fontWeight, size: fit.currentSize, ratio: settings.neighbourRatio,
                                   color: model.searchHint ? RGB(1, 1, 1) : model.lineColor(settings), glow: settings.glow, clearShadow: clearShadow, width: model.textWidth)
        LinesHost(items: model.lineItems(count: settings.lineCount), style: style, epoch: model.trackEpoch,
                  motion: model.reduceMotion ? .fade : .glide, height: fit.contentHeight, width: model.textWidth,
                  onLayout: { h in DispatchQueue.main.async { model.renderedLinesHeight = h } },
                  register: { model.lineStack = $0 })
            .frame(width: model.textWidth, height: fit.contentHeight)
    }
}

struct LinesHost: NSViewRepresentable {
    var items: [LineItem]
    var style: LineStackStyle
    var epoch: Int
    var motion: LineMotion
    var height: Double
    var width: Double = LyricsMetrics.textWidth
    var onLayout: (Double) -> Void
    var register: (LineStackView) -> Void

    func makeNSView(context: Context) -> LineStackView {
        let v = LineStackView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        v.onLayout = onLayout
        register(v)
        return v
    }

    func updateNSView(_ v: LineStackView, context: Context) {
        v.onLayout = onLayout
        v.apply(items: items, style: style, epoch: epoch, motion: motion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LineStackView, context: Context) -> CGSize? {
        CGSize(width: width, height: height)
    }
}

/// Paroles non synchronisées (texte seul, ou écart de durée > 5 s) : bloc qui défile lentement avec la position
/// (décision utilisateur du 2026-10-22), mention « non synchronisées ».
private struct UnsyncedBlock: View {
    var model: AppModel
    var settings: Settings
    var clearShadow: Bool
    static let viewport = 100.0

    var body: some View {
        let color = Color(hex: settings.colorHex)
        let size = max(12, Double(settings.size) * 0.7)
        VStack(spacing: 6) {
            Text("Paroles non synchronisées").font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(txtMid)
            Text(model.plainText)
                .font(FontResolver.swiftUIFont(settings.font, size: size))
                .lineSpacing(FontResolver.extraLineSpacing(settings.font, size: size))
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
                .frame(width: model.textWidth)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(ClearTextShadow(enabled: clearShadow))
                .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { model.unsyncedContentHeight = $0 }
                .offset(y: -max(0, model.unsyncedContentHeight - Self.viewport) * model.unsyncedProgress)
                .animation(model.animation(.linear(duration: 0.12)), value: model.unsyncedProgress)
                .frame(width: model.textWidth, height: Self.viewport, alignment: .top)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                             .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .frame(width: model.textWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paroles non synchronisées")
        .accessibilityValue(model.plainText)
    }
}

/// Ombre du style Transparent. Un `.shadow` à rayon 0 et opacité 0 forçait quand même une couche de transparence CoreGraphics
/// (rendu logiciel à chaque image de l'animation, mesuré à J5b) : hors du style Transparent, AUCUN modificateur d'ombre.
struct ClearTextShadow: ViewModifier {
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black.opacity(0.65), radius: 7, y: 2)
                .shadow(color: .black.opacity(0.55), radius: 1)
        } else {
            content
        }
    }
}

/// États du §3.6 (titre gras / corps) : « Rien en lecture », « Paroles indisponibles » (textes de la maquette) et les autres.
struct StateView: View {
    var title: String
    var message: Text

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            message.font(.system(size: 15)).foregroundStyle(txtMid).lineSpacing(15 * 1.5 - 18)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 330)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// Géométrie de la barre au survol (partagée avec l'autotest, qui y clique : aucun nombre magique en double).
enum HoverBarLayout {
    static let buttonSize = 28.0
    static let spacing = 4.0
    static let sidePadding = 14.0
    static let groupGap = 10.0
    static let centerFromTop = 25.0
    /// Ordre de droite à gauche : ⚙, ◐, puis suivant, lecture/pause, précédent.
    static let order = ["gear", "style", "next", "playpause", "previous"]
    /// Abscisse du centre d'un bouton dans la fenêtre (origine à gauche).
    static func centerX(of name: String, windowWidth: Double = LyricsMetrics.windowWidth) -> Double {
        let i = Double(order.firstIndex(of: name) ?? 0)
        // un petit écart supplémentaire sépare le groupe de lecture du groupe style / réglages
        let extra = i >= 2 ? groupGap - spacing : 0
        return windowWidth - sidePadding - buttonSize / 2 - i * (buttonSize + spacing) - extra
    }
}

/// Barre au survol : titre · artiste, ⏮ ⏯ ⏭ (lecteur actif), ◐ (style suivant), ⚙ (réglages).
struct HoverBar: View {
    var model: AppModel
    var onStyle: @MainActor () -> Void
    var onGear: @MainActor () -> Void

    var body: some View {
        let bar = model.barText
        let playback = model.playbackAvailability
        HStack(spacing: 10) {
            Text("\(Text(bar.title).fontWeight(.semibold).foregroundStyle(.white))\(Text(bar.artist.map { " · \($0)" } ?? "").foregroundStyle(txtMid))")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
            HStack(spacing: HoverBarLayout.spacing) {
                transportButton(.previous, name: "previous", playback: playback)
                transportButton(.playPause, name: "playpause", playback: playback)
                transportButton(.next, name: "next", playback: playback)
            }
            HStack(spacing: HoverBarLayout.spacing) {
                BarButton(glyph: "◐", symbol: nil, label: "Changer de style de fond", disabled: false, help: "Changer de style de fond", hovered: model.hoveredButton == "style",
                          onHover: { model.hoveredButton = $0 ? "style" : nil }, action: onStyle)
                BarButton(glyph: "⚙", symbol: nil, label: "Réglages", disabled: false, help: "Réglages", hovered: model.hoveredButton == "gear",
                          onHover: { model.hoveredButton = $0 ? "gear" : nil }, action: onGear)
            }
        }
        .frame(height: 30)
        .padding(.horizontal, HoverBarLayout.sidePadding)
        .padding(.top, 10)
    }
}

extension HoverBar {
    @ViewBuilder fileprivate func transportButton(_ command: PlaybackCommand, name: String, playback: AppModel.PlaybackAvailability) -> some View {
        let isPlayPause = command == .playPause
        let showsPlay = model.isPaused || model.track == nil
        let symbol: String = isPlayPause ? (showsPlay ? "play.fill" : "pause.fill") : (command == .previous ? "backward.fill" : "forward.fill")
        let label: String = isPlayPause ? (showsPlay ? "Lecture" : "Pause") : command.accessibilityLabel
        let help: String = playback.enabled ? (playback.hint.map { "\(label) — \($0)" } ?? label) : (playback.reason ?? label)
        BarButton(glyph: nil, symbol: symbol, label: label, disabled: !playback.enabled, help: help, hovered: model.hoveredButton == name,
                  onHover: { model.hoveredButton = $0 ? name : nil }, action: { model.sendPlayback(command) })
    }
}

private struct BarButton: View {
    var glyph: String?
    var symbol: String?
    var label: String
    var disabled: Bool
    var help: String
    var hovered: Bool
    var onHover: (Bool) -> Void
    var action: @MainActor () -> Void

    var body: some View {
        Button(action: { action() }) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                } else {
                    Text(glyph ?? "").font(.system(size: 14))
                }
            }
            .foregroundStyle(.white.opacity(disabled ? 0.35 : 1))
            .accessibilityHidden(true)
            .frame(width: HoverBarLayout.buttonSize, height: HoverBarLayout.buttonSize)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(disabled ? 0.06 : (hovered ? 0.26 : 0.12))))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(disabled ? help : "")
        .help(help)
        .onHover { onHover($0) }
    }
}

/// Crédit « Paroles : LRCLIB · À propos et droits » (apparaît au survol).
struct CreditLine: View {
    var onAbout: @MainActor () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Text("Paroles : LRCLIB · ")
            Button(action: { onAbout() }) { Text("À propos et droits").underline() }.buttonStyle(.plain)
                .accessibilityLabel("À propos et droits")
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.35))
        .accessibilityElement(children: .contain)
    }
}

extension Color {
    init(hex: String) {
        var h = hex; if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt32(h, radix: 16) ?? 0xFFFFFF
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

