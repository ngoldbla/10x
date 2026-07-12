// GameCanvasView — draws one game's abstract entity list into a SwiftUI
// Canvas. Retro content layer only: chunky sprites and flat shapes; all
// chrome above this is Liquid Glass via CouchKit.
import SwiftUI
import CouchKit
import CoreGraphics

/// Palette lane for shape entities, derived from the daily mutator's
/// paletteID over AsciiKit's fixed chunky-16 — so shapes and pixel sprites
/// share a universe. Hazards keep a constant warning tone.
struct GamePalette {
    let obstacle: Color
    let obstacleEdge: Color
    let hazard: Color
    let accent: Color

    init(paletteID: Int) {
        let ramp = AsciiPipeline.chunky16
        let base = ramp[(2 + paletteID) % ramp.count]
        let glow = ramp[(9 + paletteID * 3) % ramp.count]
        obstacle = Color(base.scaled(by: 0.55))
        obstacleEdge = Color(base)
        hazard = Color(RGB(224, 74, 60))
        accent = Color(glow)
    }
}

struct GameCanvasView: View {
    let game: GameID
    let entities: [Entity]
    let palette: GamePalette
    /// Today's mutator palette lane — picks the backdrop deterministically.
    let paletteID: Int
    let locker: SpriteLocker

    var body: some View {
        // Resolve locker content up front: the Canvas renderer closure only
        // captures immutable values, never the observable locker itself.
        let backdrop = locker.backdrop(paletteID: paletteID)
        let actors = locker.actors
        Canvas { context, size in
            let scaleX = size.width / World.width
            let scaleY = size.height / World.height

            func rect(_ e: Entity) -> CGRect {
                CGRect(
                    x: (e.x - e.width / 2) * scaleX,
                    y: size.height - (e.y + e.height / 2) * scaleY,
                    width: e.width * scaleX,
                    height: e.height * scaleY
                )
            }

            // Backdrop: dimmed mosaic of a landscape photo, under everything.
            if let backdrop {
                var bg = context
                bg.opacity = 0.34
                bg.draw(
                    Image(decorative: backdrop, scale: 1),
                    in: CGRect(origin: .zero, size: size)
                )
            }

            for entity in entities {
                draw(entity, in: rect(entity), context: context, actors: actors)
            }
        }
        .background(CouchPalette.void)
        .ignoresSafeArea()
    }

    // MARK: Entity dispatch

    private func draw(_ e: Entity, in rect: CGRect, context: GraphicsContext, actors: [CGImage]) {
        switch e.kind {
        case .hero, .segment, .pickup:
            drawSprite(e, in: rect, context: context, actors: actors)
        case .obstacle:
            drawObstacle(in: rect, context: context)
        case .hazard:
            drawHazard(e, in: rect, context: context)
        case .goal:
            drawGoal(in: rect, context: context)
        case .indicator:
            drawIndicator(e, in: rect, context: context)
        }
    }

    private func drawSprite(_ e: Entity, in rect: CGRect, context: GraphicsContext, actors: [CGImage]) {
        let sprite: CGImage? =
            (!actors.isEmpty && e.spriteSlot >= 0) ? actors[e.spriteSlot % actors.count] : nil
        if let sprite {
            var c = context
            c.translateBy(x: rect.midX, y: rect.midY)
            c.rotate(by: .degrees(-e.rotation)) // world CCW → screen
            if e.kind == .pickup {
                // Pickups shimmer so they read as "good" at a glance.
                c.addFilter(.shadow(color: palette.accent.opacity(0.9), radius: 10))
            }
            c.draw(
                Image(decorative: sprite, scale: 1),
                in: CGRect(x: -rect.width / 2, y: -rect.height / 2,
                           width: rect.width, height: rect.height)
            )
        } else {
            // Locker still warming up: clean placeholder disc.
            let disc = Path(ellipseIn: rect)
            context.fill(disc, with: .color(palette.accent.opacity(0.9)))
            context.stroke(disc, with: .color(.white.opacity(0.7)), lineWidth: 2)
        }
    }

