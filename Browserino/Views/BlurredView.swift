//
//  BlurredView.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import SwiftUI

struct BlurredView: NSViewRepresentable {
    /// Also used on its own by picker effects, which have to match this background exactly.
    static func makeEffectView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        
        return view
    }

    func makeNSView(context: Context) -> some NSVisualEffectView {
        Self.makeEffectView()
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
        
    }
}
