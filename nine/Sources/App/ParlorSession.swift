// ParlorSession.swift — the live half of a parlor (PRD-28 §4, §5).
//
// The rules about *what* a parlor is — the invite, its two envelopes, the
// provenance guard, the roster and the reveal — are all in
// `Sources/Shared/Parlor.swift`, pure and Linux-clean. This type is the plumbing
// around them: it holds the room, throttles what goes out, and enforces the one
// timing rule that cannot be expressed as a value — **a finish is sent only once
// the room says everybody is done.**
//
// **It is written against a transport protocol rather than against
// GroupActivities**, and that is not architecture for its own sake. A FaceTime
// call cannot be placed between two simulators, and this machine's simulators are
// slimmed with the `messaging` category disabled, so a live group session cannot
// exist on the development lane at all. The seam is what makes the presence row,
// the reveal and the accessibility tree drivable — the same position PRD-31 took
// on the Pencil recognizer, which was measured against constructed strokes
// because no simulator has ever held a Pencil.
import Foundation
import Observation
#if canImport(GroupActivities)
import GroupActivities
#endif
#if canImport(NineEngine)
import NineEngine
#endif

// MARK: - The seam

/// Everything a parlor needs from the outside world.
///
/// Four members and no session type in sight: who I am, what arrived, who is
/// still here, and how to speak. Both implementations below are small because
/// this is small.
@MainActor
protocol ParlorTransport: AnyObject {
    var localParticipant: UUID { get }
    var onEnvelope: ((UUID, ParlorEnvelope) -> Void)? { get set }
    /// The full roster, every time it changes. A `Set` rather than a
    /// join/leave pair because `ParlorRoom.retain` takes the truth rather than
    /// a delta, and a delta stream is one dropped event from a ghost dot.
    var onRoster: ((Set<UUID>) -> Void)? { get set }
    func send(_ envelope: ParlorEnvelope)
    func leave()
}

// MARK: - The session

@MainActor
@Observable
final class ParlorSession {

    /// The board everyone is on, or nil when there is no parlor.
    private(set) var invite: ParlorInvite?

    /// The roster and the reveal. Nil outside a parlor, so every surface's
    /// "should I draw this" is one optional test.
    private(set) var room: ParlorRoom?

    /// An invite that arrived while the app was elsewhere — from a Game Center
    /// activity at launch, or from a SharePlay session accepted on the Home
    /// Screen. The shelf picks it up and opens the board.
    private(set) var pendingInvite: ParlorInvite?

    @ObservationIgnored private var transport: (any ParlorTransport)?
    /// My own finish, minted at solve time and held until the room agrees.
    @ObservationIgnored private var heldFinish: ParlorFinish?
    @ObservationIgnored private var finishSent = false
    /// The last presence actually put on the wire, so an unchanged board sends
    /// nothing. The board's own autosave ticks at 0.6 s and a placement can
    /// fire several observations; a message per observation is a message per
    /// frame on somebody else's radio.
    @ObservationIgnored private var lastSent: ParlorPresence?

    var isActive: Bool { room != nil }

    // MARK: Lifecycle

    /// Join a parlor on a board with `fillable` empty cells.
    func join(invite: ParlorInvite, fillable: Int, over transport: any ParlorTransport) {
        leave()
        self.invite = invite
        self.transport = transport
        room = ParlorRoom(me: transport.localParticipant, fillable: fillable)
        transport.onEnvelope = { [weak self] id, envelope in
            self?.receive(envelope, from: id)
        }
        transport.onRoster = { [weak self] ids in
            self?.room?.retain(ids)
            self?.publishFinishIfReady()
        }
    }

    func leave() {
        transport?.leave()
        transport = nil
        invite = nil
        room = nil
        heldFinish = nil
        finishSent = false
        lastSent = nil
    }

    func offer(_ invite: ParlorInvite) { pendingInvite = invite }
    func takePendingInvite() -> ParlorInvite? {
        defer { pendingInvite = nil }
        return pendingInvite
    }

    // MARK: Outbound

    /// Tell the room where this board stands.
    ///
    /// Idempotent and self-throttling: an unchanged presence sends nothing, so
    /// this can be called from wherever the board changes without anybody having
    /// to reason about how often that is.
    func report(fill: Int, done: Bool, fillable: Int? = nil) {
        guard let transport, room != nil else { return }
        // The denominator can arrive after the room does — a session accepted
        // on the Home Screen joins before its board has finished composing.
        if let fillable { room?.rebase(fillable: fillable) }
        let presence = ParlorPresence(fill: fill, done: done)
        room?.update(presence, from: transport.localParticipant)
        if presence != lastSent {
            lastSent = presence
            transport.send(ParlorEnvelope(presence: presence))
        }
        publishFinishIfReady()
    }

    /// Hand the session this device's finished solve. **It does not go out
    /// here.** It goes out when — and only when — the room completes, which is
    /// the same predicate on every device, so everybody's number arrives at
    /// once and nobody is waiting on a host.
    func hold(finish: ParlorFinish) {
        guard room != nil else { return }
        heldFinish = finish
        publishFinishIfReady()
    }

    // MARK: Inbound

    private func receive(_ envelope: ParlorEnvelope, from id: UUID) {
        if let presence = envelope.presence { room?.update(presence, from: id) }
        if let finish = envelope.finish { room?.record(finish, from: id) }
        publishFinishIfReady()
    }

    /// The one timing rule in this file.
    private func publishFinishIfReady() {
        guard let transport, let room, let finish = heldFinish, !finishSent,
              room.mayPublishFinish else { return }
        finishSent = true
        // Recorded locally as well as sent: the sender is a member of its own
        // room, and a card that showed everybody's time but yours would be a
        // strange kind of modesty.
        self.room?.record(finish, from: transport.localParticipant)
        transport.send(ParlorEnvelope(finish: finish))
    }
}

