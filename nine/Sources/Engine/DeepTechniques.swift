// DeepTechniques.swift — the Tempest and Abyss reasoning (PRD-25).
//
// Three techniques, and one rule decided which three: **a technique Nine cannot
// say in one sentence has no business in a band Nine sells.** PROGRAM-2.0 puts
// it as "stop before full chains — explanation complexity is the limit", and
// that is a product constraint, not a difficulty one. Everything here is a
// finite pattern with a fixed number of named cells:
//
//   • **Skyscraper** (Tempest) — two lines, one shared cross, two roofs.
//   • **XY-wing** (Tempest) — a pivot and two pincers, three digits.
//   • **Simple coloring** (Abyss) — one digit's strong links, two colours,
//     and the two rules that fall out of "one colour is true".
//
// W-Wing is deliberately absent; PRD-25 §3.1 records why.
//
// The soundness rule is `VariantTechniques.swift`'s, restated because it is the
// one that matters most here: a technique may only place a digit that is forced
// and may only eliminate a candidate that is impossible. An over-eager
// elimination is not a bug that shows up as a wrong answer later — it is a
// *wrong proof* that the uniqueness verifier will happily agree with, because
// the verifier is downstream of this file. Every deduction below is written as
// "at least one of these is true, and anything seeing all of them is not".
//
// All three are single-digit or three-digit patterns over `state.candidates`
// and read `context.peers`/`context.units`, so a variant board gets them free —
// the same property PRD-23 bought for the coach.
import Foundation
import CouchCore

extension LogicSolver {

    // MARK: - Skyscraper

    /// Two lines in which a digit has exactly two homes, sharing one cross
    /// coordinate. The shared column can hold the digit at most once, so at
    /// least one of the two lines puts it at its *other* end — and anything
    /// seeing both of those ends cannot be the digit.
    ///
    /// The pattern is an X-wing with one corner slid sideways, which is exactly
    /// how it reads on the board and exactly why it earns its own name: the
    /// fish loop above cannot see it, because the two cross sets are not equal.
    static func skyscraper(_ state: CandidateState) -> SolveStep? {
        for baseIsRow in [true, false] {
            for digit in 1...9 {
                let bit = Sudoku.bit(digit)
                // Cross positions of the digit, per base line, for the lines
                // that have exactly two. Anything else is a single or a mess.
                var homes = [[Int]](repeating: [], count: 9)
                for base in 0..<9 {
                    for cross in 0..<9 {
                        let cell = baseIsRow ? base * 9 + cross : cross * 9 + base
                        if state.candidates[cell] & bit != 0 { homes[base].append(cross) }
                    }
                }
                let pairs = (0..<9).filter { homes[$0].count == 2 }
                guard pairs.count >= 2 else { continue }

                for i in 0..<(pairs.count - 1) {
                    for j in (i + 1)..<pairs.count {
                        let b1 = pairs[i], b2 = pairs[j]
                        // Exactly one shared cross: two shared is an X-wing
                        // (already found at a lower rank), none is no link.
                        let shared = Set(homes[b1]).intersection(homes[b2])
                        guard shared.count == 1, let base = shared.first else { continue }
                        guard let roof1 = homes[b1].first(where: { $0 != base }),
                              let roof2 = homes[b2].first(where: { $0 != base }) else { continue }

                        let cell = { (line: Int, cross: Int) in
                            baseIsRow ? line * 9 + cross : cross * 9 + line
                        }
                        let baseCells = [cell(b1, base), cell(b2, base)]
                        let roofCells = [cell(b1, roof1), cell(b2, roof2)]

                        // "At least one roof is the digit" only follows if the
                        // two base cells really are in one unit. They share a
                        // cross coordinate, which is a line in classic — but a
                        // variant context can widen peers, never narrow them,
                        // so asking `peers` is the version that stays true.
                        guard state.context.peers[baseCells[0]].contains(baseCells[1])
                        else { continue }

                        let pattern = Set(baseCells + roofCells)
                        let seeing = Set(state.context.peers[roofCells[0]])
                            .intersection(state.context.peers[roofCells[1]])
                        var eliminations: [Elimination] = []
                        for victim in seeing.sorted()
                        where !pattern.contains(victim) && state.candidates[victim] & bit != 0 {
                            eliminations.append(Elimination(cell: victim, digit: digit))
                        }
                        guard !eliminations.isEmpty else { continue }

                        return SolveStep(
                            technique: .skyscraper,
                            cells: baseCells + roofCells,
                            digits: [digit],
                            eliminations: eliminations,
                            roles: [.base, .base, .cover, .cover],
                            chain: [
                                StepLink(from: baseCells[0], to: roofCells[0], isStrong: true),
                                StepLink(from: baseCells[0], to: baseCells[1], isStrong: false),
                                StepLink(from: baseCells[1], to: roofCells[1], isStrong: true),
                            ]
                        )
                    }
                }
            }
        }
        return nil
    }

