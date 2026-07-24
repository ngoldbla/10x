// PadKit — the one place an extended gamepad becomes intent (PRD-5 §4 Step 1).
// Sibling to RemoteKit: controllers are a suite asset (Blockhead and Cartridge
// will want this — see COUCHKIT-ASKS). Apps set `onGesture`/`onConnectionChange`
// and never touch a raw `GCController`.
//
// Two hard rules that keep PadKit and RemoteKit from fighting over the bus:
//   • PadKit filters STRICTLY to `extendedGamepad` profiles. The Siri Remote is
//     a `GCController` too, but it exposes only a `microGamepad` — RemoteKit owns
//     it. The two readers must never both claim a device (PRD-5 §5, risk 1).
//   • Never assume `GCController.current`. Two-controller households flap that
//     value; PadKit tracks its own adopted device and walks `GCController.controllers()`.
//
// The right stick *is* the flick rose: one deflection per digit, reusing
// CouchCore's `FlickClassifier` geometry with the never-misfire covenant — the
// deflection must cross 0.75 magnitude and *return to rest* to register, and an
// ambiguous diagonal reports its two candidate petals for the ghost-rose
// shimmer instead of placing (the ask CouchKit never delivered for the Siri
// Remote, COUCHKIT-ASKS #1 — it works here because we own the reader). The left
// stick is analog momentum: deflection magnitude drives a cursor repeat-rate
// curve so a full push glides across a box and a feathered push steps one cell.
//
// Guard split (PRD-5 Phase 4): the grammar below the reader — `PadButton`,
// `PadGesture`, `PadMomentum`/`classifyStick`, and `PadButtonSampler` — is pure
// Foundation + CouchCore, so it lives OUTSIDE the `#if os(tvOS)` and is
// exercised by CouchKitTests on the Mac (the simulator can never pair a
// controller — PRD-5 §5). Only the device-facing `PadReader`/`PadHaptics` stay
// tvOS-guarded.
import Foundation
import CouchCore

// MARK: - Gestures

/// The pad's face / shoulder buttons, named by their PRD-5 §2.1 role rather
/// than a vendor glyph (Cross/Circle/Square/Triangle on DualSense; A/B/X/Y on
/// Xbox map to the same positions through GameController's profile).
public enum PadButton: Sendable, Equatable, Hashable {
    case cross     // place-into-rose (learning mode) / confirm
    case circle    // erase user entry / cancel rose
    case square    // sticky pencil toggle
    case triangle  // same-number highlight toggle
    case r3        // right-stick click → place 5 (center petal)
    case l1        // previous empty cell
    case r1        // next empty cell
    case l2        // peek (hold): dim all but the highlighted kind
    case r2        // peek alias of L2 (hold) — first-class R2 (PRD-5 Phase 3)
    case options   // prefs sheet
}

// Deliberately unmapped (PRD-5 Phase 3, documented not forgotten):
//   • PS / `buttonHome` — system-reserved (tvOS routes it to the home screen);
//     claiming it risks App Review and fights the OS. Left untouched.
//   • Touchpad click — vendor-specific element naming would break the Xbox
//     covenant; deferred.
//   • Adaptive-trigger resistance — hardware-tuning cost outweighs the payoff
//     for a sudoku; deferred.

/// Declarative gesture intents an app subscribes to. The board never sees a
/// raw axis — only the classified intent.
public enum PadGesture: Sendable, Equatable {
    /// A single cursor step. `glide` is true when it came from left-stick
    /// momentum (the board ticks a box detent as the glide crosses a box) and
    /// false for a d-pad single-step (the precision fallback).
    case move(Direction4, glide: Bool)
    /// Right-stick flick placed a digit by rose direction (up-left=1 … down-right=9).
    case flick(Direction8OrCenter)
    /// The stroke fell in the forgiveness cone between two petals — shimmer
    /// both candidates in a ghost rose and place nothing (never misfire).
    case flickAmbiguous(Direction8OrCenter, Direction8OrCenter)
    /// A button was pressed.
    case button(PadButton)
    /// A held button was released (only L2 peek cares; others ignore it).
    case buttonUp(PadButton)
    /// An extended gamepad became the active device.
    case connect
    /// The active device dropped (board freezes under the reconnect veil).
    case disconnect
}

// MARK: - Momentum curve (pure)

