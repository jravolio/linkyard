//
//  View+Reorderable.swift
//  Browserino
//

import SwiftUI

private let reorderPrefix = "linkyard-row:"

extension View {
    /// Rows in a grouped Form can't use `onMove`, so a row is dragged onto another to take its place.
    /// VoiceOver and keyboard users get Move Up and Move Down actions instead of dragging.
    func reorderable(at index: Int, count: Int, move: @escaping (_ from: Int, _ to: Int) -> Void) -> some View {
        accessibilityElement(children: .contain)
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
            .draggable("\(reorderPrefix)\(index)")
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first,
                      item.hasPrefix(reorderPrefix),
                      let from = Int(item.dropFirst(reorderPrefix.count)),
                      from != index
                else {
                    return false
                }

                move(from, index)
                return true
            }
    }
}

extension Array {
    /// Moves an element onto another's position; dropping a row on one below it puts it after that row.
    mutating func move(from: Int, to: Int) {
        move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }
}