    // MARK: - XY-wing

    /// A pivot holding exactly `{x, y}`, and two pincers it can see holding
    /// exactly `{x, z}` and `{y, z}`. Whichever way the pivot falls, one pincer
    /// is forced to `z` — so nothing that sees both pincers can be `z`.
    ///
    /// Three bi-value cells and one digit of conclusion: the shortest chain
    /// that is still worth a name, and the last one this app will narrate.
    static func xyWing(_ state: CandidateState) -> SolveStep? {
        let bivalue = (0..<81).filter {
            state.values[$0] == 0 && state.candidates[$0].nonzeroBitCount == 2
        }
        guard bivalue.count >= 3 else { return nil }
        let isBivalue = Set(bivalue)

        for pivot in bivalue {
            let pair = Sudoku.digits(in: state.candidates[pivot])
            let x = pair[0], y = pair[1]
            let seen = state.context.peers[pivot].filter { isBivalue.contains($0) }

            for a in seen {
                let maskA = state.candidates[a]
                // The pincer on `x` must hold x and not y; the third digit is z.
                guard maskA & Sudoku.bit(x) != 0, maskA & Sudoku.bit(y) == 0 else { continue }
                guard let z = Sudoku.digits(in: maskA).first(where: { $0 != x }) else { continue }
                let wanted = Sudoku.bit(y) | Sudoku.bit(z)

                for b in seen where b != a && state.candidates[b] == wanted {
                    let pattern: Set<Int> = [pivot, a, b]
                    let zBit = Sudoku.bit(z)
                    let seeing = Set(state.context.peers[a])
                        .intersection(state.context.peers[b])
                    var eliminations: [Elimination] = []
                    for victim in seeing.sorted()
                    where !pattern.contains(victim) && state.candidates[victim] & zBit != 0 {
                        eliminations.append(Elimination(cell: victim, digit: z))
                    }
                    guard !eliminations.isEmpty else { continue }

                    return SolveStep(
                        technique: .xyWing,
                        // Pivot first: the sentence names it first, and the
                        // narration rings it before the pincers breathe in.
                        cells: [pivot, a, b],
                        // `digits[0]` is the conclusion; the two the pivot is
                        // torn between follow. Every consumer reads position 0.
                        digits: [z, x, y],
                        eliminations: eliminations,
                        roles: [.pivot, .cover, .cover],
                        chain: [
                            StepLink(from: pivot, to: a, isStrong: false),
                            StepLink(from: pivot, to: b, isStrong: false),
                        ]
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Simple coloring

    /// One digit, its strong links, and two colours.
    ///
    /// A *strong link* is a unit in which the digit has exactly two homes: one
    /// of them is the digit, necessarily. Colour a connected component of those
    /// links alternately and exactly one colour is the true one. Two rules
    /// follow, and this implements both:
    ///
    ///   • **wrap** — two cells of the *same* colour see each other. They cannot
    ///     both be the digit, so that colour is false everywhere. Every cell of
    ///     it loses the candidate. (This is the stronger rule, so it is tried
    ///     first.)
    ///   • **trap** — a cell outside the chain sees both colours. One of the two
    ///     is true, so that cell cannot be the digit.
    ///
    /// Stops here, on purpose: multi-digit chains, forcing nets and anything
    /// with a branch produce a proof no single sentence can carry, and PRD-25's
    /// limit is explanation, not difficulty.
    static func simpleColoring(_ state: CandidateState) -> SolveStep? {
        for digit in 1...9 {
            let bit = Sudoku.bit(digit)

            // Strong links: the units where this digit has exactly two homes.
            var links: [(Int, Int)] = []
            var adjacency = [Int: [Int]]()
            for unit in state.context.units {
                let homes = unit.filter { state.candidates[$0] & bit != 0 }
                guard homes.count == 2 else { continue }
                let (a, b) = (homes[0], homes[1])
                // The same pair can be strongly linked by a row and a box; one
                // edge is enough, and a duplicate would draw twice.
                if adjacency[a]?.contains(b) == true { continue }
                links.append((a, b))
                adjacency[a, default: []].append(b)
                adjacency[b, default: []].append(a)
            }
            guard !links.isEmpty else { continue }

            // Two-colour each component. Ascending seed order so the answer is
            // a function of the position and nothing else.
            var colour = [Int: Bool]()
            var components: [[Int]] = []
            for seed in adjacency.keys.sorted() where colour[seed] == nil {
                colour[seed] = true
                var component = [seed]
                var frontier = [seed]
                while let cell = frontier.popLast() {
                    for next in (adjacency[cell] ?? []).sorted() where colour[next] == nil {
                        colour[next] = !(colour[cell] ?? true)
                        component.append(next)
                        frontier.append(next)
                    }
                }
                components.append(component.sorted())
            }

            for component in components {
                let componentEdges = links.filter { component.contains($0.0) }
                // A strong link joining two cells of one colour means the
                // component has an odd cycle, and then "exactly one colour is
                // true" — the premise both rules below rest on — is false. It
                // takes an already-contradictory position to happen, and the
                // coach is allowed to meet one of those, so this is a guard
                // rather than an assertion.
                guard componentEdges.allSatisfy({ colour[$0.0] != colour[$0.1] }) else { continue }
                let componentLinks = componentEdges
                    .map { StepLink(from: $0.0, to: $0.1, isStrong: true) }
                let onside = component.filter { colour[$0] == true }
                let offside = component.filter { colour[$0] == false }

                // Wrap. A colour with two mutually-visible cells is false whole.
                for side in [onside, offside] where side.count >= 2 {
                    var clashes = false
                    outer: for i in 0..<(side.count - 1) {
                        for j in (i + 1)..<side.count
                        where state.context.peers[side[i]].contains(side[j]) {
                            clashes = true
                            break outer
                        }
                    }
                    guard clashes else { continue }
                    let doomed = Set(side)
                    return SolveStep(
                        technique: .simpleColoring,
                        cells: component,
                        digits: [digit],
                        eliminations: side.map { Elimination(cell: $0, digit: digit) },
                        // The false colour's cells are the victims; the rest of
                        // the chain is what proved them false.
                        roles: component.map { doomed.contains($0) ? .victim : .base },
                        chain: componentLinks
                    )
                }

                // Trap. Anything outside the chain that sees both colours.
                guard !onside.isEmpty, !offside.isEmpty else { continue }
                var sees = Set(state.context.peers[onside[0]])
                for cell in onside.dropFirst() {
                    sees.formUnion(state.context.peers[cell])
                }
                var seesOff = Set(state.context.peers[offside[0]])
                for cell in offside.dropFirst() {
                    seesOff.formUnion(state.context.peers[cell])
                }
                let inChain = Set(component)
                var eliminations: [Elimination] = []
                for victim in sees.intersection(seesOff).sorted()
                where !inChain.contains(victim) && state.candidates[victim] & bit != 0 {
                    eliminations.append(Elimination(cell: victim, digit: digit))
                }
                guard !eliminations.isEmpty else { continue }

                return SolveStep(
                    technique: .simpleColoring,
                    cells: component,
                    digits: [digit],
                    eliminations: eliminations,
                    roles: component.map { colour[$0] == true ? .base : .cover },
                    chain: componentLinks
                )
            }
        }
        return nil
    }
}