/// Turns a left-stick deflection stream into discrete 4-way cursor steps with
/// analog momentum (PRD-5 §2.1): below the deadzone nothing moves; a feathered
/// push steps one cell and rests; a full push accelerates into a box-crossing
/// glide. Pure and `Sendable` so the cadence is unit-checkable without a device
/// (the simulator can never pair a controller — PRD-5 §5).
public struct PadMomentum: Sendable, Equatable {
    /// Sticks report noise near center; ignore anything under this magnitude.
    public var deadzone: Double
    /// Cells per second at full deflection — fast enough to cross a 3-cell box
    /// in a glide, slow enough to read.
    public var maxRate: Double
    /// Deflection→rate shaping. >1 keeps feathered pushes gentle (one cell at a
    /// time) while full pushes ramp hard.
    public var curve: Double

    private var accumulator: Double
    private var lastDirection: Direction4?

    public init(deadzone: Double = 0.20, maxRate: Double = 11, curve: Double = 2.2) {
        self.deadzone = deadzone
        self.maxRate = maxRate
        self.curve = curve
        self.accumulator = 0
        self.lastDirection = nil
    }

    /// The dominant 4-way direction of a deflection past the deadzone, or nil.
    /// +y is UP (GameController's stick convention), so screen-up is +y.
    public static func direction(x: Double, y: Double, deadzone: Double) -> Direction4? {
        guard hypot(x, y) >= deadzone else { return nil }
        if abs(x) >= abs(y) {
            return x >= 0 ? .right : .left
        } else {
            return y >= 0 ? .up : .down
        }
    }

    /// Feed one frame of stick deflection; returns whole cursor steps to apply
    /// this frame (usually zero or one; several while gliding at full tilt).
    public mutating func accumulate(x: Double, y: Double, dt: Double) -> [Direction4] {
        guard let direction = Self.direction(x: x, y: y, deadzone: deadzone) else {
            // Back to rest: drop the accumulator so the next push starts crisp,
            // and re-arm an instant first step.
            accumulator = 0
            lastDirection = nil
            return []
        }
        // A change of direction fires immediately and restarts the cadence, so
        // the cursor never lags a deliberate flick of the stick.
        if direction != lastDirection {
            lastDirection = direction
            accumulator = 1
        }
        let magnitude = hypot(x, y)
        let normalized = min(1, max(0, (magnitude - deadzone) / (1 - deadzone)))
        let rate = pow(normalized, curve) * maxRate
        accumulator += rate * dt
        var steps: [Direction4] = []
        while accumulator >= 1 {
            steps.append(direction)
            accumulator -= 1
        }
        return steps
    }
}

// MARK: - Right-stick classification (pure)

extension PadMomentum {
    /// Outcome of a completed right-stick deflection (already gated on the 0.75
    /// magnitude + return-to-rest covenant by the reader).
    public enum StickFlick: Sendable, Equatable {
        case direction(Direction8OrCenter)
        case ambiguous(Direction8OrCenter, Direction8OrCenter)
    }

    /// Classify a right-stick peak deflection into a rose direction, reusing
    /// `FlickClassifier`'s 8-way geometry and forgiveness cone. Inside the cone
    /// the two adjacent petals are reported so the ghost rose can shimmer both —
    /// PadKit never places on an ambiguous angle. +y is UP.
    public static func classifyStick(
        dx: Double, dy: Double, cone: Double = FlickThresholds.standard.ambiguityCone
    ) -> StickFlick {
        let sectors: [Direction8OrCenter] = [
            .right, .upRight, .up, .upLeft, .left, .downLeft, .down, .downRight,
        ]
        let deg = FlickClassifier.angleDegrees(dx: dx, dy: dy)
        let m = deg.truncatingRemainder(dividingBy: 45)
        if abs(m - 22.5) < cone {
            let lower = Int(deg / 45) % 8
            let upper = (lower + 1) % 8
            return .ambiguous(sectors[lower], sectors[upper])
        }
        return .direction(sectors[Int((deg / 45).rounded()) % 8])
    }
}

// MARK: - Button sampler (pure)

