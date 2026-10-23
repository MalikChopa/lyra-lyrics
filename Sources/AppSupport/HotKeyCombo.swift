import Foundation

/// Combinaison du raccourci global « Cacher / montrer ». Les masques sont ceux de Carbon (`RegisterEventHotKey`),
/// recopiés ici pour que ce module reste en Foundation seule.
public struct HotKeyCombo: Codable, Equatable, Sendable {
    public static let carbonCommand: UInt32 = 0x0100   // cmdKey
    public static let carbonShift: UInt32 = 0x0200     // shiftKey
    public static let carbonOption: UInt32 = 0x0800    // optionKey
    public static let carbonControl: UInt32 = 0x1000   // controlKey
    public static let allModifiers: UInt32 = carbonCommand | carbonShift | carbonOption | carbonControl
    /// Au moins un de ceux-là est exigé (⇧ seul ne suffit pas : ⇧+lettre est une frappe de texte).
    public static let requiredOneOf: UInt32 = carbonCommand | carbonOption | carbonControl

    public var keyCode: UInt32
    public var modifiers: UInt32
    /// Libellé de la touche tel que reçu à l'enregistrement (« L », « 7 », « Espace »…), pour l'affichage.
    public var label: String

    public init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.allModifiers
        self.label = label
    }

    /// Affichage dans l'ordre de macOS : ⌃ ⌥ ⇧ ⌘ puis la touche.
    public var display: String {
        var s = ""
        if modifiers & Self.carbonControl != 0 { s += "⌃" }
        if modifiers & Self.carbonOption != 0 { s += "⌥" }
        if modifiers & Self.carbonShift != 0 { s += "⇧" }
        if modifiers & Self.carbonCommand != 0 { s += "⌘" }
        return s + label.uppercased()
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case needsModifier      // aucune des touches ⌃ ⌥ ⌘
        case emptyKey           // pas de touche
    }

    /// Valide une combinaison enregistrée ; refuse celle qui n'a pas de modificateur.
    public static func validated(keyCode: UInt32, modifiers: UInt32, label: String) -> Result<HotKeyCombo, ValidationError> {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return .failure(.emptyKey) }
        guard modifiers & requiredOneOf != 0 else { return .failure(.needsModifier) }
        return .success(HotKeyCombo(keyCode: keyCode, modifiers: modifiers, label: label))
    }

    public var isValid: Bool {
        if case .success = Self.validated(keyCode: keyCode, modifiers: modifiers, label: label) { return true }
        return false
    }
}

/// Raccourci par défaut : la SEULE occurrence de la combinaison dans le code (décision utilisateur du 2026-10-22 : ⌃⌥⌘L,
/// code de touche 37 = L sur clavier ANSI ; modifiable dans le volet de réglages).
public let defaultHotKey = HotKeyCombo(
    keyCode: 37,
    modifiers: HotKeyCombo.carbonControl | HotKeyCombo.carbonOption | HotKeyCombo.carbonCommand,
    label: "L"
)
