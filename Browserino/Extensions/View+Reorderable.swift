//
//  View+Reorderable.swift
//  Browserino
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    /// Declared in Info.plist; a drag of another type, like text from another app, never reorders rows.
    static let settingsRow = UTType(exportedAs: "io.github.jravolio.Linkyard.settings-row")
}

extension View {
    /// Rows in a grouped Form can't use `onMove`, so a dragged row moves into each row it passes over,
    /// and the list shows the new order before it's dropped.
    /// VoiceOver and keyboard users get Move Up and Move Down actions instead of dragging.
    func reorderable(at index: Int, count: Int, draggedRow: Binding<Int?>, move: @escaping (_ from: Int, _ to: Int) -> Void) -> some View {
        modifier(Reorderable(index: index, count: count, draggedRow: draggedRow, move: move))
    }
}

private struct Reorderable: ViewModifier {
    let index: Int
    let count: Int
    @Binding var draggedRow: Int?
    let move: (_ from: Int, _ to: Int) -> Void

    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            content
        }
        .opacity(draggedRow == index ? 0.4 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move Up") {
            if index > 0 {
                move(index, index - 1)
            }
        }
        .accessibilityAction(named: "Move Down") {
            if index < count - 1 {
                move(index, index + 1)
            }
        }
        .onDrag {
            draggedRow = index
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.settingsRow.identifier, visibility: .all) { completion in
                completion(Data(), nil)
                return nil
            }
            return provider
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .onDrop(of: [.settingsRow], delegate: RowDropDelegate(index: index, height: height, draggedRow: $draggedRow, move: move))
        .onHover { _ in
            // A drag let go outside the rows never drops, so its row stays faded until the pointer comes back.
            if draggedRow != nil && NSEvent.pressedMouseButtons == 0 {
                draggedRow = nil
            }
        }
    }
}

private struct RowDropDelegate: DropDelegate {
    let index: Int
    let height: CGFloat
    @Binding var draggedRow: Int?
    let move: (_ from: Int, _ to: Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let from = draggedRow, RowReorder.shouldMove(from: from, to: index, y: info.location.y, height: height) {
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.15)) {
                move(from, index)
            }
            draggedRow = index
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedRow = nil
        return true
    }
}

enum RowReorder {
    /// Whether the row dragged from `from` takes the place of row `to`, with the pointer `y` points down that `height`-point row.
    /// Only past the row's middle: moving on entry swaps rows of different heights back and forth, since the taller one ends up under the pointer again.
    static func shouldMove(from: Int, to: Int, y: CGFloat, height: CGFloat) -> Bool {
        from != to && (from < to ? y > height / 2 : y < height / 2)
    }
}

extension Array {
    /// Moves an element onto another's position; dropping a row on one below it puts it after that row.
    mutating func move(from: Int, to: Int) {
        move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
}
