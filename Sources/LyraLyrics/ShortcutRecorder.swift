import AppKit
import Observation
import AppSupport

/// Enregistrement d'une nouvelle combinaison pour le raccourci Cacher / montrer (volet de réglages).
/// Refuse une combinaison sans ⌃, ⌥ ou ⌘ ; affiche « raccourci indisponible » si l'enregistrement échoue.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var isRecording = false
    private(set) var message: String?

    /// Enregistre la combinaison auprès du système ; faux = « raccourci indisponible ».
    @ObservationIgnored var apply: (HotKeyCombo) -> Bool = { _ in true }
    /// Suspend / reprend le raccourci global pendant l'enregistrement (sinon la combinaison actuelle serait interceptée).
    @ObservationIgnored var suspendGlobal: (Bool) -> Void = { _ in }
    @ObservationIgnored private var monitor: Any?

    static let specialKeys: [UInt16: String] = [
        49: "Espace", 36: "Retour", 48: "Tab", 51: "Suppr", 117: "Suppr⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    func toggle() { isRecording ? cancel() : begin() }

    func begin() {
        guard !isRecording else { return }
        isRecording = true
        message = nil
        suspendGlobal(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let e = event
            let consumed = MainActor.assumeIsolated { self?.handle(e) ?? false }
            return consumed ? nil : e
        }
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        suspendGlobal(false)
    }

    /// Renvoie vrai si la frappe est consommée.
    func handle(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { cancel(); return true }                 // Échap
        let label = Self.specialKeys[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        submit(keyCode: UInt32(event.keyCode), flags: event.modifierFlags, label: label)
        return true
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= HotKeyCombo.carbonCommand }
        if flags.contains(.option) { m |= HotKeyCombo.carbonOption }
        if flags.contains(.control) { m |= HotKeyCombo.carbonControl }
        if flags.contains(.shift) { m |= HotKeyCombo.carbonShift }
        return m
    }

    /// Valide puis applique ; le chemin est le même pour une vraie frappe et pour l'autotest.
    @discardableResult
    func submit(keyCode: UInt32, flags: NSEvent.ModifierFlags, label: String) -> Bool {
        submit(keyCode: keyCode, carbon: Self.carbonModifiers(flags), label: label)
    }

    @discardableResult
    func submit(keyCode: UInt32, carbon: UInt32, label: String) -> Bool {
        switch HotKeyCombo.validated(keyCode: keyCode, modifiers: carbon, label: label) {
        case .failure:
            message = "Ajoute ⌃, ⌥ ou ⌘ à la combinaison."
            return false
        case .success(let combo):
            cancel()                                    // reprend l'ancien raccourci avant d'essayer le nouveau
            if apply(combo) { message = nil; return true }
            message = "raccourci indisponible"
            return false
        }
    }
}