/// One frame of button state, read from the live gamepad each poll tick. Plain
/// `Bool`s plus the raw d-pad axes so the sampler is pure and Mac-testable —
/// no `GCExtendedGamepad` leaks into the grammar layer.
public struct PadButtonFrame: Sendable, Equatable {
    public var cross: Bool
    public var circle: Bool
    public var square: Bool
    public var triangle: Bool
    public var l1: Bool
    public var r1: Bool
    public var l2: Bool
    public var r2: Bool
    public var r3: Bool
    public var options: Bool
    public var dpadX: Double
    public var dpadY: Double

    public init(
        cross: Bool = false, circle: Bool = false, square: Bool = false,
        triangle: Bool = false, l1: Bool = false, r1: Bool = false,
        l2: Bool = false, r2: Bool = false, r3: Bool = false,
        options: Bool = false, dpadX: Double = 0, dpadY: Double = 0
    ) {
        self.cross = cross; self.circle = circle; self.square = square
        self.triangle = triangle; self.l1 = l1; self.r1 = r1
        self.l2 = l2; self.r2 = r2; self.r3 = r3; self.options = options
        self.dpadX = dpadX; self.dpadY = dpadY
    }
}

/// Turns a stream of per-frame button snapshots into discrete `PadGesture`s by
/// edge detection — the same job the old `pressedChangedHandler`s did, but on
/// the poll path. Unifying every button onto polling is the PRD-5 tvOS-controller
/// fix: a re-connect or profile replacement can never strand a handler on a dead
/// profile object, because each tick re-reads the live `isPressed` (real Apple
/// TV symptom: sticks worked, buttons didn't). Pure/`Sendable` so
/// `PadButtonSamplerTests` pins every edge without a device.
public struct PadButtonSampler: Sendable {
    private var last = PadButtonFrame()
    private var lastDpad: Direction4?

    public init() {}

    /// Forget all prior state (call on adopt / teardown so the first frame after
    /// a fresh device can't read a rising edge against a stale `true`).
    public mutating func reset() {
        last = PadButtonFrame()
        lastDpad = nil
    }

    /// Feed one frame; return the gestures its edges imply this tick.
    ///
    /// Edge policy:
    ///   • Rising edge (was up, now down) → `.button(b)` for EVERY button — the
    ///     press is the intent for taps and the *start* of a hold alike.
    ///   • Falling edge (was down, now up) → `.buttonUp(b)` only for the held
    ///     buttons the grammar cares about: Circle (tap-undo vs hold-erase) and
    ///     the L2/R2 peek. Emitting `.buttonUp` for the rest would be dead noise.
    ///   • D-pad single-steps on the *transition into* a direction using the
    ///     same 0.5 deadzone the old `handleDpad` used; holding a direction does
    ///     not repeat (that is the analog left stick's job).
    public mutating func sample(_ frame: PadButtonFrame) -> [PadGesture] {
        var out: [PadGesture] = []
        func rise(_ now: Bool, _ was: Bool, _ button: PadButton) {
            if now && !was { out.append(.button(button)) }
        }
        rise(frame.cross, last.cross, .cross)
        rise(frame.circle, last.circle, .circle)
        rise(frame.square, last.square, .square)
        rise(frame.triangle, last.triangle, .triangle)
        rise(frame.l1, last.l1, .l1)
        rise(frame.r1, last.r1, .r1)
        rise(frame.l2, last.l2, .l2)
        rise(frame.r2, last.r2, .r2)
        rise(frame.r3, last.r3, .r3)
        rise(frame.options, last.options, .options)

        func fall(_ now: Bool, _ was: Bool, _ button: PadButton) {
            if !now && was { out.append(.buttonUp(button)) }
        }
        fall(frame.circle, last.circle, .circle)
        fall(frame.l2, last.l2, .l2)
        fall(frame.r2, last.r2, .r2)

        if let direction = PadMomentum.direction(x: frame.dpadX, y: frame.dpadY, deadzone: 0.5) {
            if direction != lastDpad {
                lastDpad = direction
                out.append(.move(direction, glide: false))
            }
        } else {
            lastDpad = nil
        }

        last = frame
        return out
    }
}

// MARK: - Controller haptics provider
#if os(tvOS)
#if canImport(GameController)
import GameController
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif
import os

