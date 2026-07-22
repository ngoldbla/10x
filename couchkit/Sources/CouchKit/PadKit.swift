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
#if os(tvOS)
import Foundation
import CouchCore
#if canImport(GameController)
import GameController
#endif
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// MARK: - Gestures

/// The pad's face / shoulder buttons, named by their PRD-5 §2.1 role rather
/// than a vendor glyph (Cross/Circle/Square/Triangle on DualSense; A/B/X/Y on
/// Xbox map to the same positions through GameController's profile).
public enum PadButton: Sendable, Equatable {
    case cross     // place-into-rose (learning mode) / confirm
    case circle    // erase user entry / cancel rose
    case square    // sticky pencil toggle
    case triangle  // same-number highlight toggle
    case r3        // right-stick click → place 5 (center petal)
    case l1        // previous empty cell
    case r1        // next empty cell
    case l2        // peek (hold): dim all but the highlighted kind
    case options   // prefs sheet
}

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

// MARK: - Controller haptics provider

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

    #if canImport(GameController)
    private var controller: GCController?
    private var connectObserver: (any NSObjectProtocol)?
    private var disconnectObserver: (any NSObjectProtocol)?
    private var pollTask: Task<Void, Never>?

    private var momentum = PadMomentum()
    /// Right-stick flick state: armed once the magnitude crosses 0.75, holding
    /// the peak deflection until the stick returns to rest.
    private var stickArmed = false
    private var stickPeak = SIMD2<Double>(0, 0)
    private var lastDpad: Direction4?

    /// Gyro baseline for the trophy tilt (captured on first read, like
    /// `AfterglowMotion` — the player's holding pose is neutral, not flat).
    private var motionBaseline: SIMD2<Double>?
    #endif

    public init() {}

    // MARK: Lifecycle

    public func start() {
        #if canImport(GameController)
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
        guard self.controller == nil, let controller, controller.extendedGamepad != nil else { return }
        adopt(controller)
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
        lastDpad = nil
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

        wireButtons(controller.extendedGamepad)
        startPolling()

        isConnected = true
        onConnectionChange?(true)
        onGesture?(.connect)
    }

    private func teardownActive(emitDisconnect: Bool) {
        pollTask?.cancel()
        pollTask = nil
        if let pad = controller?.extendedGamepad { unwireButtons(pad) }
        #if canImport(CoreHaptics)
        haptics.stopAll()
        haptics.controller = nil
        #endif
        controller = nil
        motionBaseline = nil
        if isConnected {
            isConnected = false
            if emitDisconnect {
                onConnectionChange?(false)
                onGesture?(.disconnect)
            } else {
                onConnectionChange?(false)
            }
        }
    }

    // MARK: Button wiring (edge-triggered; the handler queue is main)

    private func wireButtons(_ pad: GCExtendedGamepad?) {
        guard let pad else { return }
        press(pad.buttonA) { [weak self] in self?.onGesture?(.button(.cross)) }
        press(pad.buttonB) { [weak self] in self?.onGesture?(.button(.circle)) }
        press(pad.buttonX) { [weak self] in self?.onGesture?(.button(.square)) }
        press(pad.buttonY) { [weak self] in self?.onGesture?(.button(.triangle)) }
        press(pad.leftShoulder) { [weak self] in self?.onGesture?(.button(.l1)) }
        press(pad.rightShoulder) { [weak self] in self?.onGesture?(.button(.r1)) }
        pad.rightThumbstickButton.map { button in
            press(button) { [weak self] in self?.onGesture?(.button(.r3)) }
        }
        pad.buttonOptions.map { button in
            press(button) { [weak self] in self?.onGesture?(.button(.options)) }
        }
        // L2 is a hold: peek begins on press, restores on release.
        pad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                self?.onGesture?(pressed ? .button(.l2) : .buttonUp(.l2))
            }
        }
        // D-pad is the precision single-step fallback: fire once per press.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.handleDpad(x: Double(x), y: Double(y)) }
        }
    }

    private func unwireButtons(_ pad: GCExtendedGamepad) {
        for button in [pad.buttonA, pad.buttonB, pad.buttonX, pad.buttonY,
                       pad.leftShoulder, pad.rightShoulder, pad.leftTrigger,
                       pad.rightThumbstickButton, pad.buttonOptions].compactMap({ $0 }) {
            button.pressedChangedHandler = nil
        }
        pad.dpad.valueChangedHandler = nil
    }

    /// Attach a fire-on-press handler (ignore the release edge).
    private func press(_ button: GCControllerButtonInput, _ action: @escaping @MainActor () -> Void) {
        button.pressedChangedHandler = { _, _, pressed in
            MainActor.assumeIsolated { if pressed { action() } }
        }
    }

    private func handleDpad(x: Double, y: Double) {
        // Single-step on the transition into a direction; nothing on release.
        guard let direction = PadMomentum.direction(x: x, y: y, deadzone: 0.5) else {
            lastDpad = nil
            return
        }
        guard direction != lastDpad else { return }
        lastDpad = direction
        onGesture?(.move(direction, glide: false))
    }

    // MARK: Polling (sticks — held deflections must re-fire)

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
                self.pollLeftStick(pad, dt: dt)
                self.pollRightStick(pad)
            }
        }
    }

    private func pollLeftStick(_ pad: GCExtendedGamepad, dt: Double) {
        let x = Double(pad.leftThumbstick.xAxis.value)
        let y = Double(pad.leftThumbstick.yAxis.value)
        for step in momentum.accumulate(x: x, y: y, dt: dt) {
            onGesture?(.move(step, glide: true))
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
            onGesture?(.flick(direction))
        case .ambiguous(let a, let b):
            onGesture?(.flickAmbiguous(a, b))
        }
    }
    #endif
}
#endif