// MARK: - The live transport (SharePlay)

// `#if os(iOS)` rather than `#if canImport(GroupActivities)`: the framework
// imports on macOS and tvOS too, and PRD-28 §9 ships this on iOS only. PRD-30
// records the same distinction for ActivityKit, where `canImport` was true on
// the Mac and the build then failed on the conformance.
#if os(iOS)

/// The activity every participant is in.
///
/// Its `Codable` payload is the invite and nothing else — eight bytes and a
/// tier — because the board is a pure function of those and the grid never
/// crosses the wire.
struct NineParlorActivity: GroupActivity {
    let invite: ParlorInvite

    var metadata: GroupActivityMetadata {
        var data = GroupActivityMetadata()
        data.title = Strings.string("parlor.activity.title")
        data.subtitle = Strings.string("parlor.activity.subtitle")
        // `.generic`, not `.playTogether`: the system's play-together experience
        // wants a shared game state to keep in step, and there isn't one — this
        // is N solitary boards that happen to be the same board.
        data.type = .generic
        // Everyone keeps their own board when the person who started it hangs
        // up, which is what "the boards are ordinary library boards" means.
        data.lifetimePolicy = .automatic
        return data
    }
}

extension ParlorSession {
    /// Ask the system to start a group session for this board.
    ///
    /// Returns false when there is no call to share into, or when the player
    /// declined the system's own sheet. **The caller opens the board anyway** —
    /// a parlor that could not be started is a solitary board, which is the
    /// honest degradation and the one every other transport failure in this
    /// app already takes.
    static func activate(_ invite: ParlorInvite) async -> Bool {
        let activity = NineParlorActivity(invite: invite)
        guard await activity.prepareForActivation() == .activationPreferred else { return false }
        return (try? await activity.activate()) ?? false
    }
}

@MainActor
final class GroupParlorTransport: ParlorTransport {
    let localParticipant: UUID
    var onEnvelope: ((UUID, ParlorEnvelope) -> Void)?
    var onRoster: ((Set<UUID>) -> Void)?

    private let session: GroupSession<NineParlorActivity>
    private let messenger: GroupSessionMessenger
    private var tasks: [Task<Void, Never>] = []

    init(session: GroupSession<NineParlorActivity>) {
        self.session = session
        self.messenger = GroupSessionMessenger(session: session)
        self.localParticipant = session.localParticipant.id
        listen()
        session.join()
    }

    private func listen() {
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await (envelope, context) in messenger.messages(of: ParlorEnvelope.self) {
                onEnvelope?(context.source.id, envelope)
            }
        })
        tasks.append(Task { [weak self] in
            guard let self else { return }
            for await participants in session.$activeParticipants.values {
                onRoster?(Set(participants.map(\.id)))
            }
        })
    }

    func send(_ envelope: ParlorEnvelope) {
        // Fire-and-forget, exactly like every Game Center submission in this
        // app: a dropped presence message costs one stale dot for a few
        // seconds, and the next placement corrects it. Nothing here is worth
        // interrupting somebody's board for.
        Task { try? await messenger.send(envelope) }
    }

    func leave() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        session.leave()
    }
}
#endif

// MARK: - The loopback transport

// DEBUG only, and sealed: `ParlorSealTests` fails if this name appears outside
// a `#if DEBUG` fence, which is the arrangement PRD-23 used to keep the variant
// channel out of Release and PRD-24 re-aimed rather than deleted.
#if DEBUG
/// A parlor with nobody in it but ghosts.
///
/// Two synthetic participants fill their boards at fixed rates and finish, which
/// is enough to drive every surface this PRD adds: the dots, the ordering, the
/// reveal, the comets and the accessibility tree. It is reached only by
/// `-parlor-demo`, and it exists because the alternative on this lane is a
/// feature nobody has ever seen run.
@MainActor
final class LoopbackParlorTransport: ParlorTransport {
    let localParticipant = UUID(uuidString: "00000000-0000-0000-0000-00000000FACE")!
    var onEnvelope: ((UUID, ParlorEnvelope) -> Void)?
    var onRoster: ((Set<UUID>) -> Void)?

    /// Ordered after the local participant's id, so the demo row reads
    /// you-then-them and matches what a real session would show.
    private let ghosts: [(id: UUID, cellsPerTick: Int, seconds: Int)] = [
        (UUID(uuidString: "00000000-0000-0000-0000-0000000FEED1")!, 2, 214),
        (UUID(uuidString: "00000000-0000-0000-0000-0000000FEED2")!, 3, 168),
    ]
    private let fillable: Int
    private var fills: [UUID: Int] = [:]
    private var ticker: Task<Void, Never>?

    init(fillable: Int) {
        self.fillable = max(1, fillable)
        for ghost in ghosts { fills[ghost.id] = 0 }
    }

    func start() {
        onRoster?(Set([localParticipant] + ghosts.map(\.id)))
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    private func tick() {
        for ghost in ghosts {
            let filled = min(fillable, (fills[ghost.id] ?? 0) + ghost.cellsPerTick)
            fills[ghost.id] = filled
            let done = filled >= fillable
            onEnvelope?(ghost.id, ParlorEnvelope(
                presence: ParlorPresence(fill: filled, done: done)))
            if done {
                onEnvelope?(ghost.id, ParlorEnvelope(
                    finish: ParlorFinish(seconds: ghost.seconds, packed: Data())))
            }
        }
    }

    func send(_ envelope: ParlorEnvelope) {}

    func leave() {
        ticker?.cancel()
        ticker = nil
    }
}
#endif
