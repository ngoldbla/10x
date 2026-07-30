// BoardKeys.swift — one keyboard grammar over the board, for every platform
// that has a keyboard (PRD-31).
//
// This was `MacBoardKeys`, and it lived inside `MacUI.swift`'s `#if os(macOS)`
// for the entirely reasonable reason that the Mac was the only place a key
// could arrive. An iPad with a Magic Keyboard is the other place, and it has
// been shipping with none of this: no arrows, no digits, no ⇧-digit pencil, no
// Tab-to-next-empty. "Keyboard parity" is not new work so much as it is
// deleting a platform fence, which is why the grammar moved out whole rather
// than being reimplemented — a second copy would drift, and the drift would be
// invisible until someone happened to play the same board on both.
//
// The classification is pure and stateful nothing: the game screens decide what
// a `.place` means in sticky-pencil mode, and the tutorial reuses the same
// table so its keyboard never disagrees with the game's.
#if os(iOS) || os(macOS)
import SwiftUI
// `Direction4` is CouchKit's — the same one the remote and the pad speak, so a
// keyboard arrow and a D-pad press decode to the same value on the way in.
import CouchKit

/// One decoded keystroke over the board. Pure classification (no state), so the
/// two game screens and the tutorial share it.
enum BoardKeyAction {
    case move(Direction4)
    case place(Int)
    case pencil(Int)
    case erase
    case toggleStickyPencil
    case highlight
    case nextEmpty(forward: Bool)
    case escape
}

enum BoardKeys {
    /// Classify a `KeyPress` into a board action, or nil to pass it through
    /// (⌘-shortcuts belong to the menus on Mac and to the system on iPad). The
    /// never-misfire rule is trivial here: a keystroke is unambiguous.
    static func action(for press: KeyPress) -> BoardKeyAction? {
        switch press.key {
        case .upArrow: return .move(.up)
        case .downArrow: return .move(.down)
        case .leftArrow: return .move(.left)
        case .rightArrow: return .move(.right)
        case .escape: return .escape
        case .space: return .highlight
        case .tab: return .nextEmpty(forward: !press.modifiers.contains(.shift))
        case .delete, .deleteForward: return .erase
        default: break
        }
        let ch = press.key.character
        if ch == "p" || ch == "P" { return .toggleStickyPencil }
        if ch == "0" { return .erase }
        // The hardware delete (backspace) key can arrive as a raw control
        // character rather than KeyEquivalent.delete (observed in validation).
        if ch == "\u{7F}" || ch == "\u{08}" { return .erase }
        if let digit = digitValue(press), (1...9).contains(digit) {
            return press.modifiers.contains(.shift) ? .pencil(digit) : .place(digit)
        }
        return nil
    }

    /// The digit a key stands for, tolerating layouts that deliver ⇧1 as its
    /// shifted symbol rather than the base digit.
    private static func digitValue(_ press: KeyPress) -> Int? {
        if let value = press.key.character.wholeNumberValue, (0...9).contains(value) {
            return value
        }
        switch press.key.character {
        case "!": return 1
        case "@": return 2
        case "#": return 3
        case "$": return 4
        case "%": return 5
        case "^": return 6
        case "&": return 7
        case "*": return 8
        case "(": return 9
        default: return nil
        }
    }
}
#endif