#if canImport(GameController) && canImport(CoreHaptics)
/// Vends and caches a CoreHaptics engine per locality from the controller's
/// `GCDeviceHaptics`, with the exact create-at-need lifecycle `AfterglowHaptics`
/// proved on iPhone: build the engine the first time a locality is asked for,
/// hold it, and tear everything down on disconnect. The *patterns* are the
/// caller's (Nine plays `AfterglowScore` through these engines) — PadKit only
/// owns the engine plumbing, so CouchKit never depends on an app's score.
@MainActor
public final class PadHaptics {
    private var engines: [GCHapticsLocality: CHHapticEngine] = [:]
    fileprivate weak var controller: GCController?

    public init() {}

    /// A started engine for `locality`, created on first ask. Returns nil when
    /// the device has no haptics (Xbox pads with no rumble, or none paired) —
    /// callers swallow the nil, exactly as the celebration swallows a throw.
    public func engine(for locality: GCHapticsLocality = .default) -> CHHapticEngine? {
        if let existing = engines[locality] { return existing }
        guard let haptics = controller?.haptics else { return nil }
        guard haptics.supportedLocalities.contains(locality) || locality == .default else { return nil }
        guard let engine = haptics.createEngine(withLocality: locality) else { return nil }
        do {
            try engine.start()
        } catch {
            return nil
        }
        engines[locality] = engine
        return engine
    }

    /// Cut every engine (disconnect / backgrounding). Safe to call twice.
    public func stopAll() {
        for engine in engines.values { engine.stop() }
        engines.removeAll()
    }
}
#endif

// MARK: - Reader

/// Observes `GCController` connect/disconnect, adopts a single extended gamepad,
/// and turns its sticks/d-pad/buttons into `PadGesture`s. Inert until a device
/// pairs — tvOS and iOS builds are byte-identical when no controller ever
/// connects (PRD-5 §6, item 10).
@MainActor
public final class PadReader {
    /// Board-grammar intents (the active screen owns this).
    public var onGesture: (@MainActor (PadGesture) -> Void)?
    /// Connection edges (the app model owns this — drives the shelf card and
    /// the reconnect veil, independent of who is reading gestures right now).
    public var onConnectionChange: (@MainActor (Bool) -> Void)?

    /// Whether an extended gamepad is currently adopted.
    public private(set) var isConnected = false

    #if canImport(GameController) && canImport(CoreHaptics)
    /// Per-locality haptic engines for the adopted device.
    public let haptics = PadHaptics()
    #endif

    /// Cone width for right-stick ambiguity (degrees). The never-misfire dial.
    public var ambiguityCone = FlickThresholds.standard.ambiguityCone

    /// Turns on os.Logger tracing (adopt / connect / gesture emission) and keeps
    /// the poll-edge counters `debugSnapshot()` reports live. Default off — the
    /// `--pad-probe` launch arg flips it for the DEBUG pad-probe HUD (PRD-5
    /// Phase 0). Costs nothing when off.
    public var diagnosticsEnabled = false

    #if canImport(GameController)
    private var controller: GCController?
    private var connectObserver: (any NSObjectProtocol)?
    private var disconnectObserver: (any NSObjectProtocol)?
    private var pollTask: Task<Void, Never>?

    private var momentum = PadMomentum()
    /// Every face / shoulder / stick-click button now flows through this pure
    /// edge sampler on the poll path instead of a `pressedChangedHandler` bound
    /// once to a profile object that a reconnect could strand (PRD-5 Phase 2.1
    /// — the real Apple TV "sticks work, buttons don't" fix).
    private var buttons = PadButtonSampler()
    /// Right-stick flick state: armed once the magnitude crosses 0.75, holding
    /// the peak deflection until the stick returns to rest.
    private var stickArmed = false
    private var stickPeak = SIMD2<Double>(0, 0)

    /// Gyro baseline for the trophy tilt (captured on first read, like
    /// `AfterglowMotion` — the player's holding pose is neutral, not flat).
    private var motionBaseline: SIMD2<Double>?

    // Diagnostics (Phase 0): all inert unless `diagnosticsEnabled`, except the
    // counters, which are cheap enough to always keep.
    private let log = Logger(subsystem: "com.couchsuite.couchkit", category: "padkit")
    /// Rising-edge count per button since adoption — the HUD's proof a physical
    /// press actually reached the poll path.
    private var edgeCounts: [PadButton: Int] = [:]
    private var gestureCount = 0
    private var lastGestureDescription: String?
    #endif

    public init() {}

    // MARK: Lifecycle

