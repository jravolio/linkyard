//
//  PickerAnimation.swift
//  Browserino
//

import AppKit

enum PickerAnimation: String, CaseIterable, Identifiable {
    case none, fade, rise, zoom, glow
    case restore, ink, thaw, crystallize, ripple, hologram, materialize

    static let effects = allCases.filter { $0.effect != nil }

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .fade: "Fade"
        case .rise: "Rise"
        case .zoom: "Zoom"
        case .glow: "Glow"
        case .restore: "Restore"
        case .ink: "Ink"
        case .thaw: "Thaw"
        case .crystallize: "Crystallize"
        case .ripple: "Ripple"
        case .hologram: "Hologram"
        case .materialize: "Materialize"
        }
    }

    /// Reduce Motion keeps only a fade.
    var resolved: PickerAnimation {
        self != .none && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .fade : self
    }

    /// The case of PickerEffects.metal's `mode` switch that draws it, and how long it plays.
    var effect: (mode: Int32, duration: TimeInterval)? {
        switch self {
        case .restore: (0, 0.6)
        case .ink: (1, 0.55)
        case .thaw: (2, 0.75)
        case .crystallize: (3, 0.65)
        case .ripple: (4, 0.5)
        case .hologram: (5, 0.5)
        case .materialize: (6, 0.45)
        case .none, .fade, .rise, .zoom, .glow: nil
        }
    }

    var summary: String {
        switch self {
        case .none: "Appears instantly. The fastest."
        case .fade: "Fades in."
        case .rise: "Slides up into place, like Arc's windows."
        case .zoom: "Zooms in toward you as it fades in."
        case .glow: "Fades in with a brief glow around the edge, like Dia."
        case .restore: "Burns in reverse from the bottom, and the picker heals behind the glowing edge."
        case .ink: "Spreads out from the middle like a drop of ink in water."
        case .thaw: "Appears frosted over, then thaws from the middle out."
        case .crystallize: "Grows from scattered ice crystals that join into the picker."
        case .ripple: "A single glassy wave rolls out from the middle."
        case .hologram: "A scan line draws it from the top with a quick flicker."
        case .materialize: "Resolves from big pixels to sharp."
        }
    }
}