    private func drawObstacle(in rect: CGRect, context: GraphicsContext) {
        let path = Path(roundedRect: rect, cornerRadius: min(10, rect.width * 0.18))
        context.fill(path, with: .color(palette.obstacle))
        context.stroke(path, with: .color(palette.obstacleEdge.opacity(0.85)), lineWidth: 3)
    }

    private func drawHazard(_ e: Entity, in rect: CGRect, context: GraphicsContext) {
        var c = context
        c.translateBy(x: rect.midX, y: rect.midY)
        c.rotate(by: .degrees(-e.rotation + 45)) // diamond spin
        let half = rect.width / 2
        let square = CGRect(x: -half, y: -half, width: rect.width, height: rect.width)
        let path = Path(roundedRect: square, cornerRadius: rect.width * 0.16)
        c.fill(path, with: .color(palette.hazard))
        c.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 2)
    }

    private func drawGoal(in rect: CGRect, context: GraphicsContext) {
        // The cup: dark well + accent lip + a little flag.
        let cup = Path(ellipseIn: rect)
        context.fill(cup, with: .color(.black.opacity(0.92)))
        context.stroke(cup, with: .color(palette.accent), lineWidth: 3)
        var flag = Path()
        flag.move(to: CGPoint(x: rect.midX, y: rect.midY))
        flag.addLine(to: CGPoint(x: rect.midX, y: rect.minY - rect.height * 1.4))
        context.stroke(flag, with: .color(.white.opacity(0.8)), lineWidth: 3)
        var pennant = Path()
        let top = rect.minY - rect.height * 1.4
        pennant.move(to: CGPoint(x: rect.midX, y: top))
        pennant.addLine(to: CGPoint(x: rect.midX + rect.width * 0.9, y: top + rect.height * 0.35))
        pennant.addLine(to: CGPoint(x: rect.midX, y: top + rect.height * 0.7))
        pennant.closeSubpath()
        context.fill(pennant, with: .color(palette.accent))
    }

    private func drawIndicator(_ e: Entity, in rect: CGRect, context: GraphicsContext) {
        switch game {
        case .quadrant:
            // Zone plate; the occupied zone glows faintly.
            let plate = Path(roundedRect: rect.insetBy(dx: 10, dy: 10), cornerRadius: 28)
            if e.value > 0.5 {
                context.fill(plate, with: .color(palette.accent.opacity(0.10)))
                context.stroke(plate, with: .color(palette.accent.opacity(0.55)), lineWidth: 2)
            } else {
                context.stroke(plate, with: .color(.white.opacity(0.10)), lineWidth: 2)
            }
        case .putt:
            drawAimSweep(e, in: rect, context: context)
        default:
            break
        }
    }

    /// Putt's single-axis aim: a ray sweeping around the ball, plus a charge
    /// ring while holding.
    private func drawAimSweep(_ e: Entity, in rect: CGRect, context: GraphicsContext) {
        var c = context
        c.translateBy(x: rect.midX, y: rect.midY)
        c.rotate(by: .degrees(-e.rotation))
        var ray = Path()
        ray.move(to: CGPoint(x: rect.width * 0.18, y: 0))
        ray.addLine(to: CGPoint(x: rect.width / 2, y: 0))
        c.stroke(
            ray,
            with: .color(palette.accent.opacity(0.95)),
            style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 12])
        )
        var tip = Path()
        let tipX = rect.width / 2
        tip.move(to: CGPoint(x: tipX + 12, y: 0))
        tip.addLine(to: CGPoint(x: tipX - 6, y: -9))
        tip.addLine(to: CGPoint(x: tipX - 6, y: 9))
        tip.closeSubpath()
        c.fill(tip, with: .color(palette.accent))

        if e.value > 0 {
            // Charge ring fills clockwise with power.
            let ringRect = CGRect(
                x: rect.midX - rect.width * 0.16, y: rect.midY - rect.width * 0.16,
                width: rect.width * 0.32, height: rect.width * 0.32
            )
            var ring = Path()
            ring.addArc(
                center: CGPoint(x: ringRect.midX, y: ringRect.midY),
                radius: ringRect.width / 2,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 + 360 * e.value),
                clockwise: false
            )
            context.stroke(
                ring,
                with: .color(.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: 7, lineCap: .round)
            )
        }
    }
}