    public func start() {
        #if canImport(GameController)
        if diagnosticsEnabled {
            let all = GCController.controllers()
            log.debug("start: \(all.count, privacy: .public) controller(s); extended: \(all.filter { $0.extendedGamepad != nil }.map { $0.vendorName ?? "?" }.joined(separator: ","), privacy: .public)")
        }
        // Adopt any extended gamepad already paired at launch.
        for candidate in GCController.controllers() where candidate.extendedGamepad != nil {
            adopt(candidate)
            break
        }
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            nonisolated(unsafe) let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.handleConnect(controller) }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            nonisolated(unsafe) let controller = note.object as? GCController
            MainActor.assumeIsolated { self?.handleDisconnect(controller) }
        }
        #endif
    }

    public func stop() {
        #if canImport(GameController)
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
        connectObserver = nil
        disconnectObserver = nil
        teardownActive(emitDisconnect: false)
        #endif
    }

    // MARK: Motion (gyro trophy)

    /// Controller tilt as a gravity delta from the pose captured on first read,
    /// clamped to ±0.35 — the exact seam `AfterglowMotion` feeds on iPhone, so
    /// `BoardView.afterglowTilt` is platform-agnostic. Returns .zero (a calm,
    /// centered highlight) when the device has no motion sensors.
    public func motionTilt(at _: Date) -> SIMD2<Double> {
        #if canImport(GameController)
        guard let motion = controller?.motion else { return .zero }
        let current = SIMD2(motion.gravity.x, motion.gravity.y)
        guard let baseline = motionBaseline else {
            motionBaseline = current
            return .zero
        }
        let delta = current - baseline
        return SIMD2(
            min(max(delta.x, -0.35), 0.35),
            min(max(delta.y, -0.35), 0.35)
        )
        #else
        return .zero
        #endif
    }

    #if canImport(GameController)
    // MARK: Connection

    private func handleConnect(_ controller: GCController?) {
        guard let controller, controller.extendedGamepad != nil else { return }
        // Phase 2.3 — same-controller re-announce (profile replacement / wake).
        // The old guard returned here, silently leaving handlers on a dead
        // profile object forever. Polling already re-reads the live profile each
        // tick, so re-adopt only has to re-point motion/haptics and re-arm the
        // sampler, never reset the session.
        if controller === self.controller {
            if diagnosticsEnabled { log.debug("handleConnect: same-controller re-adopt \(controller.vendorName ?? "?", privacy: .public)") }
            reAdopt(controller)
            return
        }
        guard self.controller == nil else {
            if diagnosticsEnabled { log.debug("handleConnect: ignoring second controller \(controller.vendorName ?? "?", privacy: .public)") }
            return
        }
        if diagnosticsEnabled { log.debug("handleConnect: adopt \(controller.vendorName ?? "?", privacy: .public)") }
        adopt(controller)
    }

    /// Re-run the device-facing setup for a controller we already hold, without
    /// disturbing the session (no `.connect`, no `onConnectionChange`).
    private func reAdopt(_ controller: GCController) {
        #if canImport(CoreHaptics)
        haptics.stopAll()
        haptics.controller = controller
        #endif
        if let motion = controller.motion, motion.sensorsRequireManualActivation {
            motion.sensorsActive = true
        }
        motionBaseline = nil
        // Reset ALL per-device transient state, exactly as `adopt` does — a
        // re-announce mid-flick must not let a stale armed peak (or left-stick
        // momentum) misfire a placement on the replaced profile.
        buttons.reset()
        stickArmed = false
        stickPeak = .zero
        momentum = PadMomentum()
    }

    private func handleDisconnect(_ controller: GCController?) {
        guard let controller, controller === self.controller else { return }
        teardownActive(emitDisconnect: true)
        // A second pad may already be paired (a household with two): adopt it
        // immediately so the veil clears without a manual re-pair.
        for candidate in GCController.controllers() where candidate.extendedGamepad != nil {
            adopt(candidate)
            break
        }
    }

    private func adopt(_ controller: GCController) {
        self.controller = controller
        motionBaseline = nil
        stickArmed = false
        stickPeak = .zero
        buttons.reset()
        edgeCounts.removeAll()
        gestureCount = 0
        lastGestureDescription = nil
        momentum = PadMomentum()
        #if canImport(CoreHaptics)
        haptics.controller = controller
        #endif
        // Wake the device's motion sensors if it has any (DualSense/DualShock).
        // `sensorsRequireManualActivation` is read-only; when it's true the
        // engine stays dark until `sensorsActive` is set.
        if let motion = controller.motion, motion.sensorsRequireManualActivation {
            motion.sensorsActive = true
        }

        // No handler wiring: every button rides the poll path now (Phase 2.1).
        startPolling()

        isConnected = true
        onConnectionChange?(true)
        emit(.connect)
    }

    private func teardownActive(emitDisconnect: Bool) {
        pollTask?.cancel()
        pollTask = nil
        #if canImport(CoreHaptics)
        haptics.stopAll()
        haptics.controller = nil
        #endif
        controller = nil
        motionBaseline = nil
        buttons.reset()
        if isConnected {
            isConnected = false
            if emitDisconnect {
                onConnectionChange?(false)
                emit(.disconnect)
            } else {
                onConnectionChange?(false)
            }
        }
    }

    /// The single funnel for every gesture leaving the reader — keeps the
    /// diagnostic counters and the `--pad-probe` trace honest (Phase 0).
    private func emit(_ gesture: PadGesture) {
        gestureCount += 1
        if case .button(let button) = gesture { edgeCounts[button, default: 0] += 1 }
        if diagnosticsEnabled {
            lastGestureDescription = String(describing: gesture)
            log.debug("gesture \(String(describing: gesture), privacy: .public)")
        }
        onGesture?(gesture)
    }

    // MARK: Polling (sticks AND buttons — one 60 Hz loop, no handlers)

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60 Hz
                guard let self, let pad = self.controller?.extendedGamepad else { continue }
                let now = Date()
                let dt = min(0.1, now.timeIntervalSince(last))
                last = now
                self.pollButtons(pad)
                self.pollLeftStick(pad, dt: dt)
                self.pollRightStick(pad)
            }
        }
    }

    /// Sample every button off the LIVE profile this tick and let the pure
    /// sampler turn the edges into gestures (Phase 2.1). ≤16 ms worst-case
    /// latency — imperceptible, and nothing a `pressedChangedHandler` delivered
    /// is lost, while the stale-profile/handler-delivery failure modes are gone.
    private func pollButtons(_ pad: GCExtendedGamepad) {
        let frame = PadButtonFrame(
            cross: pad.buttonA.isPressed,
            circle: pad.buttonB.isPressed,
            square: pad.buttonX.isPressed,
            triangle: pad.buttonY.isPressed,
            l1: pad.leftShoulder.isPressed,
            r1: pad.rightShoulder.isPressed,
            l2: pad.leftTrigger.isPressed,
            r2: pad.rightTrigger.isPressed,
            r3: pad.rightThumbstickButton?.isPressed ?? false,
            // Phase 3.2 — DualSense's Create (left of the touchpad) is believed
            // to surface as `buttonOptions`, but this is UNVERIFIED until the
            // physical pad-probe session confirms which element lights (the
            // probe couldn't run in the sim). If disproven, swap this element and
            // fix the three label surfaces — see nine/DEVIATIONS.md pad section.
            options: pad.buttonOptions?.isPressed ?? false,
            dpadX: Double(pad.dpad.xAxis.value),
            dpadY: Double(pad.dpad.yAxis.value)
        )
        for gesture in buttons.sample(frame) { emit(gesture) }
    }

    private func pollLeftStick(_ pad: GCExtendedGamepad, dt: Double) {
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = Double(pad.leftThumbstick.yAxis.value)
        for step in momentum.accumulate(x: x, y: y, dt: dt) {
            emit(.move(step, glide: true))
        }
    }

    private func pollRightStick(_ pad: GCExtendedGamepad) {
        let x = Double(pad.rightThumbstick.xAxis.value)
        let y = Double(pad.rightThumbstick.yAxis.value)
        let magnitude = hypot(x, y)
        if !stickArmed {
            // The covenant: cross 0.75 to arm.
            if magnitude >= 0.75 {
                stickArmed = true
                stickPeak = SIMD2(x, y)
            }
        } else {
            if magnitude >= hypot(stickPeak.x, stickPeak.y) {
                stickPeak = SIMD2(x, y) // track the peak for the truest angle
            }
            // …and return to rest to register (no misfire while riding a corner).
            if magnitude <= 0.2 {
                emitStickFlick(dx: stickPeak.x, dy: stickPeak.y)
                stickArmed = false
                stickPeak = .zero
            }
        }
    }

    private func emitStickFlick(dx: Double, dy: Double) {
        switch PadMomentum.classifyStick(dx: dx, dy: dy, cone: ambiguityCone) {
        case .direction(let direction):
            emit(.flick(direction))
        case .ambiguous(let a, let b):
            emit(.flickAmbiguous(a, b))
        }
    }

    // MARK: Light bar (Phase 3)

    /// Paint the DualSense light bar (nil-safe: Xbox pads and unpaired devices
    /// have no `light` and are a no-op). Nine calls this from the accent color
    /// when a pad session begins — ~zero cost, high delight.
    public func setLight(red: Double, green: Double, blue: Double) {
        guard let light = controller?.light else { return }
        light.color = GCColor(red: Float(red), green: Float(green), blue: Float(blue))
    }

    // MARK: Diagnostics snapshot (Phase 0)

    /// A read-only census of the adopted device for the DEBUG pad-probe HUD:
    /// live pressed/axis state, per-button poll-edge counts (proof a physical
    /// press reached the poll path), and the controllers() population.
    public func debugSnapshot() -> PadDebugSnapshot {
        let all = GCController.controllers()
        let pad = controller?.extendedGamepad
        func pressed(_ b: GCControllerButtonInput?) -> Bool { b?.isPressed ?? false }
        return PadDebugSnapshot(
            adopted: controller != nil,
            vendorName: controller?.vendorName,
            controllerCount: all.count,
            extendedCount: all.filter { $0.extendedGamepad != nil }.count,
            pressed: [
                .cross: pressed(pad?.buttonA), .circle: pressed(pad?.buttonB),
                .square: pressed(pad?.buttonX), .triangle: pressed(pad?.buttonY),
                .l1: pressed(pad?.leftShoulder), .r1: pressed(pad?.rightShoulder),
                .l2: pressed(pad?.leftTrigger), .r2: pressed(pad?.rightTrigger),
                .r3: pressed(pad?.rightThumbstickButton), .options: pressed(pad?.buttonOptions),
            ],
            edgeCounts: edgeCounts,
            leftStick: SIMD2(Double(pad?.leftThumbstick.xAxis.value ?? 0), Double(pad?.leftThumbstick.yAxis.value ?? 0)),
            rightStick: SIMD2(Double(pad?.rightThumbstick.xAxis.value ?? 0), Double(pad?.rightThumbstick.yAxis.value ?? 0)),
            dpad: SIMD2(Double(pad?.dpad.xAxis.value ?? 0), Double(pad?.dpad.yAxis.value ?? 0)),
            gestureCount: gestureCount,
            lastGesture: lastGestureDescription
        )
    }
    #endif
}

