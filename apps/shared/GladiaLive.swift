import Foundation

/// Les partiels remplacent une phrase ; les phrases terminées s'accumulent.
struct LiveTranscript {
    private var order: [String] = []
    private var phrases: [String: (text: String, final: Bool)] = [:]

    mutating func update(id: String, text: String, final: Bool) -> String {
        if phrases[id] == nil, order.count < 128 { order.append(id) }
        if order.contains(id), phrases[id]?.final != true {
            phrases[id] = (text.trimmingCharacters(in: .whitespacesAndNewlines), final)
        }
        return order.compactMap { phrases[$0]?.text }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Apple reste prêt en secours, mais ne remplace jamais le direct Gladia actif.
struct DictationText {
    private(set) var usingGladia = true
    private(set) var apple = ""
    private(set) var gladia = ""
    var displayed: String { usingGladia ? gladia : (apple.isEmpty ? gladia : apple) }

    mutating func updateApple(_ text: String) { apple = text }
    mutating func updateGladia(_ text: String) { gladia = text }
    mutating func fallback() { usingGladia = false }
}

@MainActor
final class GladiaLive {
    typealias Audio = AsyncThrowingStream<Data, Error>
    enum Failure: Error { case unavailable, overflow }

    static func endpoint(transcribe: URL?) -> URL? {
        guard let transcribe, var parts = URLComponents(url: transcribe, resolvingAgainstBaseURL: false),
              parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = parts.scheme == "https" ? "wss" : "ws"
        parts.path += "/live"
        return parts.url
    }

    private var socket: URLSessionWebSocketTask?
    private var receiving: Task<Void, Never>?
    private var sending: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var transcript = LiveTranscript()
    private var finished = false
    private var onText: ((String) -> Void)?
    private var onFallback: (() -> Void)?

    func start(transcribe: URL?, audio: Audio, onText: @escaping (String) -> Void,
               onFallback: @escaping () -> Void) {
        self.onText = onText; self.onFallback = onFallback
        guard let endpoint = Self.endpoint(transcribe: transcribe) else { fail(); return }
        let socket = URLSession.shared.webSocketTask(with: endpoint)
        socket.maximumMessageSize = 128_000
        self.socket = socket
        socket.resume()
        setDeadline(seconds: 5)
        receiving = Task { [weak self] in
            guard let self else { return }
            do {
                var ready = false
                while !finished {
                    let message = try await socket.receive()
                    guard !finished else { return }
                    guard case .string(let raw) = message,
                          let data = raw.data(using: .utf8),
                          let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = event["type"] as? String else { throw Failure.unavailable }
                    switch type {
                    case "ready":
                        guard !ready else { throw Failure.unavailable }
                        ready = true
                        deadline?.cancel()
                        sending = Task { [weak self] in
                            do {
                                for try await chunk in audio { try await socket.send(.data(chunk)) }
                                try Task.checkCancellation()
                                try await socket.send(.string("{\"type\":\"stop\"}"))
                                self?.setDeadline(seconds: 6)
                            } catch { self?.fail() }
                        }
                    case "transcript":
                        guard ready, let id = event["id"] as? String,
                              let text = event["text"] as? String,
                              let final = event["final"] as? Bool else { throw Failure.unavailable }
                        onText(transcript.update(id: id, text: text, final: final))
                    case "done": cancel()
                    default: throw Failure.unavailable
                    }
                }
            } catch { fail() }
        }
    }

    private func setDeadline(seconds: UInt64) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
            catch { return }
            self?.fail()
        }
    }

    private func fail() {
        guard !finished else { return }
        let fallback = onFallback
        cancel()
        fallback?()
    }

    func waitForCompletion() async {
        await receiving?.value
    }

    func cancel() {
        finished = true
        receiving?.cancel(); receiving = nil
        sending?.cancel(); sending = nil
        deadline?.cancel(); deadline = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        onText = nil; onFallback = nil
    }
}
