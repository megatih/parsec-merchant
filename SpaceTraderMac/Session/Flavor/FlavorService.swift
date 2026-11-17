// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights

/// A generated flavor ready to be cached in the journal (LLM-021).
nonisolated struct FlavorResult: Sendable, Equatable {
    var entryID: Int
    var gameID: String
    var text: FlavorText
}

/// LLM-018…023: the session's flavor service. Template lines are attached by the journal recorder; this service only
/// asks the on-device model for prose in `foundationModels` mode, one request at a time, off the main actor.
@MainActor
final class FlavorService: SessionFlavor {
    /// Generates prose for one request (the Foundation Models provider in production, fakes in tests).
    typealias Generator = @Sendable (FlavorRequest, FlavorNames) async -> FlavorText?

    struct Job: Equatable {
        var request: FlavorRequest
        var gameID: String
        var names: FlavorNames
        var epoch: Int
    }

    static let maxWaiting = 8

    private(set) var mode: FlavorMode
    private let makeGenerator: () -> Generator?
    private var generator: Generator?
    /// LLM-024: true once a model provider was created (never in `templateForced` mode).
    private(set) var providerCreated = false
    private(set) var waiting: [Job] = []
    private(set) var inFlight: Job?
    private var task: Task<Void, Never>?
    /// Bumped by `cancelAll`, so a cancelled request's late answer is ignored.
    private var epoch = 0
    private var handler: ((FlavorResult) -> Void)?

    var isTemplateOnly: Bool { mode != .foundationModels }

    /// `generator` defaults to the system Foundation Models provider (nil when the framework is not in this build).
    init(mode: FlavorMode, generator: (() -> Generator?)? = nil) {
        self.mode = mode
        makeGenerator = generator ?? {
            guard let provider = FoundationModelsFlavorProvider.system() else { return nil }
            return { request, names in await provider.flavor(for: request, names: names) }
        }
    }

    func setResultHandler(_ handler: @escaping (FlavorResult) -> Void) {
        self.handler = handler
    }

    /// LLM-026: leaving `foundationModels` cancels the queue; generated texts already cached stay.
    func setMode(_ new: FlavorMode) {
        guard new != mode else { return }
        if mode == .templateForced { return }  // a launch argument cannot be overridden by Settings
        mode = new
        if new != .foundationModels { cancelAll() }
    }

    /// LLM-018: enqueues every new entry that has a flavor subject and still carries its template.
    func enqueue(_ entries: [LogEntry], gameID: String, names: () -> FlavorNames) {
        guard mode == .foundationModels else { return }
        let requests = entries.compactMap { entry -> FlavorRequest? in
            if case .generated = entry.flavor { return nil }
            return FlavorRequest(entry: entry)
        }
        guard !requests.isEmpty else { return }
        let n = names()
        for r in requests {
            waiting.append(Job(request: r, gameID: gameID, names: n, epoch: epoch))
            // LLM-019: the oldest waiting request is dropped first (it keeps its template).
            if waiting.count > Self.maxWaiting { waiting.removeFirst() }
        }
        pump()
    }

    /// LLM-019: Close Game, New Game, load and leaving the mode cancel everything waiting and in flight.
    func cancelAll() {
        epoch += 1
        waiting = []
        task?.cancel()
        task = nil
        inFlight = nil
    }

    private func pump() {
        guard task == nil, !waiting.isEmpty else { return }
        if generator == nil {
            generator = makeGenerator()
            providerCreated = true
        }
        guard let generator else {
            waiting = []
            return
        }
        let job = waiting.removeFirst()
        inFlight = job
        task = Task { [weak self] in
            let text = await Self.run(generator, job)
            self?.finish(job, text: text)
        }
    }

    /// Runs the generator in a detached task (off the main actor), cancelled with the caller.
    nonisolated private static func run(_ generator: @escaping Generator, _ job: Job) async -> FlavorText? {
        let work = Task.detached { await generator(job.request, job.names) }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private func finish(_ job: Job, text: FlavorText?) {
        guard job.epoch == epoch else { return }
        task = nil
        inFlight = nil
        // LLM-020: nil keeps the template already in the entry.
        if mode == .foundationModels, let text, case .generated = text {
            handler?(FlavorResult(entryID: job.request.entryID, gameID: job.gameID, text: text))
        }
        pump()
    }
}
