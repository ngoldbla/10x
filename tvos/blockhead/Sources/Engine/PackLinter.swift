// Build-time content linter. Runs as tests over the full bundled pack —
// a malformed question is unshippable by construction (PRD §5).
import Foundation
import CouchCore

/// One problem the linter found with a question (or with the pack shape).
public struct LintIssue: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// Offending question id, or "pack" for pack-level issues.
    public let questionID: String
    public let message: String

    public init(questionID: String, message: String) {
        self.questionID = questionID
        self.message = message
    }

    public var description: String { "[\(questionID)] \(message)" }
}

public enum PackLinter {
    /// Prompt cap for 3-meter legibility at display size.
    public static let maxPromptLength = 90
    /// Answer cap so slabs stay one comfortable line.
    public static let maxAnswerLength = 26
    /// Correct-direction share may deviate at most ±15% from the ideal 25%.
    public static let balanceTolerance = 0.15

    /// Lints a pack. An empty result means the pack is shippable.
    public static func lint(_ pack: [Question]) -> [LintIssue] {
        var issues: [LintIssue] = []
        var seenIDs = Set<String>()
        var seenPrompts = Set<String>()

        for question in pack {
            let id = question.id

            if id.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(LintIssue(questionID: "pack", message: "question with empty id"))
            }
            if !seenIDs.insert(id).inserted {
                issues.append(LintIssue(questionID: id, message: "duplicate question id"))
            }

            let prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.isEmpty {
                issues.append(LintIssue(questionID: id, message: "empty prompt"))
            }
            if question.prompt.count > maxPromptLength {
                issues.append(LintIssue(
                    questionID: id,
                    message: "prompt is \(question.prompt.count) chars (max \(maxPromptLength))"
                ))
            }
            if !seenPrompts.insert(normalized(question.prompt)).inserted {
                issues.append(LintIssue(questionID: id, message: "duplicate prompt"))
            }

            if question.answers.count != 4 {
                issues.append(LintIssue(
                    questionID: id,
                    message: "has \(question.answers.count) answers (must be exactly 4)"
                ))
            }
            if !question.answers.indices.contains(question.correctIndex) {
                issues.append(LintIssue(
                    questionID: id,
                    message: "correctIndex \(question.correctIndex) out of range"
                ))
            }
            for answer in question.answers {
                let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    issues.append(LintIssue(questionID: id, message: "empty answer"))
                }
                if answer.count > maxAnswerLength {
                    issues.append(LintIssue(
                        questionID: id,
                        message: "answer \"\(answer)\" is \(answer.count) chars (max \(maxAnswerLength))"
                    ))
                }
            }
            if Set(question.answers.map(normalized)).count != question.answers.count {
                issues.append(LintIssue(questionID: id, message: "repeated answer text"))
            }

            if !(1...3).contains(question.difficulty) {
                issues.append(LintIssue(
                    questionID: id,
                    message: "difficulty \(question.difficulty) outside 1…3"
                ))
            }

            if let recipe = question.pictureRecipe, DemoArt.recipe(id: recipe) == nil {
                issues.append(LintIssue(
                    questionID: id,
                    message: "unknown DemoArt recipe \"\(recipe)\""
                ))
            }
        }

        issues.append(contentsOf: balanceIssues(for: pack))
        return issues
    }

    /// Direction balance: each direction's share of correct answers must stay
    /// within ±15% (relative) of the ideal 25%. Only checked on packs big
    /// enough for the statistic to mean anything.
    public static func balanceIssues(for pack: [Question]) -> [LintIssue] {
        guard pack.count >= 20 else { return [] }
        var counts = [0, 0, 0, 0]
        for question in pack where question.answers.indices.contains(question.correctIndex) {
            counts[question.correctIndex] += 1
        }
        let ideal = Double(pack.count) / 4
        var issues: [LintIssue] = []
        for (index, count) in counts.enumerated() {
            let deviation = abs(Double(count) - ideal) / ideal
            if deviation > balanceTolerance {
                let direction = Question.direction(forAnswerIndex: index)
                issues.append(LintIssue(
                    questionID: "pack",
                    message: "direction \(direction.rawValue) holds \(count) of \(pack.count) correct answers (ideal \(Int(ideal)), tolerance ±15%)"
                ))
            }
        }
        return issues
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
