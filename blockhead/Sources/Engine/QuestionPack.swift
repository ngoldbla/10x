// The bundled v1 pack. Hand-written Swift source data — the linter tests in
// Tests/EngineTests keep every question shippable by construction.
import Foundation

public enum QuestionPack {
    /// Every bundled question. Order is stable; the planner's determinism
    /// depends on it, so append — never reorder.
    public static let all: [Question] =
        PackGeneral.questions
        + PackScience.questions
        + PackWords.questions
        + PackScreen.questions
        + PackGeography.questions
        + PackOddOneOut.questions
        + PackPicture.questions
}

/// Authoring helper. The correct answer is placed at `slot`
/// (0 = up, 1 = right, 2 = down, 3 = left); the three wrong answers fill the
/// remaining positions in order. Authors cycle `slot` 0→1→2→3 inside each
/// pack file so the correct direction stays balanced across the pack.
func packQuestion(
    _ id: String,
    _ prompt: String,
    correct: String,
    wrong: [String],
    slot: Int,
    _ category: Question.Category,
    _ difficulty: Int,
    art: String? = nil
) -> Question {
    var answers = wrong
    let index = max(0, min(slot, wrong.count))
    answers.insert(correct, at: index)
    return Question(
        id: id,
        prompt: prompt,
        answers: answers,
        correctIndex: index,
        category: category,
        difficulty: difficulty,
        pictureRecipe: art
    )
}