// MARK: - Debug snapshot (Phase 0)

/// Immutable census the pad-probe HUD renders. Pure value type so the HUD can
/// hold it in `@State` and diff it frame to frame.
public struct PadDebugSnapshot: Sendable, Equatable {
    public var adopted: Bool
    public var vendorName: String?
    public var controllerCount: Int
    public var extendedCount: Int
    /// Live `isPressed` per button this instant.
    public var pressed: [PadButton: Bool]
    /// Rising-edge count per button since adoption (poll path).
    public var edgeCounts: [PadButton: Int]
    public var leftStick: SIMD2<Double>
    public var rightStick: SIMD2<Double>
    public var dpad: SIMD2<Double>
    public var gestureCount: Int
    public var lastGesture: String?

    public init(
        adopted: Bool = false, vendorName: String? = nil, controllerCount: Int = 0,
        extendedCount: Int = 0, pressed: [PadButton: Bool] = [:],
        edgeCounts: [PadButton: Int] = [:], leftStick: SIMD2<Double> = .zero,
        rightStick: SIMD2<Double> = .zero, dpad: SIMD2<Double> = .zero,
        gestureCount: Int = 0, lastGesture: String? = nil
    ) {
        self.adopted = adopted; self.vendorName = vendorName
        self.controllerCount = controllerCount; self.extendedCount = extendedCount
        self.pressed = pressed; self.edgeCounts = edgeCounts
        self.leftStick = leftStick; self.rightStick = rightStick; self.dpad = dpad
        self.gestureCount = gestureCount; self.lastGesture = lastGesture
    }
}
#endif
