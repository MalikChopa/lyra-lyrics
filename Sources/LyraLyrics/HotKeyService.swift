import AppKit
import Carbon.HIToolbox
import AppSupport

private let hotKeySignature: OSType = 0x5046_484B   // 'PFHK'

private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &id)
    if status == noErr, id.signature == hotKeySignature {
        Task { @MainActor in HotKeyService.shared?.pressed() }
    }
    return noErr
}

/// Raccourci global « Cacher / montrer » par `RegisterEventHotKey` (aucune permission, aucune dépendance).
/// `noErr` ne prouve pas l'absence de conflit avec une autre app (§12) : seul un code d'erreur est détecté.
@MainActor
final class HotKeyService {
    enum Registration: Equatable { case none, registered, failed(Int32) }

    static weak var shared: HotKeyService?

    private(set) var registration: Registration = .none
    private(set) var current: HotKeyCombo?
    private(set) var pressCount = 0
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    init() { Self.shared = self }

    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: hotKeySignature, id: 1),
                                         GetApplicationEventTarget(), 0, &newRef)
        if status == noErr, let newRef {
            ref = newRef; current = combo; registration = .registered
            return true
        }
        registration = .failed(status)
        current = nil
        return false
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registration = .none
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    fileprivate func pressed() {
        pressCount += 1
        onPress?()
    }

    /// Autotest : envoie au gestionnaire un événement Carbon « raccourci pressé » (aucune frappe réelle, aucune permission).
    /// Prouve le chemin gestionnaire → effet ; NE prouve PAS que le système livre la vraie frappe.
    func deliverSyntheticPress() -> Bool {
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr, let event else { return false }
        defer { ReleaseEvent(event) }
        var id = EventHotKeyID(signature: hotKeySignature, id: 1)
        guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                MemoryLayout<EventHotKeyID>.size, &id) == noErr else { return false }
        return SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr
    }
}

#if DEBUG
extension HotKeyService {
    /// Autotest : occupe une combinaison (autre identifiant, même app) pour provoquer un échec d'enregistrement réel
    /// (`eventHotKeyExistsErr`) et exercer le message « raccourci indisponible ».
    func debugBlock(_ combo: HotKeyCombo) -> Int32 {
        debugUnblock()
        var r: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: hotKeySignature, id: 99), GetApplicationEventTarget(), 0, &r)
        if status == noErr { Self.blocker = r }
        return status
    }
    func debugUnblock() {
        if let r = Self.blocker { UnregisterEventHotKey(r) }
        Self.blocker = nil
    }
    nonisolated(unsafe) fileprivate static var blocker: EventHotKeyRef?
}
#endif
