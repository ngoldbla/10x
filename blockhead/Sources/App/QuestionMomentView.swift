// The question moment — the whole game. Prompt floats center over the void,
// four glass answer slabs hold the compass points, a GlassRing hugs the
// prompt. Flick = answer: the chosen slab lifts and locks, the others fall
// away, then the hall lighting delivers the verdict.
import SwiftUI
import CouchKit

struct QuestionMomentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            pictureLayer
            answerSlabs
            centerColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let label = model.soloProgressLabel {
                GlassChip(label).padding(48)
            }
        }
        .overlay(alignment: .bottom) {
            if model.route == .partyQuestion, let match = model.match {
                PartyScoreMeters(match: match)
                    .padding(.bottom, 26)
            }
        }
    }

    // MARK: Center: prompt + timer ring

    @ViewBuilder
    private var centerColumn: some View {
        if let question = model.activeQuestion {
            VStack(spacing: 36) {
                Text(question.prompt)
                    .couchText(CouchTypography.display)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.4)
                    .lineLimit(3)
                    .frame(maxWidth: 920)
                    .shadow(color: .black.opacity(0.7), radius: 18)
                TimerRing()
            }
        }
    }

    // MARK: The four slabs

    @ViewBuilder
    private var answerSlabs: some View {
        if let question = model.activeQuestion {
            ZStack {
                slab(question, .up)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 66)
                slab(question, .down)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, model.route == .partyQuestion ? 150 : 96)
                slab(question, .left)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 76)
                slab(question, .right)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 76)
            }
        }
    }

    private func slab(_ question: Question, _ direction: Direction4) -> some View {
        AnswerSlab(
            text: question.answer(for: direction),
            direction: direction,
            state: slabState(question, direction)
        )
    }

    private func slabState(_ question: Question, _ direction: Direction4) -> AnswerSlab.State {
        let index = Question.answerIndex(for: direction)
        switch model.moment {
        case .countdown:
            return .idle
        case .locked:
            return index == model.lastOutcome?.pickedIndex ? .picked : .dropped
        case .verdict:
            if index == question.correctIndex { return .reveal }
            if index == model.lastOutcome?.pickedIndex { return .wrongPick }
            return .dropped
        }
    }

    // MARK: Picture rounds — mosaic during the countdown, sharp on reveal

    @ViewBuilder
    private var pictureLayer: some View {
        if let question = model.activeQuestion, question.isPicture {
            ZStack {
                if let mosaic = model.pictureMosaic {
                    Image(decorative: mosaic, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(model.revealPicture ? 0 : 1)
                }
                if let sharp = model.pictureSharp {
                    Image(decorative: sharp, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(model.revealPicture ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(
                // Glass-dimmed edges so the prompt owns the center.
                RadialGradient(
                    colors: [.black.opacity(0.3), .black.opacity(0.82)],
                    center: .center, startRadius: 180, endRadius: 1100
                )
            )
            .animation(
                .easeOut(duration: model.reduceFlash ? 1.6 : 0.9),
                value: model.revealPicture
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Timer ring

private struct TimerRing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: model.moment != .countdown || model.isPaused
            )
        ) { timeline in
            GlassRing(progress: model.ringProgress(at: timeline.date))
        }
        .frame(width: 120, height: 120)
    }
}

// MARK: - Answer slab

struct AnswerSlab: View {
    enum State: Equatable { case idle, picked, dropped, reveal, wrongPick }

    let text: String
    let direction: Direction4
    let state: State

    var body: some View {
        content
            .padding(.horizontal, 44)
            .padding(.vertical, 26)
            .frame(minWidth: 260)
            .couchGlassInteractive(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 2)
            )
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
            .blur(radius: blur)
            .animation(.couchFast, value: state)
    }

    @ViewBuilder
    private var content: some View {
        let chevron = Image(systemName: chevronName)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.secondary)
            .opacity(0.65)
        let label = Text(text)
            .font(CouchTypography.body)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        switch direction {
        case .up: VStack(spacing: 10) { chevron; label }
        case .down: VStack(spacing: 10) { label; chevron }
        case .left: HStack(spacing: 16) { chevron; label }
        case .right: HStack(spacing: 16) { label; chevron }
        }
    }

    private var chevronName: String {
        switch direction {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        }
    }

    /// Outward unit vector for this compass position (screen coordinates).
    private var unit: CGSize {
        switch direction {
        case .up: CGSize(width: 0, height: -1)
        case .down: CGSize(width: 0, height: 1)
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        }
    }

    private var scale: CGFloat {
        switch state {
        case .picked: 1.12
        case .reveal: 1.10
        case .dropped: 0.92
        case .wrongPick: 0.96
        case .idle: 1.0
        }
    }

    private var offset: CGSize {
        switch state {
        case .dropped:
            CGSize(width: unit.width * 90, height: unit.height * 90)     // falls into the void
        case .reveal:
            CGSize(width: unit.width * -150, height: unit.height * -150) // glides toward center
        case .picked:
            CGSize(width: unit.width * -30, height: unit.height * -30)   // lifts and locks
        case .idle, .wrongPick:
            .zero
        }
    }

    private var opacity: Double {
        switch state {
        case .dropped: 0.05
        case .wrongPick: 0.25 // fades wrong-smoke
        default: 1
        }
    }

    private var blur: CGFloat { state == .dropped ? 6 : 0 }

    private var strokeColor: Color {
        switch state {
        case .picked: .white.opacity(0.5)
        case .reveal: Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.8)
        default: .white.opacity(0)
        }
    }
}
