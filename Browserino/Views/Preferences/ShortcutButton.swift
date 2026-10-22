//
//  ShortcutButton.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct ShortcutButton: View {
    let browserId: String
    var name: String? = nil
    
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]
    
    @State private var isRecording: Bool = false
    @FocusState private var focus: Bool

    private static let escape = "\u{1B}"
    private static let deleteKeys: Set<String> = ["\u{7F}", "\u{8}"]

    enum Recording: Equatable {
        case cancel
        case clear
        case record(String)
    }

    /// Esc cancels recording and Delete removes the shortcut, so neither can become a shortcut.
    static func recording(for key: String) -> Recording {
        if key == escape {
            return .cancel
        }
        if deleteKeys.contains(key) {
            return .clear
        }
        return .record(key)
    }

    private func label(for key: String) -> String {
        key == Self.escape ? "esc" : key.uppercased()
    }
    
    var body: some View {
        if isRecording {
            Text("Press a key")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor))
                .contentShape(.rect)
                .focusable()
                .focused($focus)
                .onChange(of: focus) { newFocus in
                    isRecording = newFocus
                }
                .onKeyPressCompat { key in
                    isRecording = false

                    switch Self.recording(for: key) {
                    case .cancel:
                        break
                    case .clear:
                        shortcuts[browserId] = nil
                    case .record(let key):
                        if let shortcut = shortcuts.first(where: { $0.value == key }) {
                            shortcuts[shortcut.key] = nil
                        }
                        shortcuts[browserId] = key
                    }

                    return true
                }
                .help("Press a key to use as the shortcut. Esc cancels, Delete removes it.")
        } else {
            let recordedKey = shortcuts[browserId]
            
            Button(action: {
                isRecording = true
                focus = true
            }, label: {
                Text(recordedKey.map(label) ?? "Shortcut")
                    .font(recordedKey == nil ? .caption : .caption.monospaced().weight(.semibold))
                    .foregroundStyle(recordedKey == nil ? .secondary : .primary)
                    .frame(minWidth: 52)
            })
            .controlSize(.small)
            .help(recordedKey == nil ? "Record a key that opens this from the picker" : "Click to record a different key")
            .accessibilityLabel(name.map { "Shortcut for \($0)" } ?? "Shortcut")
        }
    }
}
