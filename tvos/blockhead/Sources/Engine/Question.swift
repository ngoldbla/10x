// Blockhead engine — question model.
// Pure Swift: Foundation + CouchCore only (builds and tests on Linux).
import Foundation
import CouchCore

/// One Blockhead question.
///
/// The four answers are authored in *direction order* — the mapping between
/// array index and swipe direction is fixed and IS the layout on screen:
///
///     index 0 = up · 1 = right · 2 = down · 3 = left
///
/// Exactly one answer (at `correctIndex`) is correct. Picture rounds carry a
/// CouchCore `DemoArt` recipe id in `pictureRecipe`; the app renders it via
/// AsciiEngine (mosaic during the countdown, sharpening on reveal).
public struct Question: Sendable, Hashable, Codable, Identifiable {
    public enum Category: String, Sendable, Codable, CaseIterable, Hashable {
        case general
        case science
        case words
        /// Movies & music.
        case screen
        case geography
        case oddOneOut
    }

    public let id: String
    public let prompt: String
    /// Exactly four answers, in direction order (up, right, down, left).
    public let answers: [String]
    public let correctIndex: Int
    public let category: Category
    /// 1 (warm) … 3 (hard).
    public let difficulty: Int
    /// Optional `DemoArt` recipe id — presence makes this a picture round.
    public let pictureRecipe: String?

    public init(
        id: String,
        prompt: String,
        answers: [String],
        correctIndex: Int,
        category: Category,
        difficulty: Int,
        pictureRecipe: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.answers = answers
        self.correctIndex = correctIndex
        self.category = category
        self.difficulty = difficulty
        self.pictureRecipe = pictureRecipe
    }

    public var isPicture: Bool { pictureRecipe != nil }

    public var correctAnswer: String { answers[correctIndex] }

    public var correctDirection: Direction4 {
        Self.direction(forAnswerIndex: correctIndex)
    }

    /// The fixed index ↔ direction mapping (up, right, down, left).
    public static let directionOrder: [Direction4] = [.up, .right, .down, .left]

    public static func direction(forAnswerIndex index: Int) -> Direction4 {
        directionOrder[index]
    }

    public static func answerIndex(for direction: Direction4) -> Int {
        switch direction {
        case .up: 0
        case .right: 1
        case .down: 2
        case .left: 3
        }
    }

    public func answer(for direction: Direction4) -> String {
        answers[Self.answerIndex(for: direction)]
    }
}
