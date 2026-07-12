// The build-time content linter, run as tests over the FULL bundled pack.
// A failing test here means the pack is unshippable.
import XCTest
import CouchCore
@testable import BlockheadEngine

final class PackLintTests: XCTestCase {

    // MARK: Full-pack lint

    func testFullPackPassesLinter() {
        let issues = PackLinter.lint(QuestionPack.all)
        XCTAssertTrue(issues.isEmpty, "Pack lint failed:\n" + issues.map(\.description).joined(separator: "\n"))
    }

    func testPackSizeMeetsV1Floor() {
        XCTAssertGreaterThanOrEqual(QuestionPack.all.count, 180)
    }

    func testEveryQuestionHasExactlyFourAnswersAndOneCorrect() {
        for question in QuestionPack.all {
            XCTAssertEqual(question.answers.count, 4, "\(question.id) must have 4 answers")
            XCTAssertTrue(question.answers.indices.contains(question.correctIndex), "\(question.id) correctIndex")
            // Exactly one correct by construction: the correct text appears once.
            let matches = question.answers.filter { $0 == question.correctAnswer }.count
            XCTAssertEqual(matches, 1, "\(question.id) correct answer text must be unique")
        }
    }

    func testLengthCapsHoldAcrossPack() {
        for question in QuestionPack.all {
            XCTAssertLessThanOrEqual(question.prompt.count, PackLinter.maxPromptLength, question.id)
            for answer in question.answers {
                XCTAssertLessThanOrEqual(answer.count, PackLinter.maxAnswerLength, "\(question.id): \(answer)")
            }
        }
    }

    func testDirectionBalanceWithinTolerance() {
        let pack = QuestionPack.all
        var counts = [0, 0, 0, 0]
        for question in pack { counts[question.correctIndex] += 1 }
        let ideal = Double(pack.count) / 4
        for (index, count) in counts.enumerated() {
            let deviation = abs(Double(count) - ideal) / ideal
            XCTAssertLessThanOrEqual(
                deviation, PackLinter.balanceTolerance,
                "direction \(Question.direction(forAnswerIndex: index)) count \(count) vs ideal \(ideal)"
            )
        }
    }

    func testPictureRecipesResolveToDemoArt() {
        let pictures = QuestionPack.all.filter(\.isPicture)
        XCTAssertGreaterThanOrEqual(pictures.count, 10, "need a healthy picture pool")
        for question in pictures {
            XCTAssertNotNil(DemoArt.recipe(id: question.pictureRecipe ?? ""), question.id)
        }
    }

    func testPoolsCoverTheEpisodeSlotPlan() {
        let pack = QuestionPack.all
        for slot in Set(EpisodePlanner.slotPlan) {
            let matching = pack.filter {
                EpisodePlanner.kind(of: $0) == slot.kind && $0.difficulty == slot.difficulty
            }
            let needed = EpisodePlanner.slotPlan.filter { $0 == slot }.count
            XCTAssertGreaterThanOrEqual(
                matching.count, needed * 3,
                "pool for \(slot.kind) d\(slot.difficulty) too thin (\(matching.count))"
            )
        }
    }

    // MARK: Linter behavior (negative cases)

    private func makeQuestion(
        id: String = "test-q",
        prompt: String = "A perfectly reasonable prompt?",
        answers: [String] = ["A", "B", "C", "D"],
        correctIndex: Int = 0,
        difficulty: Int = 1,
        pictureRecipe: String? = nil
    ) -> Question {
        Question(id: id, prompt: prompt, answers: answers, correctIndex: correctIndex,
                 category: .general, difficulty: difficulty, pictureRecipe: pictureRecipe)
    }

    func testLinterCatchesWrongAnswerCount() {
        let bad = makeQuestion(answers: ["A", "B", "C"])
        XCTAssertTrue(PackLinter.lint([bad]).contains { $0.message.contains("must be exactly 4") })
    }

    func testLinterCatchesOutOfRangeCorrectIndex() {
        let bad = makeQuestion(correctIndex: 4)
        XCTAssertTrue(PackLinter.lint([bad]).contains { $0.message.contains("out of range") })
    }

    func testLinterCatchesOverlongPromptAndAnswer() {
        let longPrompt = makeQuestion(prompt: String(repeating: "x", count: 91))
        XCTAssertFalse(PackLinter.lint([longPrompt]).isEmpty)
        let longAnswer = makeQuestion(answers: [String(repeating: "y", count: 27), "B", "C", "D"])
        XCTAssertFalse(PackLinter.lint([longAnswer]).isEmpty)
    }

    func testLinterCatchesDuplicatePromptsAndIDs() {
        let a = makeQuestion(id: "dup-1", prompt: "Same prompt?")
        let b = makeQuestion(id: "dup-2", prompt: "same prompt?")
        XCTAssertTrue(PackLinter.lint([a, b]).contains { $0.message == "duplicate prompt" })

        let c = makeQuestion(id: "dup-3", prompt: "First prompt?")
        let d = makeQuestion(id: "dup-3", prompt: "Second prompt?")
        XCTAssertTrue(PackLinter.lint([c, d]).contains { $0.message == "duplicate question id" })
    }

    func testLinterCatchesRepeatedAnswerText() {
        let bad = makeQuestion(answers: ["A", "a", "C", "D"])
        XCTAssertTrue(PackLinter.lint([bad]).contains { $0.message == "repeated answer text" })
    }

    func testLinterCatchesBadDifficultyAndUnknownRecipe() {
        let badDifficulty = makeQuestion(difficulty: 4)
        XCTAssertTrue(PackLinter.lint([badDifficulty]).contains { $0.message.contains("difficulty") })
        let badRecipe = makeQuestion(pictureRecipe: "not-a-recipe")
        XCTAssertTrue(PackLinter.lint([badRecipe]).contains { $0.message.contains("unknown DemoArt recipe") })
    }

    func testLinterCatchesDirectionImbalance() {
        // 24 questions, every correct answer up — maximally imbalanced.
        let skewed = (0..<24).map { index in
            makeQuestion(id: "skew-\(index)", prompt: "Skewed prompt number \(index)?")
        }
        XCTAssertFalse(PackLinter.balanceIssues(for: skewed).isEmpty)
    }
}
