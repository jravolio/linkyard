//
//  PickerAnimation.swift
//  Browserino
//

import AppKit

enum PickerAnimation: String, CaseIterable, Identifiable {
    case none, fade, rise, zoom, glow

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .fade: "Fade"
        case .rise: "Rise"
        case .zoom: "Zoom"
        case .glow: "Glow"
        }
    }

    /// Reduce Motion keeps only a fade.
    var resolved: PickerAnimation {
        self != .none && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .fade : self
    }

    var summary: String {
        switch self {
        case .none: "Appears instantly. The fastest."
        case .fade: "Fades in."
        case .rise: "Slides up into place, like Arc's windows."
        case .zoom: "Zooms in toward you as it fades in."
        case .glow: "Fades in with a brief glow around the edge, like Dia."
        }
    }
}
